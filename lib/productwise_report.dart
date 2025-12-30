import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'widgets/app_drawer.dart';

class ProductwiseReportPage extends StatefulWidget {
  const ProductwiseReportPage({super.key});

  @override
  State<ProductwiseReportPage> createState() => _ProductwiseReportPageState();
}

class _ProductwiseReportPageState extends State<ProductwiseReportPage> {
  bool _loading = true;
  bool _loadingBranches = true;
  bool _loadingCategories = true;
  bool _loadingProducts = true;

  List<Map<String, String>> branches = [];
  Map<String, String> categoryMap = {}; // ID -> Name
  List<Map<String, String>> categoriesList = []; // For Dropdown
  Map<String, String> productCategoryMap = {}; // ProductID -> CategoryID
  Map<String, String> productNameMap = {}; // ProductID -> Name

  String selectedBranchId = 'ALL';
  String selectedCategoryId = 'ALL';
  DateTime? fromDate;
  DateTime? toDate;

  List<Map<String, dynamic>> aggregatedData = [];
  double totalAmount = 0.0;
  double totalQty = 0.0;

  @override
  void initState() {
    super.initState();
    fromDate = DateTime.now();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _fetchBranches(),
      _fetchCategories(),
      _fetchProducts(),
    ]);
    await _fetchAndGroup();
  }

  Future<String?> _getToken() async {
    const storage = FlutterSecureStorage();
    return await storage.read(key: 'token');
  }

  Future<void> _fetchBranches() async {
    setState(() => _loadingBranches = true);
    try {
      final token = await _getToken();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/branches?limit=3000'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];
        final List<Map<String, String>> list = [
          {'id': 'ALL', 'name': 'All Branches'}
        ];
        for (var b in docs) {
          final id = b['id'] ?? b['_id'];
          final name = b['name'] ?? 'Unnamed Branch';
          if (id != null) list.add({'id': id.toString(), 'name': name.toString()});
        }
        setState(() => branches = list);
      }
    } catch (e) {
      debugPrint('Error fetching branches: $e');
    } finally {
      setState(() => _loadingBranches = false);
    }
  }

  Future<void> _fetchCategories() async {
    setState(() => _loadingCategories = true);
    try {
      final token = await _getToken();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/categories?limit=3000'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];
        final Map<String, String> tempMap = {};
        final List<Map<String, String>> cList = [
          {'id': 'ALL', 'name': 'All Categories'}
        ];

        for (var c in docs) {
          final id = c['id'] ?? c['_id'];
          final name = c['name'] ?? 'Unnamed Category';
          if (id != null) {
            tempMap[id.toString()] = name.toString();
            cList.add({'id': id.toString(), 'name': name.toString()});
          }
        }
        setState(() {
          categoryMap = tempMap;
          categoriesList = cList;
        });
      }
    } catch (e) {
      debugPrint('Error fetching categories: $e');
    } finally {
      setState(() => _loadingCategories = false);
    }
  }

  Future<void> _fetchProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final token = await _getToken();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/products?limit=5000&depth=0'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];
        final Map<String, String> pcMap = {};
        final Map<String, String> pnMap = {};
        
        for (var p in docs) {
          final id = (p['id'] ?? p['_id'])?.toString();
          final name = p['name']?.toString();
          
          final cat = p['category'];
          String? catId;
          if (cat is Map) {
             catId = (cat['id'] ?? cat['_id'])?.toString();
          } else if (cat is String) {
             catId = cat;
          }
          
          if (id != null) {
            if (catId != null) pcMap[id] = catId;
            if (name != null) pnMap[id] = name;
          }
        }
        setState(() {
          productCategoryMap = pcMap;
          productNameMap = pnMap;
        });
      }
    } catch (e) {
      debugPrint('Error fetching products: $e');
    } finally {
      setState(() => _loadingProducts = false);
    }
  }

  // Cache to store results
  final Map<String, List<Map<String, dynamic>>> _reportCache = {};
  final Map<String, double> _cacheTotalAmt = {};
  final Map<String, double> _cacheTotalQty = {};

  Future<void> _fetchAndGroup() async {
    if (fromDate == null) return;
    setState(() => _loading = true);

    try {
      final token = await _getToken();
      if (token == null) return;

      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);

      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();
      final cacheKey = '$startStr|$endStr|$selectedBranchId|$selectedCategoryId';

      // 1. Check Cache
      if (_reportCache.containsKey(cacheKey)) {
        setState(() {
          aggregatedData = _reportCache[cacheKey]!;
          totalAmount = _cacheTotalAmt[cacheKey]!;
          totalQty = _cacheTotalQty[cacheKey]!;
          _loading = false;
        });
        return;
      }

      // 2. Fetch Data
      String url =
          'https://admin.theblackforestcakes.com/api/billings?limit=3000&depth=0&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr';

      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }

      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        // 3. Process in Background
        final result = await compute(_processBillingData, {
          'body': res.body,
          'branches': branches,
          'categoryMap': categoryMap,
          'productCategoryMap': productCategoryMap,
          'productNameMap': productNameMap,
          'selectedCategoryId': selectedCategoryId,
        });

        final list = result['list'] as List<Map<String, dynamic>>;
        final tAmt = result['totalAmount'] as double;
        final tQty = result['totalQty'] as double;

        // 4. Update Cache & State
        _reportCache[cacheKey] = list;
        _cacheTotalAmt[cacheKey] = tAmt;
        _cacheTotalQty[cacheKey] = tQty;

        setState(() {
          aggregatedData = list;
          totalAmount = tAmt;
          totalQty = tQty;
        });
      }
    } catch (e) {
      debugPrint('Error fetching/grouping data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    );
    if (picked != null) {
      setState(() {
        fromDate = picked.start;
        toDate = picked.end;
      });
      await _fetchAndGroup();
    }
  }

  void _showProductDetails(Map<String, dynamic> productData) {
    final branches = (productData['branches'] as Map<String, Map<String, dynamic>>).values.toList();
    // Sort branches by amount desc
    branches.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    
    final prodTotal = productData['amount'] as double;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Expanded(child: Text('Breakdown: ${productData['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                   IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                 ],
               ),
               const SizedBox(height: 10),
               // Total Row
               Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                 child: Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                      const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('₹${prodTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                   ],
                 ),
               ),
               const SizedBox(height: 15),
               // Column Headers
               Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                 child: Row(
                   children: [
                     const Expanded(child: Text('BCH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey))),
                     SizedBox(
                       width: 60, 
                       child: Text('UNITS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700), textAlign: TextAlign.right)
                     ),
                     SizedBox(
                       width: 70,
                       child: Text('AMT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700), textAlign: TextAlign.right)
                     ),
                     SizedBox(
                       width: 60,
                       child: Text('%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700), textAlign: TextAlign.right)
                     ),
                   ],
                 ),
               ),
               const Divider(),
               ConstrainedBox(
                 constraints: const BoxConstraints(maxHeight: 500),
                 child: ListView.separated(
                   shrinkWrap: true,
                   itemCount: branches.length,
                   separatorBuilder: (_,__) => const Divider(height: 1),
                   itemBuilder: (context, index) {
                     final b = branches[index];
                     final amt = b['amount'] as double;
                     final qty = b['quantity'] as double;
                     
                     // Percentage of Total
                     final pct = prodTotal > 0 ? (amt / prodTotal * 100) : 0.0;
                     
                     String bName = b['name'].toString().trim();
                     if (bName.length > 3) {
                       bName = bName.substring(0, 3);
                     }
                     bName = bName.toUpperCase();
                     
                     return Padding(
                       padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                       child: Row(
                         children: [
                            Expanded(child: Text(bName, style: const TextStyle(fontWeight: FontWeight.w600))),
                            SizedBox(
                              width: 60, 
                              child: Text(qty.toStringAsFixed(1), style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)
                            ),
                            SizedBox(
                              width: 70,
                               child: Text(amt.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right)
                            ),
                            SizedBox(
                                width: 60,
                                child: Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 13, color: Colors.grey.shade600), textAlign: TextAlign.right)
                            ),
                         ],
                       ),
                     );
                   },
                 ),
               )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetAndRefresh() async {
    setState(() {
      selectedBranchId = 'ALL';
      selectedCategoryId = 'ALL';
      fromDate = DateTime.now();
      toDate = null;
    });
    await _fetchAndGroup();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    final safeFromDate = fromDate ?? DateTime.now();
    final dateFormat = DateFormat('MMM d');
    
    // Date Label
    final dateLabel = toDate == null
        ? dateFormat.format(safeFromDate)
        : '${dateFormat.format(safeFromDate)} - ${dateFormat.format(toDate!)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product-wise Report'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetAndRefresh,
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _fetchAndGroup,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Row 1: Calendar + Branch
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                   width: isDesktop ? width * 0.5 : double.infinity,
                   child: Column(
                    children: [
                       Row(
                        children: [
                          // Calendar
                          Expanded(
                            child: InkWell(
                              onTap: _pickDateRange,
                              child: Container(
                                height: 50,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.calendar_today, color: Colors.white, size: 16),
                                    const SizedBox(width: 8),
                                    Text(dateLabel,
                                        style: const TextStyle(
                                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                            overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Branch Dropdown
                          Expanded(
                             child: DropdownButtonFormField<String>(
                                    value: selectedBranchId,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                    items: branches
                                        .map((b) {
                                          String name = b['name'] ?? 'Unnamed';
                                          if (b['id'] == 'ALL') {
                                            name = 'ALL BRANCHES';
                                          } else {
                                             if (name.length > 3) name = name.substring(0, 3);
                                             name = name.toUpperCase();
                                          }
                                          
                                          return DropdownMenuItem<String>(
                                              value: b['id'],
                                              child: Text(name, overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.bold)),
                                            );
                                        })
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => selectedBranchId = v);
                                        _fetchAndGroup();
                                      }
                                    },
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Row 2: Category Filter
                      Row(
                        children: [
                           Expanded(
                            child: DropdownButtonFormField<String>(
                                    value: selectedCategoryId,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
                                      labelText: 'Filter by Category',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                    items: categoriesList
                                        .map((c) {
                                          return DropdownMenuItem<String>(
                                              value: c['id'],
                                              child: Text(c['name']!, overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w600)),
                                            );
                                        })
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => selectedCategoryId = v);
                                        _fetchAndGroup();
                                      }
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              if (_loading)
                _buildSkeleton(isDesktop)
              else ...[
                // Summary Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Product Sales',
                          style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('₹${totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: Colors.greenAccent, fontSize: 32, fontWeight: FontWeight.bold)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${totalQty.toStringAsFixed(1)} Units',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              const Text('Total Quantity',
                                  style: TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Report Data
                if (aggregatedData.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Text('No sales data found for this period.',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ),
                  )
                else if (isDesktop)
                  _buildWebTable()
                else
                  _buildMobileList(),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton(bool isDesktop) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 24),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 8,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (_, __) {
            return Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 16, width: 150, color: Colors.grey.shade200),
                      const SizedBox(height: 8),
                      Container(height: 12, width: 100, color: Colors.grey.shade200),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildWebTable() {
    if (selectedBranchId != 'ALL') {
      // Standard Table for Single Branch
      double sumQty = 0;
      int sumCount = 0;
      double sumAmount = 0;
      for (var r in aggregatedData) {
        sumQty += (r['quantity'] as double);
        sumCount += (r['count'] as int);
        sumAmount += (r['amount'] as double);
      }

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: Column(
          children: [
            DataTable(
              showCheckboxColumn: false,
              columnSpacing: 30,
              headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
              columns: const [
                DataColumn(label: Text('S.No', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Product', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Quantity', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('Items Sold', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('% of Total', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
              ],
              rows: [
                ...aggregatedData.asMap().entries.map((entry) {
                  final index = entry.key;
                  final row = entry.value;
                  final percentage = totalAmount > 0 ? (row['amount'] / totalAmount * 100) : 0.0;
                  return DataRow(
                    onSelectChanged: (_) => _showProductDetails(row),
                    cells: [
                      DataCell(Text((index + 1).toString())),
                      DataCell(Text(row['name'], style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text(row['quantity'].toStringAsFixed(1))),
                      DataCell(Text(row['count'].toString())),
                      DataCell(Text('₹${row['amount'].toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                      DataCell(Text('${percentage.toStringAsFixed(1)}%')),
                    ],
                  );
                }),
                // Footer Row
                DataRow(
                  color: MaterialStateProperty.all(Colors.grey.shade100),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                    DataCell(Text(sumQty.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text(sumCount.toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('₹${sumAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                    const DataCell(Text('100.0%', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Pivot Table for All Branches
    // 1. Calculate Branch Totals & Sort
    final columnBranches = branches.where((b) => b['id'] != 'ALL').toList();
    final Map<String, double> branchTotals = {};

    // Init totals
    for (var b in columnBranches) {
       branchTotals[b['name']!] = 0.0;
    }

    // Sum up
    for (var row in aggregatedData) {
       final branchMap = row['branches'] as Map<String, Map<String, dynamic>>;
       for (var b in columnBranches) {
          final bName = b['name']!;
          if (branchMap.containsKey(bName)) {
             branchTotals[bName] = (branchTotals[bName] ?? 0) + (branchMap[bName]!['amount'] as double);
          }
       }
    }

    // Sort cols by Total Amount Descending
    columnBranches.sort((a, b) {
       final amtA = branchTotals[a['name']] ?? 0.0;
       final amtB = branchTotals[b['name']] ?? 0.0;
       return amtB.compareTo(amtA);
    });

    // Prepare Totals for Footer
    double grandTotal = 0;
    for(var t in branchTotals.values) grandTotal += t;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 25,
          headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
          columns: [
            const DataColumn(label: Text('S.No', style: TextStyle(fontWeight: FontWeight.bold))),
            const DataColumn(label: Text('Product', style: TextStyle(fontWeight: FontWeight.bold))),
            ...columnBranches.map((b) {
               String name = b['name'] ?? '';
               if (name.length > 3) name = name.substring(0, 3);
               return DataColumn(
                 label: Text(name.toUpperCase(), 
                   style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)), 
                 numeric: true
               );
            }),
            const DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          ],
          rows: [
            ...aggregatedData.asMap().entries.map((entry) {
              final index = entry.key;
              final row = entry.value;
              final branchData = row['branches'] as Map<String, Map<String, dynamic>>? ?? {};

              return DataRow(
                onSelectChanged: (_) => _showProductDetails(row),
                cells: [
                  DataCell(Text((index + 1).toString())),
                  DataCell(Text(row['name'], style: const TextStyle(fontWeight: FontWeight.w600))),
                  // Dynamic Branch Cells (Amount)
                  ...columnBranches.map((b) {
                    final bName = b['name'];
                    double bAmt = 0.0;
                    if (bName != null && branchData.containsKey(bName)) {
                      bAmt = branchData[bName]!['amount'] as double? ?? 0.0;
                    }
                    return DataCell(
                      Text(bAmt == 0 ? '-' : bAmt.toStringAsFixed(0), 
                          style: bAmt == 0 ? const TextStyle(color: Colors.grey) : null),
                    );
                  }),
                  // Total
                  DataCell(Text('₹${row['amount'].toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                ],
              );
            }),
            // Footer Row (Pivot)
             DataRow(
               color: MaterialStateProperty.all(Colors.grey.shade100),
               cells: [
                 const DataCell(Text('')),
                 const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                 ...columnBranches.map((b) {
                    final total = branchTotals[b['name']] ?? 0.0;
                    return DataCell(Text(total == 0 ? '-' : total.toStringAsFixed(0), 
                       style: const TextStyle(fontWeight: FontWeight.bold)));
                 }),
                 DataCell(Text('₹${grandTotal.toStringAsFixed(0)}', 
                     style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
               ]
             )
          ],
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: aggregatedData.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = aggregatedData[index];
        final percentage = totalAmount > 0 ? (row['amount'] / totalAmount * 100) : 0.0;
        return InkWell(
          onTap: () => _showProductDetails(row),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Center(
                    child: Text(
                      (index + 1).toString(),
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('${row['quantity'].toStringAsFixed(1)} Units • ${row['count']} Items sold',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${row['amount'].toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                    const SizedBox(height: 4),
                    Text('${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Top-level independent function for background processing
Future<Map<String, dynamic>> _processBillingData(Map<String, dynamic> params) async {
  final body = params['body'] as String;
  final branches = params['branches'] as List<Map<String, String>>;
  final productCategoryMap = params['productCategoryMap'] as Map<String, String>;
  final productNameMap = params['productNameMap'] as Map<String, String>;
  final selectedCategoryId = params['selectedCategoryId'] as String;

  final data = jsonDecode(body);
  final List docs = data['docs'] ?? [];

  final Map<String, Map<String, dynamic>> aggregation = {};
  double totalSum = 0.0;
  double totalQuantity = 0.0;

  double parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  for (var bill in docs) {
    // Identify Branch Name
    String branchName = 'Unknown Branch';
    final branch = bill['branch'];
    if (branch is String) {
      final found = branches.firstWhere((b) => b['id'] == branch, orElse: () => {});
      if (found.isNotEmpty) branchName = found['name']!;
    } else if (branch is Map) {
      branchName = branch['name'] ?? 'Unknown Branch';
    }

    final List items = bill['items'] ?? [];
    for (var item in items) {
      String prodName = 'Unknown Product';
      String? prodId;
      String? catId;

      // Resolve Product ID
      final product = item['product'];
      if (product != null) {
        if (product is String) prodId = product;
        else if (product is Map) {
          prodId = (product['id'] ?? product['_id'])?.toString();
          prodName = product['name'] ?? 'Unknown Product';
        }
      }

      // If we only got ID, look up name
      if (prodId != null && productNameMap.containsKey(prodId)) {
        prodName = productNameMap[prodId]!;
      }

      // Resolve Category ID
      final itemCat = item['category'];
      if (itemCat != null) {
        if (itemCat is String) catId = itemCat;
        else if (itemCat is Map) catId = (itemCat['id'] ?? itemCat['_id'])?.toString();
      }

      // Fallback Category from Product
      if (catId == null && prodId != null) {
        catId = productCategoryMap[prodId];
      }

      // Filter by Category
      if (selectedCategoryId != 'ALL') {
        if (catId == null || catId != selectedCategoryId) {
          continue; // Skip this item
        }
      }

      final double qty = parseDouble(item['quantity']);
      final double subtotal = parseDouble(item['subtotal']);

      totalSum += subtotal;
      totalQuantity += qty;

      if (!aggregation.containsKey(prodName)) {
        aggregation[prodName] = {
          'name': prodName,
          'amount': 0.0,
          'quantity': 0.0,
          'count': 0,
          'branches': <String, Map<String, dynamic>>{}, 
        };
      }

      final prodEntry = aggregation[prodName]!;
      prodEntry['amount'] += subtotal;
      prodEntry['quantity'] += qty;
      prodEntry['count'] += 1;

      // Branch Breakdown
      final branchMap = prodEntry['branches'] as Map<String, Map<String, dynamic>>;
      if (!branchMap.containsKey(branchName)) {
        branchMap[branchName] = {
          'name': branchName,
          'amount': 0.0,
          'quantity': 0.0,
          'percent': 0.0,
        };
      }
      branchMap[branchName]!['amount'] += subtotal;
      branchMap[branchName]!['quantity'] += qty;
    }
  }

  final List<Map<String, dynamic>> list = aggregation.values.toList();
  list.sort((a, b) => b['amount'].compareTo(a['amount']));

  return {
    'list': list,
    'totalAmount': totalSum,
    'totalQty': totalQuantity,
  };
}
