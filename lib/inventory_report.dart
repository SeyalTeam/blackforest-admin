import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'widgets/app_drawer.dart';

class InventoryReportPage extends StatefulWidget {
  final String? initialBranchId;

  const InventoryReportPage({super.key, this.initialBranchId});

  @override
  State<InventoryReportPage> createState() => _InventoryReportPageState();
}

class _InventoryReportPageState extends State<InventoryReportPage> {
  bool _loading = true;
  bool _loadingMetadata = true;

  List<Map<String, String>> branches = [];
  List<Map<String, String>> categories = [];
  String selectedBranchId = 'ALL';
  String selectedCategoryId = 'ALL';
  String searchQuery = '';

  List<Map<String, dynamic>> products = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialBranchId != null) {
      selectedBranchId = widget.initialBranchId!;
    }
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    const storage = FlutterSecureStorage();
    return await storage.read(key: 'token');
  }

  Future<void> _bootstrap() async {
    setState(() => _loadingMetadata = true);
    await Future.wait([
      _fetchBranches(),
      _fetchCategories(),
    ]);
    setState(() => _loadingMetadata = false);
    await _fetchInventoryReport();
  }

  Future<void> _fetchBranches() async {
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
    }
  }

  Future<void> _fetchCategories() async {
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
        final List<Map<String, String>> list = [
          {'id': 'ALL', 'name': 'All Categories'}
        ];
        for (var c in docs) {
          final id = c['id'] ?? c['_id'];
          final name = c['name'] ?? 'Unnamed Category';
          if (id != null) list.add({'id': id.toString(), 'name': name.toString()});
        }
        setState(() => categories = list);
      }
    } catch (e) {
      debugPrint('Error fetching categories: $e');
    }
  }

  Future<void> _fetchInventoryReport() async {
    setState(() => _loading = true);
    try {
      final token = await _getToken();
      if (token == null) return;

      var url = 'https://admin.theblackforestcakes.com/api/reports/inventory?limit=5000';
      if (selectedBranchId != 'ALL') {
        url += '&branch=$selectedBranchId';
      }
      if (selectedCategoryId != 'ALL') {
        url += '&category=$selectedCategoryId';
      }

      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List rawProducts = data['products'] ?? [];
        setState(() {
          products = rawProducts.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('Error fetching inventory report: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _getFlattenedRows() {
    final List<Map<String, dynamic>> rows = [];

    for (var p in products) {
      final pName = (p['name'] ?? 'Unknown').toString();
      if (searchQuery.isNotEmpty &&
          !pName.toLowerCase().contains(searchQuery.toLowerCase())) {
        continue;
      }

      final branchList = (p['branches'] as List?) ?? [];
      if (selectedBranchId != 'ALL') {
        final matching = branchList.firstWhere(
          (b) => b['id']?.toString() == selectedBranchId,
          orElse: () => null,
        );
        final instock = (matching != null ? (matching['instock'] ?? matching['inventory'] ?? 0) : 0);
        final numVal = num.tryParse(instock.toString()) ?? 0;
        rows.add({
          'productId': p['id'],
          'productName': pName,
          'branchId': selectedBranchId,
          'branchName': branches.firstWhere((b) => b['id'] == selectedBranchId, orElse: () => {'name': 'Branch'})['name'],
          'instock': numVal,
        });
      } else {
        // Show total or per branch
        for (var b in branchList) {
          final instock = b['instock'] ?? b['inventory'] ?? 0;
          final numVal = num.tryParse(instock.toString()) ?? 0;
          rows.add({
            'productId': p['id'],
            'productName': pName,
            'branchId': b['id'],
            'branchName': b['name'] ?? 'Unknown',
            'instock': numVal,
          });
        }
      }
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    final rows = _getFlattenedRows();

    final inStockCount = rows.where((r) => (r['instock'] as num) > 0).length;
    final outOfStockCount = rows.where((r) => (r['instock'] as num) <= 0).length;

    Widget mainContent = Column(
      children: [
        // Summary KPIs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              _buildKpiCard('Total Tracked', rows.length.toString(), Colors.blue),
              const SizedBox(width: 12),
              _buildKpiCard('In Stock', inStockCount.toString(), Colors.green),
              const SizedBox(width: 12),
              _buildKpiCard('Out of Stock (Billing Blocked)', outOfStockCount.toString(), Colors.red),
            ],
          ),
        ),
        const Divider(height: 1),

        // Filters
        Container(
          color: Colors.grey.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Branch filter
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: selectedBranchId,
                  decoration: InputDecoration(
                    labelText: 'Branch',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: branches.map((b) {
                    return DropdownMenuItem(value: b['id'], child: Text(b['name']!, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => selectedBranchId = val);
                      _fetchInventoryReport();
                    }
                  },
                ),
              ),

              // Category filter
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: selectedCategoryId,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: categories.map((c) {
                    return DropdownMenuItem(value: c['id'], child: Text(c['name']!, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => selectedCategoryId = val);
                      _fetchInventoryReport();
                    }
                  },
                ),
              ),

              // Search box
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search product...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (val) => setState(() => searchQuery = val.trim()),
                ),
              ),

              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.blue),
                onPressed: _fetchInventoryReport,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Products In-Stock List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? const Center(child: Text('No products found', style: TextStyle(color: Colors.grey, fontSize: 16)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final r = rows[index];
                        final num stock = r['instock'] ?? 0;
                        final isAvailable = stock > 0;

                        return Container(
                          color: isAvailable ? Colors.white : Colors.red.shade50.withOpacity(0.5),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            title: Text(
                              r['productName'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            subtitle: Text(
                              'Branch: ${r['branchName']}',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      stock.round().toString(),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color: isAvailable ? const Color(0xFF059669) : Colors.red,
                                      ),
                                    ),
                                    const Text('In Stock', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isAvailable ? Colors.green.shade50 : Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isAvailable ? Colors.green.shade300 : Colors.red.shade400),
                                  ),
                                  child: Text(
                                    isAvailable ? 'BILLING ALLOWED' : 'BILLING BLOCKED (0)',
                                    style: TextStyle(
                                      color: isAvailable ? Colors.green.shade800 : Colors.red.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Report (In-Stock)'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      drawer: isDesktop ? null : const Drawer(child: SafeArea(child: AppDrawer())),
      body: isDesktop
          ? Row(
              children: [
                Container(width: 250, color: Colors.white, child: const AppDrawer()),
                Expanded(child: mainContent),
              ],
            )
          : mainContent,
    );
  }

  Widget _buildKpiCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
