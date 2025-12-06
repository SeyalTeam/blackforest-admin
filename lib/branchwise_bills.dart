import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widgets/app_drawer.dart';

class BranchwiseBillsPage extends StatefulWidget {
  const BranchwiseBillsPage({super.key});

  @override
  State<BranchwiseBillsPage> createState() => _BranchwiseBillsPageState();
}

class _BranchwiseBillsPageState extends State<BranchwiseBillsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> branchSummaries = [];
  DateTime? fromDate;
  DateTime? toDate;

  double grandTotal = 0.0;
  double grandCash = 0.0;
  double grandUpi = 0.0;
  double grandCard = 0.0;
  int grandBills = 0;

  String? _latestBillId;
  String _lastUpdatedTime = '';

  final Map<String, double> _previousTotals = {};
  String? _justUpdatedBranch;

  StreamSubscription? _billListener;

  @override
  void initState() {
    super.initState();
    fromDate = DateTime.now();
    _fetchBranchSummaries().then((_) {
      _startLiveBillStream();
    });
  }

  @override
  void dispose() {
    _billListener?.cancel();
    super.dispose();
  }

  // ✅ Smart live updates (no polling)
  void _startLiveBillStream() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    // Here we mimic a "live" smart refresh via periodic check for new bill ID
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) timer.cancel();

      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);

      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();

      final response = await http.get(
        Uri.parse(
            'https://admin.theblackforestcakes.com/api/billings?limit=1&sort=-createdAt&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final docs = jsonDecode(response.body)['docs'] ?? [];
        if (docs.isNotEmpty) {
          final latest = docs.first;
          final id = latest['id'] ?? latest['_id'];
          final idStr = id?.toString();

          if (idStr != null && idStr != _latestBillId) {
            _latestBillId = idStr;
            _updateBranchSummariesSmoothly();
          }
        }
      }
    });
  }

  Future<void> _updateBranchSummariesSmoothly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);

      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();

      final response = await http.get(
        Uri.parse(
            'https://admin.theblackforestcakes.com/api/billings?limit=1000&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List docs = jsonDecode(response.body)['docs'] ?? [];
        final Map<String, Map<String, dynamic>> summaryMap = {};
        double totalSum = 0, cashSum = 0, upiSum = 0, cardSum = 0;
        int totalBills = 0;

        for (var bill in docs) {
          final branch = bill['branch']?['name'] ?? 'Unknown';
          final amount = _extractAmount(bill);
          final payment =
          (bill['paymentMethod'] ?? '').toString().trim().toLowerCase();

          summaryMap.putIfAbsent(branch, () {
            return {
              'branch': branch,
              'total': 0.0,
              'bills': 0,
              'cash': 0.0,
              'upi': 0.0,
              'card': 0.0,
            };
          });

          final s = summaryMap[branch]!;
          s['total'] += amount;
          s['bills'] += 1;
          if (payment.contains('cash')) s['cash'] += amount;
          if (payment.contains('upi')) s['upi'] += amount;
          if (payment.contains('card')) s['card'] += amount;

          totalSum += amount;
          totalBills++;
          if (payment.contains('cash')) cashSum += amount;
          if (payment.contains('upi')) upiSum += amount;
          if (payment.contains('card')) cardSum += amount;
        }

        // detect which branch changed
        String? updatedBranch;
        for (var b in summaryMap.values) {
          final old = _previousTotals[b['branch']] ?? 0;
          if (b['total'] != old) {
            updatedBranch = b['branch'];
            break;
          }
        }

        setState(() {
          _justUpdatedBranch = updatedBranch;
          branchSummaries = summaryMap.values.toList()
            ..sort((a, b) => (b['total'] as double).compareTo(a['total']));
          grandTotal = totalSum;
          grandBills = totalBills;
          grandCash = cashSum;
          grandUpi = upiSum;
          grandCard = cardSum;
          _lastUpdatedTime = DateFormat('hh:mm:ss a').format(DateTime.now());
        });

        // remove highlight after 1s
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) setState(() => _justUpdatedBranch = null);
        });
      }
    } catch (e) {
      debugPrint('Smooth update error: $e');
    }
  }

  Future<void> _fetchBranchSummaries() async {
    setState(() => _loading = true);
    await _updateBranchSummariesSmoothly();
    setState(() => _loading = false);
  }

  double _extractAmount(dynamic bill) {
    if (bill == null) return 0;
    final keys = ['total', 'totalAmount', 'grandTotal', 'amount'];
    for (var k in keys) {
      if (bill[k] != null) {
        final v = bill[k];
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
      }
    }
    return 0;
  }

  String _shortenBranchName(String name) {
    if (name.isEmpty) return 'UNK';
    return name.trim().substring(0, name.length < 3 ? name.length : 3).toUpperCase();
  }

  Widget _buildAnimatedTotal(String branch, double newTotal) {
    final previousTotal = _previousTotals[branch] ?? newTotal;
    _previousTotals[branch] = newTotal;

    final color =
    branch == _justUpdatedBranch ? Colors.green : Colors.green.shade700;

    // ✅ Wider width to handle up to crore values gracefully
    const double fixedWidth = 160;

    // ✅ Common style
    final textStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: color,
    );

    return SizedBox(
      width: fixedWidth,
      child: Align(
        alignment: Alignment.centerRight,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 600),
          tween: Tween(begin: previousTotal, end: newTotal),
          builder: (context, val, _) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              '₹${val.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: textStyle,
            ),
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    final safeFromDate = fromDate ?? DateTime.now();
    final dateFormat = DateFormat('MMM d');
    final dateLabel = toDate == null
        ? 'From: ${dateFormat.format(safeFromDate)}'
        : 'From: ${dateFormat.format(safeFromDate)}  To: ${dateFormat.format(toDate!)}';

    Widget mainContent = _loading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() {
                    fromDate = picked.start;
                    toDate = picked.end;
                  });
                  await _fetchBranchSummaries();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(dateLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: branchSummaries.length,
              itemBuilder: (context, index) {
                final s = branchSummaries[index];
                final bg = index % 2 == 0
                    ? Colors.grey.shade100
                    : Colors.pink.shade50;
                final shortBranch = _shortenBranchName(s['branch']);
                final pct = grandTotal == 0
                    ? '0%'
                    : '${((s['total'] / grandTotal) * 100).toStringAsFixed(1)}%';

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: s['branch'] == _justUpdatedBranch
                        ? Colors.green.withOpacity(0.1)
                        : bg,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(shortBranch,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87)),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('Bills: ${s['bills']}',
                                style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.black54)),
                          ),
                          Expanded(
                              flex: 2,
                              child: _buildAnimatedTotal(
                                  s['branch'], s['total'])),
                          Text(' ($pct)',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black45)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Icon(Icons.money,
                              color: Colors.black45, size: 20),
                          const SizedBox(width: 6),
                          Text('₹${s['cash'].toStringAsFixed(0)}',
                              style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 20),
                          const Icon(Icons.qr_code,
                              color: Colors.black45, size: 20),
                          const SizedBox(width: 6),
                          Text('₹${s['upi'].toStringAsFixed(0)}',
                              style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 20),
                          const Icon(Icons.credit_card,
                              color: Colors.black45, size: 20),
                          const SizedBox(width: 6),
                          Text('₹${s['card'].toStringAsFixed(0)}',
                              style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Card(
            color: Colors.black,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                      mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Bills: $grandBills',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15)),
                        Text('₹${grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 26))
                      ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.money,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 6),
                    Text('₹${grandCash.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: Colors.grey[400],
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 14),
                    const Icon(Icons.qr_code,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 6),
                    Text('₹${grandUpi.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: Colors.grey[400],
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 14),
                    const Icon(Icons.credit_card,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 6),
                    Text('₹${grandCard.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: Colors.grey[400],
                            fontWeight: FontWeight.bold))
                  ]),
                  const SizedBox(height: 8),
                  if (_lastUpdatedTime.isNotEmpty)
                    Text('Last updated: $_lastUpdatedTime',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                ],
              ),
            ),
          )
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch Wise Bills'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              tooltip: 'Manual Refresh',
              onPressed: _fetchBranchSummaries,
              icon: const Icon(Icons.refresh, color: Colors.white))
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
          Container(
            width: 250,
            color: Colors.white,
            child: const AppDrawer(),
          ),
          Expanded(child: mainContent),
        ],
      )
          : mainContent,
    );
  }
}
