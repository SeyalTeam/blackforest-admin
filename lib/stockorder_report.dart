import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/app_drawer.dart';
import 'constants.dart';

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

  Future<void> _fetchStockOrders() async {
    if (fromDate == null) return;
    setState(() => _loading = true);
    try {
      final token = await _getToken();
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);

      var url = 'https://admin.theblackforestcakes.com/api/stock-orders?limit=1000&depth=1'
          '&where[createdAt][greater_than]=${start.toUtc().toIso8601String()}'
          '&where[createdAt][less_than]=${end.toUtc().toIso8601String()}';

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
        });
      }
    } catch (e) {
      debugPrint('fetchStockOrders error: $e');
    } finally {
      setState(() => _loading = false);
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
        ? const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()))
        : DropdownButtonFormField<String>(
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

    return Card(
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
          // Data Rows with zebra stripes
          ...items.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDateSelector(),
                  // Could add more filters or stats here
                ],
              ),
              const SizedBox(height: 12),
              _buildBranchFilter(),
            ],
          ),
        ),
        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : stockOrders.isEmpty
              ? const Center(child: Text('No stock orders found'))
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: stockOrders.length,
            itemBuilder: (context, index) {
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
