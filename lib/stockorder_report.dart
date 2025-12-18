import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'widgets/app_drawer.dart';

class StockOrderReportPage extends StatefulWidget {
  final String? initialBranchId;
  final DateTime? initialFromDate;
  final DateTime? initialToDate;

  const StockOrderReportPage({
    super.key,
    this.initialBranchId,
    this.initialFromDate,
    this.initialToDate,
  });

  @override
  State<StockOrderReportPage> createState() => _StockOrderReportPageState();
}

class _StockOrderReportPageState extends State<StockOrderReportPage> {
  bool _loading = true;
  bool _loadingBranches = true;
  DateTime? fromDate;
  DateTime? toDate;
  List<Map<String, String>> branches = [];
  String selectedBranchId = 'ALL';
  List<Map<String, dynamic>> stockOrders = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> departments = [];
  Map<String, dynamic>? _combinedOrder;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    fromDate = widget.initialFromDate ?? now;
    toDate = widget.initialToDate ?? now;
    if (widget.initialBranchId != null) {
      selectedBranchId = widget.initialBranchId!;
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _fetchBranches();
    await _fetchDepartments();
    await _fetchCategories();
    await _fetchStockOrders();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _fetchBranches() async {
    setState(() => _loadingBranches = true);
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/branches?limit=1000'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        final list = <Map<String, String>>[
          {'id': 'ALL', 'name': 'All Branches'}
        ];
        for (var b in docs) {
          final id = (b['id'] ?? b['_id'])?.toString();
          final name = (b['name'] ?? 'Unnamed Branch').toString();
          if (id != null) list.add({'id': id, 'name': name});
        }
        setState(() => branches = list);
      }
    } catch (e) {
      debugPrint('fetchBranches error: $e');
    } finally {
      setState(() => _loadingBranches = false);
    }
  }

  Future<void> _fetchDepartments() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/departments?limit=1000'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        setState(() {
          departments = docs.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('fetchDepartments error: $e');
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/categories?limit=1000&depth=1'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        setState(() {
          categories = docs.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('fetchCategories error: $e');
    }
  }

  Future<void> _fetchStockOrders() async {
    if (fromDate == null) return;
    setState(() => _loading = true);
    try {
      final token = await _getToken();
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);

      var url = 'https://admin.theblackforestcakes.com/api/stock-orders?limit=1000&depth=2'
          '&where[deliveryDate][greater_than]=${start.toUtc().toIso8601String()}'
          '&where[deliveryDate][less_than]=${end.toUtc().toIso8601String()}';

      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }

      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];

        setState(() {
          stockOrders = docs.cast<Map<String, dynamic>>();
          stockOrders.sort((a, b) {
            final dateA = DateTime.tryParse(a['createdAt'] ?? '');
            final dateB = DateTime.tryParse(b['createdAt'] ?? '');
            if (dateA == null && dateB == null) return 0;
            if (dateA == null) return 1;
            if (dateB == null) return -1;
            return dateB.compareTo(dateA);
          });
          _calculateCombinedOrder();
        });
      }
    } catch (e) {
      debugPrint('fetchStockOrders error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }
  void _calculateCombinedOrder() {
    if (stockOrders.isEmpty) {
      _combinedOrder = null;
      return;
    }

    final Map<String, Map<String, dynamic>> itemMap = {};
    final Set<String> branchNames = {};

    for (var order in stockOrders) {
      // Branch Name processing
      String bName = 'Unknown';
      if (order['branch'] is Map && order['branch']['name'] != null) {
        bName = order['branch']['name'].toString();
      } else if (order['branch'] is String) {
        bName = order['branch'];
      }

      final cleanName = bName.trim();
      if (cleanName.isNotEmpty) {
        if (cleanName.length > 3) {
          branchNames.add(cleanName.substring(0, 3));
        } else {
          branchNames.add(cleanName);
        }
      }

      // Items aggregation
      final items = (order['items'] as List?) ?? [];
      for (var item in items) {
        // We still need to preserve category info for the grouped display later
        // So we grab it here and store it in the aggregated item
        
        dynamic categoryData; 
        if (item['product'] is Map && item['product']['category'] != null) {
           categoryData = item['product']['category'];
        } else if (item['category'] != null) {
           categoryData = item['category'];
        }

        final name = item['name'] ?? 'Unknown';
        if (!itemMap.containsKey(name)) {
          itemMap[name] = {
            'name': name,
            'category': categoryData,
            'requiredQty': 0,
            'requiredAmount': 0.0,
            'sendingQty': 0,
            'sendingAmount': 0.0,
            'confirmedQty': 0,
            'pickedQty': 0,
            'receivedQty': 0,
            'receivedAmount': 0.0,
            'differenceQty': 0,
          };
        }

        final cur = itemMap[name]!;
        cur['requiredQty'] = (cur['requiredQty'] as int) + ((item['requiredQty'] ?? 0) as int);
        cur['requiredAmount'] = (cur['requiredAmount'] as double) + ((item['requiredAmount'] ?? 0) as num).toDouble();
        cur['sendingQty'] = (cur['sendingQty'] as int) + ((item['sendingQty'] ?? 0) as int);
        cur['sendingAmount'] = (cur['sendingAmount'] as double) + ((item['sendingAmount'] ?? 0) as num).toDouble();
        cur['confirmedQty'] = (cur['confirmedQty'] as int) + ((item['confirmedQty'] ?? 0) as int);
        cur['pickedQty'] = (cur['pickedQty'] as int) + ((item['pickedQty'] ?? 0) as int);
        cur['receivedQty'] = (cur['receivedQty'] as int) + ((item['receivedQty'] ?? 0) as int);
        cur['receivedAmount'] = (cur['receivedAmount'] as double) + ((item['receivedAmount'] ?? 0) as num).toDouble();
        cur['differenceQty'] = (cur['differenceQty'] as int) + ((item['differenceQty'] ?? 0) as int);
        
        // Ensure category is set if missing in the first occurrence
        if (cur['category'] == null && categoryData != null) {
             cur['category'] = categoryData;
        }
      }
    }

    final combinedItems = itemMap.values.toList();

    _combinedOrder = {
      'invoiceNumber': 'ALL DET',
      'branch': {'name': branchNames.join(',')},
      'status': 'Combined',
      'createdAt': DateTime.now().toIso8601String(),
      'deliveryDate': DateTime.now().toIso8601String(),
      'items': combinedItems,
    };
  }

  List<Map<String, dynamic>> _groupItemsWithHeaders(List<dynamic> items) {
    if (items.isEmpty) return [];

    // Structure: DeptName -> { CatName -> [Items] }
    final Map<String, Map<String, List<Map<String, dynamic>>>> hierarchyMap = {};

    for (var item in items) {
      // 1. Determine Category Name and Object
      String categoryName = 'Unknown Category';
      Map<String, dynamic>? categoryObj;

      if (item['product'] is Map && item['product']['category'] != null) {
        final cat = item['product']['category'];
        if (cat is Map) {
          categoryName = cat['name'] ?? 'Unknown Category';
          categoryObj = cat as Map<String, dynamic>;
        } else if (cat is String) {
          final found = categories.firstWhere((c) => c['id'] == cat || c['_id'] == cat, orElse: () => {});
          if (found.isNotEmpty) {
            categoryName = found['name'];
            categoryObj = found;
          }
        }
      } else if (item['category'] != null) {
        final cat = item['category'];
        if (cat is Map) {
          categoryName = cat['name'] ?? 'Unknown Category';
          categoryObj = cat as Map<String, dynamic>;
        } else if (cat is String) {
          final found = categories.firstWhere((c) => c['id'] == cat || c['_id'] == cat, orElse: () => {});
          if (found.isNotEmpty) {
            categoryName = found['name'];
            categoryObj = found;
          }
        }
      }

      // Refresh categoryObj from local categories list to ensure we have Department info
      if (categoryObj != null) {
        final catId = categoryObj['id'] ?? categoryObj['_id'];
        if (catId != null) {
           final found = categories.firstWhere((c) => c['id'] == catId || c['_id'] == catId, orElse: () => {});
           if (found.isNotEmpty) {
             categoryObj = found;
             categoryName = found['name'] ?? categoryName;
           }
        }
      }

      // 2. Determine Department Name from Category
      String deptName = 'Unknown Department';
      if (categoryObj != null) {
        // Check local category object first (if populated)
        if (categoryObj['department'] != null) {
          final dept = categoryObj['department'];
          if (dept is Map) {
            deptName = dept['name'] ?? 'Unknown Department';
          } else if (dept is String) {
             // Look up in fetched departments
             final foundDept = departments.firstWhere((d) => d['id'] == dept || d['_id'] == dept, orElse: () => {});
             if (foundDept.isNotEmpty) {
               deptName = foundDept['name'];
             }
          }
        } else {
           // If categoryObj came from 'product.category' which might be partial
           // Try to find the full category object in our fetched list to get department
           final catId = categoryObj['id'] ?? categoryObj['_id'];
           if (catId != null) {
             final fullCat = categories.firstWhere((c) => c['id'] == catId || c['_id'] == catId, orElse: () => {});
             if (fullCat.isNotEmpty && fullCat['department'] != null) {
                final dept = fullCat['department'];
                if (dept is Map) {
                  deptName = dept['name'] ?? 'Unknown Department';
                } else if (dept is String) {
                   final foundDept = departments.firstWhere((d) => d['id'] == dept || d['_id'] == dept, orElse: () => {});
                   if (foundDept.isNotEmpty) deptName = foundDept['name'];
                }
             }
           }
        }
      }

      // 3. Populate Map
      if (!hierarchyMap.containsKey(deptName)) {
        hierarchyMap[deptName] = {};
      }
      if (!hierarchyMap[deptName]!.containsKey(categoryName)) {
        hierarchyMap[deptName]![categoryName] = [];
      }
      hierarchyMap[deptName]![categoryName]!.add(item as Map<String, dynamic>);
    }

    // 4. Flatten to List
    final List<Map<String, dynamic>> finalItems = [];
    final sortedDepts = hierarchyMap.keys.toList()..sort();

    for (var dept in sortedDepts) {
      finalItems.add({'type': 'dept_header', 'name': dept});
      
      final catMap = hierarchyMap[dept]!;
      final sortedCats = catMap.keys.toList()..sort();
      
      for (var cat in sortedCats) {
        finalItems.add({'type': 'cat_header', 'name': cat});
        final products = catMap[cat]!;
        products.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        finalItems.addAll(products);
      }
    }
    return finalItems;
  }

  Future<void> _shareOrderPdf(Map<String, dynamic> order) async {
    final brown100 = PdfColor.fromInt(0xFFD7CCC8);
    final brown300 = PdfColor.fromInt(0xFFA1887F);
    final brown50 = PdfColor.fromInt(0xFFEFEBE9);
    final grey300 = PdfColor.fromInt(0xFFE0E0E0);
    final blue700 = PdfColor.fromInt(0xFF1976D2);
    
    final pdf = pw.Document();
    final invoiceNumber = order['invoiceNumber'] ?? 'No Invoice';
    final branchName = order['branch'] is Map ? order['branch']['name'] : (order['branch'] ?? 'Unknown Branch');
    final status = order['status'] ?? 'pending';
    final items = (order['items'] as List?) ?? [];
    final createdAt = DateTime.tryParse(order['createdAt'] ?? '');
    final deliveryDate = DateTime.tryParse(order['deliveryDate'] ?? '');
    final dateFmt = DateFormat('MMM d, h:mm a');
    final createdStr = createdAt != null ? dateFmt.format(createdAt.add(const Duration(hours: 5, minutes: 30))) : '';
    final deliveryStr = deliveryDate != null ? dateFmt.format(deliveryDate.add(const Duration(hours: 5, minutes: 30))) : '';

    final groupedItems = _groupItemsWithHeaders(items);

    // Calculate Totals
    int totalReq = 0, totalSent = 0, totalConf = 0, totalPick = 0, totalRecv = 0, totalDiff = 0;
    double totalReqAmt = 0, totalSntAmt = 0, totalRecAmt = 0;
    for (var item in items) {
      totalReq += (item['requiredQty'] ?? 0) as int;
      totalSent += (item['sendingQty'] ?? 0) as int;
      totalConf += (item['confirmedQty'] ?? 0) as int;
      totalPick += (item['pickedQty'] ?? 0) as int;
      totalRecv += (item['receivedQty'] ?? 0) as int;
      totalDiff += (item['differenceQty'] ?? 0) as int;
      totalReqAmt += (item['requiredAmount'] ?? 0).toDouble();
      totalSntAmt += (item['sendingAmount'] ?? 0).toDouble();
      totalRecAmt += (item['receivedAmount'] ?? 0).toDouble();
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return [
            // Header
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Invoice: $invoiceNumber', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: status.toLowerCase() == 'approved' ? PdfColors.green : PdfColors.orange,
                        borderRadius: pw.BorderRadius.circular(12),
                      ),
                      child: pw.Text(status.toUpperCase(), style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Text(branchName.toString(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Text('Delivery: $deliveryStr', style: pw.TextStyle(color: blue700, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text('Created: $createdStr', style: const pw.TextStyle(color: PdfColors.grey, fontSize: 10)),
                pw.SizedBox(height: 8),
                pw.Text('${items.length} Items     Req Amt: ${totalReqAmt.toInt()}     Snt Amt: ${totalSntAmt.toInt()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Divider(height: 10),
              ],
            ),
            

            
            // Items
            ...groupedItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;

              if (item['type'] == 'dept_header') {
                return pw.Container(
                  width: double.infinity,
                  color: brown300,
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  margin: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(
                    (item['name'] ?? '').toUpperCase(),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.white),
                    textAlign: pw.TextAlign.center,
                  ),
                );
              }
              if (item['type'] == 'cat_header') {
                return pw.Column(
                  children: [
                    pw.Container(
                      width: double.infinity,
                      color: grey300,
                      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: pw.Text(
                        (item['name'] ?? '').toUpperCase(),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.Container(
                      color: brown100,
                      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: pw.Row(
                        children: [
                          pw.Expanded(flex: 3, child: pw.Text('Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                          pw.Expanded(flex: 1, child: pw.Text('Prc', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                          pw.Expanded(flex: 1, child: pw.Text('Req', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                          pw.Expanded(flex: 1, child: pw.Text('Snt', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                          pw.Expanded(flex: 1, child: pw.Text('Con', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                          pw.Expanded(flex: 1, child: pw.Text('Pic', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                          pw.Expanded(flex: 1, child: pw.Text('Rec', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                          pw.Expanded(flex: 1, child: pw.Text('Dif', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                        ],
                      ),
                    ),
                  ],
                );
              }

              final name = item['name'] ?? 'Unknown';
              final req = item['requiredQty'] ?? 0;
              final reqAmount = (item['requiredAmount'] ?? 0).toDouble();
              final price = req > 0 ? (reqAmount / req).round() : 0;
              final sent = item['sendingQty'] ?? 0;
              final conf = item['confirmedQty'] ?? 0;
              final pick = item['pickedQty'] ?? 0;
              final recv = item['receivedQty'] ?? 0;
              final diff = item['differenceQty'] ?? 0;
              final bgColor = idx % 2 == 0 ? PdfColors.white : brown50;

              return pw.Container(
                color: bgColor,
                padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: pw.Row(
                  children: [
                    pw.Expanded(flex: 3, child: pw.Text(name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 1, child: pw.Text(price.toString(), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text(req.toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text(sent.toString(), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text(conf.toString(), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text(pick.toString(), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text(recv.toString(), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text(diff.toString(), style: pw.TextStyle(fontSize: 10, color: diff != 0 ? PdfColors.red : PdfColors.black, fontWeight: diff != 0 ? pw.FontWeight.bold : pw.FontWeight.normal), textAlign: pw.TextAlign.center)),
                  ],
                ),
              );
            }).toList(),

            // Totals
             pw.Container(
               color: brown300,
               padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
               margin: const pw.EdgeInsets.only(top: 8),
               child: pw.Row(
                 children: [
                   pw.Expanded(flex: 3, child: pw.Text('Total', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
                   pw.Expanded(flex: 1, child: pw.Text('', style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalReq.toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalSent.toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalConf.toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalPick.toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalRecv.toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalDiff.toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: totalDiff != 0 ? PdfColors.yellow : PdfColors.white), textAlign: pw.TextAlign.center)),
                 ],
               ),
             ),
             pw.Container(
                color: brown100,
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: pw.Row(
                  children: [
                    pw.Expanded(flex: 3, child: pw.Text('Amount', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black))),
                    pw.Expanded(flex: 1, child: pw.Text('', style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text(totalReqAmt.toInt().toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text(totalSntAmt.toInt().toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text('', style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text('', style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text(totalRecAmt.toInt().toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 1, child: pw.Text('', style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                  ],
                ),
              ),

          ];
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final safeInvoice = invoiceNumber.toString().replaceAll(RegExp(r'[^\w\-]'), '_');
    final file = File('${output.path}/stockorder_$safeInvoice.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'Stock Order - $branchName');
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: fromDate != null && toDate != null
          ? DateTimeRange(start: fromDate!, end: toDate!)
          : DateTimeRange(start: now, end: now),
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            child: child,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        fromDate = picked.start;
        toDate = picked.end;
      });
      await _fetchStockOrders();
    }
  }

  Widget _buildDateSelector() {
    final safeFrom = fromDate ?? DateTime.now();
    final dateFmt = DateFormat('MMM d');
    final label = toDate == null || (fromDate!.year == toDate!.year && fromDate!.month == toDate!.month && fromDate!.day == toDate!.day)
        ? dateFmt.format(safeFrom)
        : '${dateFmt.format(safeFrom)} - ${dateFmt.format(toDate!)}';
    return InkWell(
      onTap: _pickDateRange,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_today, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildBranchFilter() {
    return _loadingBranches
        ? const SizedBox(height: 40, width: 40, child: Center(child: CircularProgressIndicator()))
        : SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
            value: selectedBranchId,
            items: branches.map((b) {
              return DropdownMenuItem<String>(
                value: b['id'],
                child: Text(b['name']!, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) async {
              if (v == null) return;
              setState(() => selectedBranchId = v);
              await _fetchStockOrders();
            },
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              isDense: true,
              labelText: 'Branch',
            ),
          ),
        );
  }

  Widget _buildWebTable() {
    final Map<String, Map<String, double>> aggregates = {};

    for (var order in stockOrders) {
      String bName = 'Unknown';
      if (order['branch'] is Map && order['branch']['name'] != null) {
        bName = order['branch']['name'].toString();
      } else if (order['branch'] is String) {
        bName = order['branch'];
      }

      if (!aggregates.containsKey(bName)) {
        aggregates[bName] = {
          'Req': 0.0, 'Snt': 0.0, 'Con': 0.0, 'Pic': 0.0, 'Rec': 0.0, 'Dif': 0.0,
        };
      }

      final items = (order['items'] as List?) ?? [];
      for (var item in items) {
        final cur = aggregates[bName]!;

        final reqQty = (item['requiredQty'] ?? 0) as int;
        final reqAmt = (item['requiredAmount'] ?? 0).toDouble();
        final unitPrice = reqQty > 0 ? reqAmt / reqQty : 0.0;

        final sentQty = (item['sendingQty'] ?? 0) as int;
        final confQty = (item['confirmedQty'] ?? 0) as int;
        final pickQty = (item['pickedQty'] ?? 0) as int;
        final differenceQty = (item['differenceQty'] ?? 0) as int;

        // Amounts calculation
        // SntAmt & RecAmt might be available directly, but for consistency let's use logic or available fields
        // Assuming sendingAmount and receivedAmount are available.
        final sentAmt = (item['sendingAmount'] ?? 0).toDouble();
        final recvAmt = (item['receivedAmount'] ?? 0).toDouble();

        // For Confirmed, Picked, Difference, we calculate estimate
        final confAmt = confQty * unitPrice;
        final pickAmt = pickQty * unitPrice;
        final diffAmt = differenceQty * unitPrice;

        cur['Req'] = (cur['Req']!) + reqAmt;
        cur['Snt'] = (cur['Snt']!) + sentAmt;
        cur['Con'] = (cur['Con']!) + confAmt;
        cur['Pic'] = (cur['Pic']!) + pickAmt;
        cur['Rec'] = (cur['Rec']!) + recvAmt;
        cur['Dif'] = (cur['Dif']!) + diffAmt;
      }
    }

    final sortedBranches = aggregates.keys.toList()..sort();

    double totalReq = 0;
    double totalSnt = 0;
    double totalCon = 0;
    double totalPic = 0;
    double totalRec = 0;
    double totalDif = 0;

    List<DataRow> rows = [];
    int index = 0;
    for (var bName in sortedBranches) {
      final data = aggregates[bName]!;
      totalReq += data['Req']!;
      totalSnt += data['Snt']!;
      totalCon += data['Con']!;
      totalPic += data['Pic']!;
      totalRec += data['Rec']!;
      totalDif += data['Dif']!;
      
      final bgColor = index % 2 == 0 ? Colors.green.withOpacity(0.1) : Colors.white;

      rows.add(DataRow(
        color: MaterialStateProperty.all(bgColor),
        cells: [
        DataCell(Text(bName, style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(data['Req']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(data['Snt']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(data['Con']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(data['Pic']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(data['Rec']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(data['Dif']!.round().toString(), style: TextStyle(color: data['Dif']! != 0 ? Colors.red : Colors.black, fontWeight: FontWeight.bold))),
      ]));
      index++;
    }

    // Total Row
    rows.add(DataRow(
      color: MaterialStateProperty.all(Colors.grey.shade300),
      cells: [
        const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(totalReq.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(totalSnt.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(totalCon.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(totalPic.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(totalRec.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(totalDif.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
      ],
    ));

    final vScroll = ScrollController();
    final hScroll = ScrollController();
    
    return Align(
      alignment: Alignment.topLeft,
      child: Scrollbar(
        controller: vScroll,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: vScroll,
          scrollDirection: Axis.vertical,
          child: Scrollbar(
            controller: hScroll,
            thumbVisibility: true,
            trackVisibility: true,
            notificationPredicate: (notif) => notif.depth == 1,
            child: SingleChildScrollView(
              controller: hScroll,
              scrollDirection: Axis.horizontal,
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Branch Table
                    Card(
                      elevation: 4,
                      margin: const EdgeInsets.all(12),
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(Colors.brown.shade300),
                        headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        columns: const [
                          DataColumn(label: Text('Branch')),
                          DataColumn(label: Text('Req Amt'), tooltip: 'Requested Amount'),
                          DataColumn(label: Text('Snt Amt'), tooltip: 'Sent Amount'),
                          DataColumn(label: Text('Con Amt'), tooltip: 'Confirmed Amount'),
                          DataColumn(label: Text('Pic Amt'), tooltip: 'Picked Amount'),
                          DataColumn(label: Text('Rec Amt'), tooltip: 'Received Amount'),
                          DataColumn(label: Text('Dif Amt'), tooltip: 'Difference Amount'),
                        ],
                        rows: rows,
                      ),
                    ),

                    const SizedBox(height: 20),
                    
                    // Product Table
                    _buildProductSummaryTable(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductSummaryTable() {
    // Map<DepartmentName, Map<CategoryName, Map<ProductName, Stats>>>
    final Map<String, Map<String, Map<String, Map<String, int>>>> groupedAggregates = {};

    for (var order in stockOrders) {
      final items = (order['items'] as List?) ?? [];
      for (var item in items) {
        final name = item['name'] ?? 'Unknown Product';
        
        // Extract Category & Department
        String departmentName = 'Unknown Department';
        String categoryName = 'Unknown Category';
        
        Map<String, dynamic>? categoryData;
        if (item['product'] is Map && item['product']['category'] != null) {
          categoryData = item['product']['category'];
        } else if (item['category'] != null) {
          categoryData = item['category'];
        }
        
        if (categoryData != null) {
          categoryName = categoryData['name'] ?? 'Unknown Category';
          if (categoryData['department'] != null) {
             final dept = categoryData['department'];
             departmentName = dept['name'] ?? 'Unknown Department';
          }
        }
        
        if (!groupedAggregates.containsKey(departmentName)) {
          groupedAggregates[departmentName] = {};
        }
        
        if (!groupedAggregates[departmentName]!.containsKey(categoryName)) {
          groupedAggregates[departmentName]![categoryName] = {};
        }
        
        if (!groupedAggregates[departmentName]![categoryName]!.containsKey(name)) {
          groupedAggregates[departmentName]![categoryName]![name] = {
            'Req': 0, 'Snt': 0, 'Con': 0, 'Pic': 0, 'Dif': 0,
          };
        }

        final cur = groupedAggregates[departmentName]![categoryName]![name]!;
        cur['Req'] = (cur['Req']!) + ((item['requiredQty'] ?? 0) as int);
        cur['Snt'] = (cur['Snt']!) + ((item['sendingQty'] ?? 0) as int);
        cur['Con'] = (cur['Con']!) + ((item['confirmedQty'] ?? 0) as int);
        cur['Pic'] = (cur['Pic']!) + ((item['pickedQty'] ?? 0) as int);
        cur['Dif'] = (cur['Dif']!) + ((item['differenceQty'] ?? 0) as int);
      }
    }

    final sortedDepartments = groupedAggregates.keys.toList()..sort();
    
    List<DataRow> rows = [];
    int pIndex = 0;
    
    for (var deptName in sortedDepartments) {
      // Add Department Header Row
      rows.add(DataRow(
        color: MaterialStateProperty.all(Colors.brown.shade400),
        cells: [
          DataCell(Text(deptName.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
          const DataCell(Text('')),
          const DataCell(Text('')),
          const DataCell(Text('')),
          const DataCell(Text('')),
          const DataCell(Text('')),
        ],
      ));

      final categoriesMap = groupedAggregates[deptName]!;
      final sortedCategories = categoriesMap.keys.toList()..sort();

      for (var catName in sortedCategories) {
        // Add Category Header Row
        rows.add(DataRow(
          color: MaterialStateProperty.all(Colors.blueGrey.shade100),
          cells: [
            DataCell(Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Text(catName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            )),
            const DataCell(Text('')),
            const DataCell(Text('')),
            const DataCell(Text('')),
            const DataCell(Text('')),
            const DataCell(Text('')),
          ],
        ));

        final productsMap = categoriesMap[catName]!;
        final sortedProducts = productsMap.keys.toList()..sort();

        for (var pName in sortedProducts) {
          final data = productsMap[pName]!;
          final bgColor = pIndex % 2 == 0 ? Colors.blue.withOpacity(0.05) : Colors.white;

          rows.add(DataRow(
            color: MaterialStateProperty.all(bgColor),
            cells: [
              DataCell(Padding(
                padding: const EdgeInsets.only(left: 24.0), // Indent products further
                child: Text(pName, style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
              DataCell(Text(data['Req'].toString())),
              DataCell(Text(data['Snt'].toString())),
              DataCell(Text(data['Con'].toString())),
              DataCell(Text(data['Pic'].toString())),
              DataCell(Text(data['Dif'].toString(), style: TextStyle(color: data['Dif']! != 0 ? Colors.red : Colors.black, fontWeight: FontWeight.bold))),
            ],
          ));
          pIndex++;
        }
      }
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      child: DataTable(
        headingRowColor: MaterialStateProperty.all(Colors.blueGrey.shade700),
        headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        columns: const [
          DataColumn(label: Text('Product Name')),
          DataColumn(label: Text('Req (Qty)')),
          DataColumn(label: Text('Snt (Qty)')),
          DataColumn(label: Text('Con (Qty)')),
          DataColumn(label: Text('Pic (Qty)')),
          DataColumn(label: Text('Dif (Qty)')),
        ],
        rows: rows,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'fulfilled':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStockOrderCard(Map<String, dynamic> order) {
    final invoiceNumber = order['invoiceNumber'] ?? 'No Invoice';
    final branchName = order['branch'] is Map ? order['branch']['name'] : 'Unknown Branch';
    final status = order['status'] ?? 'pending';
    final items = (order['items'] as List?) ?? [];
    final itemCount = items.length;
    final createdAt = DateTime.tryParse(order['createdAt'] ?? '');
    final deliveryDate = DateTime.tryParse(order['deliveryDate'] ?? '');
    final dateFmt = DateFormat('MMM d, h:mm a');
    final createdStr = createdAt != null ? dateFmt.format(createdAt.add(const Duration(hours: 5, minutes: 30))) : '';
    final deliveryStr = deliveryDate != null ? dateFmt.format(deliveryDate.add(const Duration(hours: 5, minutes: 30))) : '';

    return GestureDetector(
      onLongPress: () => _shareOrderPdf(order),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Invoice Number + Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoiceNumber,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
                Transform.translate(
                  offset: const Offset(42, 0),
                  child: _buildStatusChip(status),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // Row 2: Branch Name
            Text(
              branchName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 3),
            // Row 3: Delivery Date (big)
            Text(
              'Delivery: $deliveryStr',
              style: TextStyle(color: Colors.blue[700], fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 1),
            // Row 4: Created Date
            Text(
              'Created: $createdStr',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
        subtitle: Builder(
          builder: (context) {
            double totalReqAmt = 0, totalSntAmt = 0;
            for (var item in items) {
              totalReqAmt += (item['requiredAmount'] ?? 0).toDouble();
              totalSntAmt += (item['sendingAmount'] ?? 0).toDouble();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                '$itemCount Items     Req Amt: ${totalReqAmt.toInt()}     Snt Amt: ${totalSntAmt.toInt()}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            );
          },
        ),
        children: [
          const Divider(height: 1),
          // Header Row

          // Data Rows with zebra stripes
          // Data Rows with zebra stripes
          ..._groupItemsWithHeaders(items).asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;

            // Check if it's a header
            if (item['type'] == 'dept_header') {
              return Container(
                width: double.infinity,
                color: Colors.brown[300],
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                margin: const EdgeInsets.only(top: 8),
                child: Text(
                  (item['name'] ?? '').toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (item['type'] == 'cat_header') {
              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    child: Text(
                      (item['name'] ?? '').toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Container(
                    color: Colors.brown.shade100,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    child: Row(
                      children: const [
                        Expanded(flex: 3, child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        Expanded(flex: 1, child: Text('Prc', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text('Req', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text('Snt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text('Con', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text('Pic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text('Rec', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text('Dif', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                      ],
                    ),
                  ),
                ],
              );
            }

            final name = item['name'] ?? 'Unknown';
            final req = item['requiredQty'] ?? 0;
            final reqAmount = (item['requiredAmount'] ?? 0).toDouble();
            final price = req > 0 ? (reqAmount / req).round() : 0;
            final sent = item['sendingQty'] ?? 0;
            final conf = item['confirmedQty'] ?? 0;
            final pick = item['pickedQty'] ?? 0;
            final recv = item['receivedQty'] ?? 0;
            final diff = item['differenceQty'] ?? 0;
            final bgColor = idx % 2 == 0 ? Colors.white : Colors.brown.shade50;

            return Container(
              color: bgColor,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 1, child: Text(price.toString(), style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(req.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(sent.toString(), style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(conf.toString(), style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(pick.toString(), style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(recv.toString(), style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(diff.toString(), style: TextStyle(fontSize: 11, color: diff != 0 ? Colors.red : Colors.black, fontWeight: diff != 0 ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center)),
                ],
              ),
            );
          }).toList(),
          // Total Row
          Builder(builder: (context) {
            int totalReq = 0, totalSent = 0, totalConf = 0, totalPick = 0, totalRecv = 0, totalDiff = 0;
            double totalReqAmt = 0, totalSntAmt = 0, totalRecAmt = 0;
            for (var item in items) {
              totalReq += (item['requiredQty'] ?? 0) as int;
              totalSent += (item['sendingQty'] ?? 0) as int;
              totalConf += (item['confirmedQty'] ?? 0) as int;
              totalPick += (item['pickedQty'] ?? 0) as int;
              totalRecv += (item['receivedQty'] ?? 0) as int;
              totalDiff += (item['differenceQty'] ?? 0) as int;
              totalReqAmt += (item['requiredAmount'] ?? 0).toDouble();
              totalSntAmt += (item['sendingAmount'] ?? 0).toDouble();
              totalRecAmt += (item['receivedAmount'] ?? 0).toDouble();
            }
            return Column(
              children: [
                // Total Qty Row
                Container(
                  color: Colors.brown.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: Row(
                    children: [
                      const Expanded(flex: 3, child: Text('Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))),
                      const Expanded(flex: 1, child: Text('', style: TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalReq.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalSent.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalConf.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalPick.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalRecv.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalDiff.toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: totalDiff != 0 ? Colors.yellow : Colors.white), textAlign: TextAlign.center)),
                    ],
                  ),
                ),
                // Total Amount Row
                Container(
                  color: Colors.brown.shade100,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: Row(
                    children: [
                      const Expanded(flex: 3, child: Text('Amount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black))),
                      const Expanded(flex: 1, child: Text('', style: TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalReqAmt.toInt().toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalSntAmt.toInt().toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black), textAlign: TextAlign.center)),
                      const Expanded(flex: 1, child: Text('', style: TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                      const Expanded(flex: 1, child: Text('', style: TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalRecAmt.toInt().toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black), textAlign: TextAlign.center)),
                      const Expanded(flex: 1, child: Text('', style: TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                    ],
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;

    Widget mainContent = Column(
      children: [
        // Filters
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                 _buildDateSelector(),
                 _buildBranchFilter(),
                 // Could add more filters or stats here
              ],
            ),
          ),
        ),
        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : stockOrders.isEmpty
                  ? const Center(child: Text('No stock orders found'))
                  : kIsWeb
                      ? _buildWebTable()
                      : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: stockOrders.length + (_combinedOrder != null ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_combinedOrder != null) {
                          if (index == 0) {
                            return _buildStockOrderCard(_combinedOrder!);
                          }
                          return _buildStockOrderCard(stockOrders[index - 1]);
                        }
                        return _buildStockOrderCard(stockOrders[index]);
                      },
                    ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Orders'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                selectedBranchId = 'ALL';
                fromDate = DateTime.now();
                toDate = DateTime.now();
              });
              _fetchStockOrders();
            },
          ),
        ],
      ),
      drawer: isDesktop
          ? null
          : const Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(child: AppDrawer()),
      ),
      body: isDesktop
          ? Row(
        children: [
          // Fixed Sidebar
          Container(
            width: 250,
            color: Colors.white,
            child: const AppDrawer(),
          ),
          // Main Content
          Expanded(child: mainContent),
        ],
      )
          : mainContent,
    );
  }
}
