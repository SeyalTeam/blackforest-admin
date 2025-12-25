import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'widgets/app_drawer.dart';

class CategorywiseReportPage extends StatefulWidget {
  const CategorywiseReportPage({super.key});

  @override
  State<CategorywiseReportPage> createState() => _CategorywiseReportPageState();
}

class _CategorywiseReportPageState extends State<CategorywiseReportPage> {
  bool _loading = true;
  bool _loadingBranches = true;
  bool _loadingCategories = true;
  bool _loadingProducts = true;

  List<Map<String, String>> branches = [];
  Map<String, String> categoryMap = {}; // ID -> Name
  Map<String, String> productCategoryMap = {}; // ProductID -> CategoryID
  String selectedBranchId = 'ALL';
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
        for (var c in docs) {
          final id = c['id'] ?? c['_id'];
          final name = c['name'] ?? 'Unnamed Category';
          if (id != null) tempMap[id.toString()] = name.toString();
        }
        setState(() => categoryMap = tempMap);
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
      // Fetch only needed fields if possible, but Payload limits often depth. depth=0 gives IDs.
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/products?limit=5000&depth=0'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];
        final Map<String, String> tempMap = {};
        for (var p in docs) {
          final id = (p['id'] ?? p['_id'])?.toString();
          // With depth=0, category might be an ID string
          final cat = p['category'];
          String? catId;
          if (cat is Map) {
             catId = (cat['id'] ?? cat['_id'])?.toString();
          } else if (cat is String) {
             catId = cat;
          }
          
          if (id != null && catId != null) {
            tempMap[id] = catId;
          }
        }
        setState(() => productCategoryMap = tempMap);
      }
    } catch (e) {
      debugPrint('Error fetching products: $e');
    } finally {
      setState(() => _loadingProducts = false);
    }
  }

  // Cache to store results: Key = "startIso|endIso|branchId" -> Value = List<Map<...>>
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
      final cacheKey = '$startStr|$endStr|$selectedBranchId';

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

  double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
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

  void _showBranchDetails(Map<String, dynamic> categoryData) {
    final branches = (categoryData['branches'] as Map<String, Map<String, dynamic>>).values.toList();
    // Sort branches by amount desc
    branches.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    
    final catTotal = categoryData['amount'] as double;

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
                   Expanded(child: Text('Breakdown: ${categoryData['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
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
                      Text('₹${catTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
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
                     final pct = catTotal > 0 ? (amt / catTotal * 100) : 0.0;
                     
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
    
    // Date Label: "Oct 25 - Dec 25"
    final dateLabel = toDate == null
        ? dateFormat.format(safeFromDate)
        : '${dateFormat.format(safeFromDate)} - ${dateFormat.format(toDate!)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Category-wise Report'),
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
              // Filters Row
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: isDesktop ? width * 0.5 : double.infinity,
                  child: Row(
                    children: [
                      // Calendar
                      Expanded(
                        child: InkWell(
                          onTap: _pickDateRange,
                          child: Container(
                            height: 50, // Match typical input height
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
                                        name = 'ALL';
                                      } else {
                                         // Format to 3 letters CAPS
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
                      const Text('Total Category Sales',
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
                              const Text('Across all categories',
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
        // Skeleton Summary Card
        Container(
          width: double.infinity,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 24),
        // Skeleton List/Table
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(height: 16, width: 60, color: Colors.grey.shade200),
                    const SizedBox(height: 8),
                    Container(height: 12, width: 40, color: Colors.grey.shade200),
                  ],
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
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 40,
          headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
          columns: const [
            DataColumn(label: Text('S.No', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Quantity', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Items Sold', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('% of Total', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          ],
          rows: aggregatedData.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final percentage = totalAmount > 0 ? (row['amount'] / totalAmount * 100) : 0.0;
            return DataRow(
              onSelectChanged: (_) => _showBranchDetails(row),
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
          }).toList(),
        ),
      );
    }

    // Pivot Table for All Branches
    // 1. Prepare Columns: S.No, Category, [Branch1], [Branch2]..., Total
    final branchCols = branches.where((b) => b['id'] != 'ALL').toList();
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 24, // Tighter spacing for many columns
          headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
          columns: [
            const DataColumn(label: Text('S.No', style: TextStyle(fontWeight: FontWeight.bold))),
            const DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
            ...branchCols.map((b) {
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
          rows: aggregatedData.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final branchMap = row['branches'] as Map<String, Map<String, dynamic>>;

            return DataRow(
              onSelectChanged: (_) => _showBranchDetails(row),
              cells: [
                DataCell(Text((index + 1).toString())),
                DataCell(Text(row['name'], style: const TextStyle(fontWeight: FontWeight.w600))),
                // Dynamic Branch Cells
                ...branchCols.map((b) {
                  final bName = b['name'];
                  final bData = branchMap[bName];
                  final val = bData != null ? (bData['amount'] as double) : 0.0;
                  return DataCell(
                    Text(val == 0 ? '-' : val.toStringAsFixed(0), 
                         style: val == 0 ? const TextStyle(color: Colors.grey) : null),
                  );
                }),
                // Total
                DataCell(Text('₹${row['amount'].toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
              ],
            );
          }).toList(),
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
          onTap: () => _showBranchDetails(row),
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
  final categoryMap = params['categoryMap'] as Map<String, String>;
  final productCategoryMap = params['productCategoryMap'] as Map<String, String>;

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
      String catName = 'Uncategorized';
      String? catId;

      // Resolve Category ID
      final itemCat = item['category'];
      if (itemCat != null) {
        if (itemCat is String) catId = itemCat;
        else if (itemCat is Map) catId = (itemCat['id'] ?? itemCat['_id'])?.toString();
      }

      if (catId == null) {
        final product = item['product'];
        String? prodId;
        if (product is String) prodId = product;
        else if (product is Map) prodId = (product['id'] ?? product['_id'])?.toString();
        
        if (prodId != null) {
          catId = productCategoryMap[prodId];
        }
      }

      if (catId != null) {
        catName = categoryMap[catId] ?? 'Uncategorized';
      }

      final double qty = parseDouble(item['quantity']);
      final double subtotal = parseDouble(item['subtotal']);

      totalSum += subtotal;
      totalQuantity += qty;

      if (!aggregation.containsKey(catName)) {
        aggregation[catName] = {
          'name': catName,
          'amount': 0.0,
          'quantity': 0.0,
          'count': 0,
          'branches': <String, Map<String, dynamic>>{}, 
        };
      }

      final catEntry = aggregation[catName]!;
      catEntry['amount'] += subtotal;
      catEntry['quantity'] += qty;
      catEntry['count'] += 1;

      // Branch Breakdown
      final branchMap = catEntry['branches'] as Map<String, Map<String, dynamic>>;
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
