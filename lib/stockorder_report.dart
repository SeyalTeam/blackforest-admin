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
  final ScrollController _webVScroll = ScrollController();

  final ScrollController _webHScroll = ScrollController();

  String selectedDepartmentId = 'ALL';
  String selectedCategoryId = 'ALL';
  String selectedProductId = 'ALL';
  String selectedStatus = 'ALL';

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
            'requiredQty': 0.0,
            'requiredAmount': 0.0,
            'sendingQty': 0.0,
            'sendingAmount': 0.0,
            'confirmedQty': 0.0,
            'pickedQty': 0.0,
            'receivedQty': 0.0,
            'receivedAmount': 0.0,
            'differenceQty': 0.0,
          };
        }

        final cur = itemMap[name]!;
        cur['requiredQty'] = parseQty(cur['requiredQty']) + parseQty(item['requiredQty']);
        cur['requiredAmount'] = parseQty(cur['requiredAmount']) + parseQty(item['requiredAmount']);
        cur['sendingQty'] = parseQty(cur['sendingQty']) + parseQty(item['sendingQty']);
        cur['sendingAmount'] = parseQty(cur['sendingAmount']) + parseQty(item['sendingAmount']);
        cur['confirmedQty'] = parseQty(cur['confirmedQty']) + parseQty(item['confirmedQty']);
        cur['pickedQty'] = parseQty(cur['pickedQty']) + parseQty(item['pickedQty']);
        cur['receivedQty'] = parseQty(cur['receivedQty']) + parseQty(item['receivedQty']);
        cur['receivedAmount'] = parseQty(cur['receivedAmount']) + parseQty(item['receivedAmount']);
        cur['differenceQty'] = parseQty(cur['differenceQty']) + parseQty(item['differenceQty']);
        
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
    double totalReq = 0, totalSent = 0, totalConf = 0, totalPick = 0, totalRecv = 0, totalDiff = 0;
    double totalReqAmt = 0, totalSntAmt = 0, totalRecAmt = 0;
    for (var item in items) {
      totalReq += parseQty(item['requiredQty']);
      totalSent += parseQty(item['sendingQty']);
      totalConf += parseQty(item['confirmedQty']);
      totalPick += parseQty(item['pickedQty']);
      totalRecv += parseQty(item['receivedQty']);
      totalDiff += parseQty(item['differenceQty']);
      totalReqAmt += parseQty(item['requiredAmount']);
      totalSntAmt += parseQty(item['sendingAmount']);
      totalRecAmt += parseQty(item['receivedAmount']);
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
              final req = parseQty(item['requiredQty']);
              final reqAmount = parseQty(item['requiredAmount']);
              final price = req > 0 ? (reqAmount / req).round() : 0;
              final sent = parseQty(item['sendingQty']);
              final conf = parseQty(item['confirmedQty']);
              final pick = parseQty(item['pickedQty']);
              final recv = parseQty(item['receivedQty']);
              final diff = parseQty(item['differenceQty']);
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
                   pw.Expanded(flex: 1, child: pw.Text(totalReq.round().toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalSent.round().toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalConf.round().toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalPick.round().toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalRecv.round().toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                   pw.Expanded(flex: 1, child: pw.Text(totalDiff.round().toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: totalDiff != 0 ? PdfColors.yellow : PdfColors.white), textAlign: pw.TextAlign.center)),
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
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: 'Branch',
          prefixIcon: const Icon(Icons.store),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        value: selectedBranchId,
        items: [
          const DropdownMenuItem(value: 'ALL', child: Text('All Branches')),
          ...branches.map((b) => DropdownMenuItem(
                value: b['id']!,
                child: Text(b['name']!, overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: (val) {
          if (val != null) {
            setState(() {
              selectedBranchId = val;
              selectedDepartmentId = 'ALL';
              selectedCategoryId = 'ALL';
              selectedProductId = 'ALL';
              selectedStatus = 'ALL';
            });
            _fetchStockOrders();
          }
        },
      ),
    );
  }

  Widget _buildDepartmentFilter() {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: 'Department',
          prefixIcon: const Icon(Icons.business),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        value: selectedDepartmentId,
        items: [
          const DropdownMenuItem(value: 'ALL', child: Text('All Departments')),
          ...departments.map((d) => DropdownMenuItem(
                value: (d['id'] ?? d['_id'])?.toString() ?? '',
                child: Text(d['name']?.toString() ?? 'Unknown', overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: (val) {
          if (val != null) {
            setState(() {
              selectedDepartmentId = val;
              selectedCategoryId = 'ALL';
              selectedProductId = 'ALL';
            });
          }
        },
      ),
    );
  }

  Widget _buildCategoryFilter() {
    List<Map<String, dynamic>> filteredCategories = categories;
    if (selectedDepartmentId != 'ALL') {
      filteredCategories = categories.where((c) {
        final dept = c['department'];
        final deptId = dept is Map ? (dept['id'] ?? dept['_id']) : dept;
        return deptId?.toString() == selectedDepartmentId;
      }).toList();
    }

    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: 'Category',
          prefixIcon: const Icon(Icons.category),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        value: selectedCategoryId,
        items: [
          const DropdownMenuItem(value: 'ALL', child: Text('All Categories')),
          ...filteredCategories.map((c) => DropdownMenuItem(
                value: (c['id'] ?? c['_id'])?.toString() ?? '',
                child: Text(c['name']?.toString() ?? 'Unknown', overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: (val) {
          if (val != null) {
            setState(() {
              selectedCategoryId = val;
              selectedProductId = 'ALL';
            });
          }
        },
      ),
    );
  }

  Widget _buildProductFilter() {
    // Collect unique products from stockOrders (filtered by Dept/Cat)
    final Set<String> productNames = {};
    for (var order in stockOrders) {
      final items = (order['items'] as List?) ?? [];
      for (var item in items) {
        final name = item['name']?.toString();
        if (name == null) continue;

        // Check Dept/Cat filtering logic to see if this product SHOULD be in the list
        // This duplicates the filtering logic slightly but is needed for correct UI options
        bool include = true;

        if (selectedDepartmentId != 'ALL') {
          String? deptId;
          // Try to extract Dept ID logic
            String itemDeptId = 'UNKNOWN';
            Map<String, dynamic>? catData;
            dynamic catSource = (item['product'] is Map) ? item['product']['category'] : null;
            if (catSource == null) catSource = item['category'];

            if (catSource is Map) {
              catData = catSource.cast<String, dynamic>();
            } else if (catSource is String) {
               // Optimization: In this UI builder loop, we might skip heavy lookups if lists are huge
               // but for reasonably sized lists, it's fine.
               final found = categories.firstWhere((c) => c['id'] == catSource || c['_id'] == catSource, orElse: () => {});
               if (found.isNotEmpty) catData = found;
            }

            if (catData != null) {
              final dept = catData['department'];
              itemDeptId = (dept is Map ? (dept['id'] ?? dept['_id']) : dept)?.toString() ?? 'UNKNOWN';
            }
            if (itemDeptId != selectedDepartmentId) include = false;
        }

        if (include && selectedCategoryId != 'ALL') {
             String itemCatId = 'UNKNOWN';
             Map<String, dynamic>? catData;
             dynamic catSource = (item['product'] is Map) ? item['product']['category'] : null;
             if (catSource == null) catSource = item['category'];

             if (catSource is Map) {
                catData = catSource.cast<String, dynamic>();
             } else if (catSource is String) {
                itemCatId = catSource;
             }
             if (catData != null) {
               itemCatId = (catData['id'] ?? catData['_id'])?.toString() ?? 'UNKNOWN';
             }
             if (itemCatId != selectedCategoryId) include = false;
        }

        if (include) {
          productNames.add(name);
        }
      }
    }

    final sortedProducts = productNames.toList()..sort();

    return SizedBox(
      width: 250,
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: 'Product',
          prefixIcon: const Icon(Icons.inventory),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        value: selectedProductId,
        items: [
          const DropdownMenuItem(value: 'ALL', child: Text('All Products')),
          ...sortedProducts.map((p) => DropdownMenuItem(
                value: p,
                child: Text(p, overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: (val) {
          if (val != null) {
            setState(() => selectedProductId = val);
          }
        },
      ),
    );
  }

  Widget _buildStatusFilter() {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: 'Status',
          prefixIcon: const Icon(Icons.info_outline),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        value: selectedStatus,
        items: const [
          DropdownMenuItem(value: 'ALL', child: Text('All Status')),
          DropdownMenuItem(value: 'Ordered', child: Text('Ordered')),
          DropdownMenuItem(value: 'Sending', child: Text('Sending')),
          DropdownMenuItem(value: 'Confirmed', child: Text('Confirmed')),
          DropdownMenuItem(value: 'Picked', child: Text('Picked')),
          DropdownMenuItem(value: 'Received', child: Text('Received')),
        ],
        onChanged: (val) {
          if (val != null) {
            setState(() => selectedStatus = val);
          }
        },
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
          'Ord': 0.0, 'Snt': 0.0, 'Con': 0.0, 'Pic': 0.0, 'Rec': 0.0, 'Dif': 0.0,
        };
      }

        final items = (order['items'] as List?) ?? [];
        for (var item in items) {
          // --- Product Filtering Logic ---
          final name = item['name']?.toString() ?? 'Unknown Product';
          if (selectedProductId != 'ALL' && name != selectedProductId) continue;
          // ------------------------------

          // --- Status Filtering Logic ---
          if (selectedStatus != 'ALL') {
             double rQty = parseQty(item['requiredQty']);
             double sQty = parseQty(item['sendingQty']);
             double cQty = parseQty(item['confirmedQty']);
             double pQty = parseQty(item['pickedQty']);
             double recQty = parseQty(item['receivedQty']);
             // Fallback for received if 'receivedQty' missing, use receivedAmount logic from before? 
             // Actually aggregation uses receivedAmount, but for unit tracking we should ideally use Qty.
             // If receivedQty is not reliable, we might need another check, but let's stick to receivedQty or 0.
             // Wait, previous code used receivedAmount > 0. Let's check item keys availability.
             // The Aggregation uses: cur['Rec'] = (cur['Rec']!) + parseQty(item['receivedQty']); 
             // So receivedQty exists.

             bool match = false;
             if (selectedStatus == 'Ordered') {
               // Pending to Send: Ordered > Sent
               if (rQty > sQty) match = true;
             }
             else if (selectedStatus == 'Sending') {
               // Pending to Confirm: Sent > Confirmed
               if (sQty > cQty) match = true;
             }
             else if (selectedStatus == 'Confirmed') {
                // Pending to Pick: Confirmed > Picked
                if (cQty > pQty) match = true;
             }
             else if (selectedStatus == 'Picked') {
                // Pending to Receive: Picked > Received
                if (pQty > recQty) match = true;
             }
             else if (selectedStatus == 'Received') {
                // Already Received
                if (recQty > 0) match = true;
             }
             
             if (!match) continue;
          }
          // ------------------------------

          // --- Department Filtering Logic ---
          if (selectedDepartmentId != 'ALL') {
            String itemDeptId = 'UNKNOWN';
            Map<String, dynamic>? catData;
            
            dynamic catSource = (item['product'] is Map) ? item['product']['category'] : null;
            if (catSource == null) catSource = item['category'];

            if (catSource is Map) {
              catData = catSource.cast<String, dynamic>();
            } else if (catSource is String) {
               final found = categories.firstWhere((c) => c['id'] == catSource || c['_id'] == catSource, orElse: () => {});
               if (found.isNotEmpty) catData = found;
            }

            if (catData != null) {
              final dept = catData['department'];
              itemDeptId = (dept is Map ? (dept['id'] ?? dept['_id']) : dept)?.toString() ?? 'UNKNOWN';
            }
            
            if (itemDeptId != selectedDepartmentId) continue;
          }
           // --- Category Filtering Logic ---
          if (selectedCategoryId != 'ALL') {
             String itemCatId = 'UNKNOWN';
             Map<String, dynamic>? catData;
             dynamic catSource = (item['product'] is Map) ? item['product']['category'] : null;
             if (catSource == null) catSource = item['category'];

             if (catSource is Map) {
                catData = catSource.cast<String, dynamic>();
             } else if (catSource is String) {
                // If we already looked up for dept logic, reuse? 
                // We'll just maintain safety and re-check or reuse if we had a var scope (not easily available here without refactor)
                // Just use simple check
                itemCatId = catSource;
             }
             
             if (catData != null) {
               itemCatId = (catData['id'] ?? catData['_id'])?.toString() ?? 'UNKNOWN';
             }
             
             if (itemCatId != selectedCategoryId) continue;
          }
          // ----------------------------------

          final cur = aggregates[bName]!;

          final reqQty = parseQty(item['requiredQty']);
          final reqAmt = parseQty(item['requiredAmount']);
          final unitPrice = reqQty > 0 ? reqAmt / reqQty : 0.0;

          final sentQty = parseQty(item['sendingQty']);
          final confQty = parseQty(item['confirmedQty']);
          final pickQty = parseQty(item['pickedQty']);
          final differenceQty = parseQty(item['differenceQty']);

          final sentAmt = parseQty(item['sendingAmount']);
          final recvAmt = parseQty(item['receivedAmount']);

          final confAmt = confQty * unitPrice;
          final pickAmt = pickQty * unitPrice;
          final diffAmt = differenceQty * unitPrice;

        cur['Ord'] = (cur['Ord']!) + reqAmt;
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
      totalReq += data['Ord']!;
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
        DataCell(Text(data['Ord']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
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

    return Align(
      alignment: Alignment.topLeft,
      child: Scrollbar(
        controller: _webVScroll,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: _webVScroll,
          scrollDirection: Axis.vertical,
          child: Scrollbar(
            controller: _webHScroll,
            thumbVisibility: true,
            trackVisibility: true,
            notificationPredicate: (notif) => notif.depth == 1,
            child: SingleChildScrollView(
              controller: _webHScroll,
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          DataColumn(label: Text('Ord Amt'), tooltip: 'Ordered Amount'),
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
    );
  }

  String _formatTime(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate).add(const Duration(hours: 5, minutes: 30)); // UTC to IST
      // 24-hour format HH:mm
      return DateFormat('HH:mm').format(dt);
    } catch (e) {
      return '';
    }
  }

  Widget _buildProductSummaryTable() {
    // Map<DepartmentName, Map<CategoryName, Map<ProductName, Stats>>>
    final Map<String, Map<String, Map<String, Map<String, dynamic>>>> groupedAggregates = {};

    for (var order in stockOrders) {
      final items = (order['items'] as List?) ?? [];
      for (var item in items) {
        if (item is! Map) continue;
        
        final name = item['name']?.toString() ?? 'Unknown Product';
        
        // Extract Category & Department safely
        String departmentName = 'Unknown Department';
        String categoryName = 'Unknown Category';
        
        Map<String, dynamic>? categoryData;
        
        // Check product.category
        final prod = item['product'];
        if (prod is Map) {
          final cat = prod['category'];
          if (cat is Map) {
            categoryData = cat.cast<String, dynamic>();
          } else if (cat is String) {
            // Lookup category by ID
            final foundCat = categories.firstWhere(
              (c) => c['id'] == cat,
              orElse: () => {},
            );
            if (foundCat.isNotEmpty) {
              categoryData = foundCat;
            }
          }
        }
        
        // Fallback to item.category
        if (categoryData == null) {
          final cat = item['category'];
          if (cat is Map) {
            categoryData = cat.cast<String, dynamic>();
          } else if (cat is String) {
            // Lookup category by ID
            final foundCat = categories.firstWhere(
              (c) => c['id'] == cat,
              orElse: () => {},
            );
            if (foundCat.isNotEmpty) {
              categoryData = foundCat;
            }
          }
        }
        
        if (categoryData != null) {
          categoryName = categoryData['name']?.toString() ?? 'Unknown Category';
          final dept = categoryData['department'];
          if (dept is Map) {
            departmentName = dept['name']?.toString() ?? 'Unknown Department';
          } else if (dept is String) {
            // Lookup department name by ID
            final foundDept = departments.firstWhere(
              (d) => d['id'] == dept,
              orElse: () => {},
            );
            departmentName = foundDept['name']?.toString() ?? dept;
          }
        }
        
        // --- Department Filtering Logic ---
        if (selectedDepartmentId != 'ALL') {
          String? currentDeptId;
          if (categoryData != null) {
            final dept = categoryData['department'];
            currentDeptId = (dept is Map ? (dept['id'] ?? dept['_id']) : dept)?.toString();
          }
          if (currentDeptId != selectedDepartmentId) continue;
        }
        
        // --- Category Filtering Logic ---
        if (selectedCategoryId != 'ALL') {
          String? currentCatId = (categoryData?['id'] ?? categoryData?['_id'])?.toString();
          if (currentCatId != selectedCategoryId) continue;
        }
        
        // --- Product Filtering Logic ---
        if (selectedProductId != 'ALL' && name != selectedProductId) continue;
        
        // --- Status Filtering Logic ---
        if (selectedStatus != 'ALL') {
             double rQty = parseQty(item['requiredQty']);
             double sQty = parseQty(item['sendingQty']);
             double cQty = parseQty(item['confirmedQty']);
             double pQty = parseQty(item['pickedQty']);
             double recQty = parseQty(item['receivedQty']);

             bool match = false;
             if (selectedStatus == 'Ordered') {
               if (rQty > sQty) match = true;
             }
             else if (selectedStatus == 'Sending') {
               if (sQty > cQty) match = true;
             }
             else if (selectedStatus == 'Confirmed') {
                if (cQty > pQty) match = true;
             }
             else if (selectedStatus == 'Picked') {
                if (pQty > recQty) match = true;
             }
             else if (selectedStatus == 'Received') {
                if (recQty > 0) match = true;
             }
             
             if (!match) continue;
        }
        // ------------------------------
        
        if (!groupedAggregates.containsKey(departmentName)) {
          groupedAggregates[departmentName] = {};
        }
        
        if (!groupedAggregates[departmentName]!.containsKey(categoryName)) {
          groupedAggregates[departmentName]![categoryName] = {};
        }
        
        if (!groupedAggregates[departmentName]![categoryName]!.containsKey(name)) {
          groupedAggregates[departmentName]![categoryName]![name] = {
            'Ord': 0.0, 'Snt': 0.0, 'Con': 0.0, 'Pic': 0.0, 'Rec': 0.0, 'Dif': 0.0,
            'OrdTime': '', 'SntTime': '', 'ConTime': '', 'PicTime': '', 'RecTime': '',
          };
        }

        final cur = groupedAggregates[departmentName]![categoryName]![name]!;
        
        // Safe numeric parsing
        // Safe numeric parsing
        cur['Ord'] = (cur['Ord']!) + parseQty(item['requiredQty']);
        cur['Snt'] = (cur['Snt']!) + parseQty(item['sendingQty']);
        cur['Con'] = (cur['Con']!) + parseQty(item['confirmedQty']);
        cur['Pic'] = (cur['Pic']!) + parseQty(item['pickedQty']);
        cur['Rec'] = (cur['Rec']!) + parseQty(item['receivedQty']);
        cur['Dif'] = (cur['Dif']!) + parseQty(item['differenceQty']);

        // Timestamp extraction
        if (order['createdAt'] != null) cur['OrdTime'] = order['createdAt'];
        
        String? sTime = item['sendingAt']?.toString() ?? order['sendingAt']?.toString() ?? order['sentAt']?.toString();

        if (sTime == null || sTime.isEmpty) {
          dynamic sentBy = item['sendingUpdatedBy'] ?? order['sendingUpdatedBy'];
          if (sentBy is Map) {
            // Check common timestamp keys
            sTime = sentBy['date']?.toString() ?? sentBy['createdAt']?.toString() ?? sentBy['time']?.toString();
          } else if (sentBy is String) {
            // If it's a string, it might be the date itself
            sTime = sentBy;
          }
        }

        if (sTime != null && sTime.isNotEmpty) cur['SntTime'] = sTime;

        String? cTime = item['confirmedAt']?.toString() ?? order['confirmedAt']?.toString();
        if (cTime != null && cTime.isNotEmpty) cur['ConTime'] = cTime;

        String? pTime = item['pickedAt']?.toString() ?? order['pickedAt']?.toString();
        if (pTime != null && pTime.isNotEmpty) cur['PicTime'] = pTime;

        String? rTime = item['receivedAt']?.toString() ?? order['receivedAt']?.toString();
        if (rTime != null && rTime.isNotEmpty) cur['RecTime'] = rTime;
      }
    }


    final sortedDepartments = groupedAggregates.keys.toList()..sort();
    
    // Fixed column widths to ensure alignment across multiple DataTables
    const double nameColWidth = 330;
    const double dataColWidth = 85;
    const double hMargin = 12; // Matching DataTable horizontalMargin
    const double totalTableWidth = nameColWidth + (dataColWidth * 6) + (hMargin * 2);

    List<Widget> children = [];
    int pIndex = 0;
    
    for (var deptName in sortedDepartments) {
      // Add Department Header Widget
      children.add(
        Container(
          width: totalTableWidth,
          color: Colors.brown.shade400,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              deptName.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      );

      final categoriesMap = groupedAggregates[deptName]!;
      final sortedCategories = categoriesMap.keys.toList()..sort();

      for (var catName in sortedCategories) {
        // Add Category Header Widget
        children.add(
          Container(
            width: totalTableWidth,
            color: Colors.blueGrey.shade100,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                catName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        );

        final productsMap = categoriesMap[catName]!;
        final sortedProducts = productsMap.keys.toList()..sort();
        
        List<DataRow> productRows = [];
        for (var pName in sortedProducts) {
          final data = productsMap[pName]!;
          final bgColor = pIndex % 2 == 0 ? Colors.blue.withOpacity(0.05) : Colors.white;

          productRows.add(DataRow(
            color: MaterialStateProperty.all(bgColor),
            cells: [
              DataCell(SizedBox(
                width: nameColWidth,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24.0),
                  child: Text(pName, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )),
              DataCell(SizedBox(width: dataColWidth, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(data['Ord']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(_formatTime(data['OrdTime']), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]))),
              DataCell(SizedBox(width: dataColWidth, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(data['Snt']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(_formatTime(data['SntTime']), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]))),
              DataCell(SizedBox(width: dataColWidth, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(data['Con']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(_formatTime(data['ConTime']), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]))),
              DataCell(SizedBox(width: dataColWidth, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(data['Pic']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(_formatTime(data['PicTime']), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]))),
              DataCell(SizedBox(width: dataColWidth, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(data['Rec']!.round().toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(_formatTime(data['RecTime']), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]))),
              DataCell(SizedBox(width: dataColWidth, child: Text(data['Dif']!.round().toString(), style: TextStyle(color: data['Dif']! != 0 ? Colors.red : Colors.black, fontWeight: FontWeight.bold)))),
            ],
          ));
          pIndex++;
        }

        children.add(
          DataTable(
            horizontalMargin: hMargin,
            columnSpacing: 0,
            headingRowColor: MaterialStateProperty.all(Colors.blueGrey.shade700),
            headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            columns: [
              DataColumn(label: SizedBox(width: nameColWidth, child: const Text('Product Name'))),
              DataColumn(label: SizedBox(width: dataColWidth, child: const Text('Ord'))),
              DataColumn(label: SizedBox(width: dataColWidth, child: const Text('Snt'))),
              DataColumn(label: SizedBox(width: dataColWidth, child: const Text('Con'))),
              DataColumn(label: SizedBox(width: dataColWidth, child: const Text('Pic'))),
              DataColumn(label: SizedBox(width: dataColWidth, child: const Text('Rec'))),
              DataColumn(label: SizedBox(width: dataColWidth, child: const Text('Dif'))),
            ],
            rows: productRows,
          ),
        );
      }
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias, // Ensures background colors don't bleed out of card corners
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  double parseQty(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
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
              totalReqAmt += parseQty(item['requiredAmount']);
              totalSntAmt += parseQty(item['sendingAmount']);
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
            final req = parseQty(item['requiredQty']);
            final reqAmount = parseQty(item['requiredAmount']);
            final price = req > 0 ? (reqAmount / req).round() : 0;
            final sent = parseQty(item['sendingQty']);
            final conf = parseQty(item['confirmedQty']);
            final pick = parseQty(item['pickedQty']);
            final recv = parseQty(item['receivedQty']);
            final diff = parseQty(item['differenceQty']);
            final bgColor = idx % 2 == 0 ? Colors.white : Colors.brown.shade50;

            return Container(
              color: bgColor,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 1, child: Text(price.toString(), style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(req.round().toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(sent.round().toString(), style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(conf.round().toString(), style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(pick.round().toString(), style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(recv.round().toString(), style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(diff.round().toString(), style: TextStyle(fontSize: 11, color: diff != 0 ? Colors.red : Colors.black, fontWeight: diff != 0 ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center)),
                ],
              ),
            );
          }).toList(),
          // Total Row
          Builder(builder: (context) {
            double totalReq = 0, totalSent = 0, totalConf = 0, totalPick = 0, totalRecv = 0, totalDiff = 0;
            double totalReqAmt = 0, totalSntAmt = 0, totalRecAmt = 0;
            for (var item in items) {
              totalReq += parseQty(item['requiredQty']);
              totalSent += parseQty(item['sendingQty']);
              totalConf += parseQty(item['confirmedQty']);
              totalPick += parseQty(item['pickedQty']);
              totalRecv += parseQty(item['receivedQty']);
              totalDiff += parseQty(item['differenceQty']);
              totalReqAmt += parseQty(item['requiredAmount']);
              totalSntAmt += parseQty(item['sendingAmount']);
              totalRecAmt += parseQty(item['receivedAmount']);
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
                      Expanded(flex: 1, child: Text(totalReq.round().toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalSent.round().toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalConf.round().toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalPick.round().toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalRecv.round().toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center)),
                      Expanded(flex: 1, child: Text(totalDiff.round().toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: totalDiff != 0 ? Colors.yellow : Colors.white), textAlign: TextAlign.center)),
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
  void dispose() {
    _webVScroll.dispose();
    _webHScroll.dispose();
    super.dispose();
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
                  _buildDepartmentFilter(),
                  _buildCategoryFilter(),
                  _buildProductFilter(),
                  _buildStatusFilter(),
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
                selectedDepartmentId = 'ALL';
                selectedCategoryId = 'ALL';
                selectedProductId = 'ALL';
                selectedStatus = 'ALL';
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
