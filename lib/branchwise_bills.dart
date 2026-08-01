import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widgets/app_drawer.dart';

class BranchwiseBillsPage extends StatefulWidget {
  final bool isEmbedded;
  const BranchwiseBillsPage({super.key, this.isEmbedded = false});

  @override
  State<BranchwiseBillsPage> createState() => _BranchwiseBillsPageState();
}

class _BranchwiseBillsPageState extends State<BranchwiseBillsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> branchSummaries = [];
  DateTime? fromDate;
  DateTime? toDate;
  String? _token;
  final Map<String, String> _branchNameById = {};

  double grandTotal = 0.0;
  double grandCash = 0.0;
  double grandUpi = 0.0;
  double grandCard = 0.0;
  double grandExpense = 0.0;
  int grandBills = 0;

  String? _latestBillId;
  String? _latestExpenseId;
  String _lastUpdatedTime = '';

  final Map<String, double> _previousTotals = {};
  String? _justUpdatedBranch;
  Timer? _liveRefreshTimer;
  bool _isLatestBillCheckInProgress = false;

  @override
  void initState() {
    super.initState();
    fromDate = DateTime.now();
    _initializePage();
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    super.dispose();
  }

  // ✅ Smart live updates (no polling)
  void _startLiveBillStream() async {
    final token = await _getToken();
    if (token == null || !mounted) return;

    _liveRefreshTimer?.cancel();

    // Here we mimic a "live" smart refresh via periodic check for new bill ID
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 20), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isLatestBillCheckInProgress) return;

      _isLatestBillCheckInProgress = true;
      try {
        final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
        final end = toDate != null
            ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
            : DateTime(
                fromDate!.year,
                fromDate!.month,
                fromDate!.day,
                23,
                59,
                59,
              );

        final startStr = start.toUtc().toIso8601String();
        final endStr = end.toUtc().toIso8601String();

        final responses = await Future.wait([
          http.get(
            Uri.parse(
              'https://blackforest.vseyal.com/api/billings?depth=0&limit=1&sort=-createdAt&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr&where[status][in][0]=completed&where[status][in][1]=settled',
            ),
            headers: {'Authorization': 'Bearer $token'},
          ),
          http.get(
            Uri.parse(
              'https://blackforest.vseyal.com/api/expenses?depth=0&limit=1&sort=-createdAt&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr',
            ),
            headers: {'Authorization': 'Bearer $token'},
          ),
        ]);
        final billResponse = responses[0];
        final expenseResponse = responses[1];

        bool shouldRefresh = false;
        if (billResponse.statusCode == 200) {
          final docs = jsonDecode(billResponse.body)['docs'] ?? [];
          if (docs.isNotEmpty) {
            final latestBillId = _extractDocId(docs.first);
            if (latestBillId != null && latestBillId != _latestBillId) {
              _latestBillId = latestBillId;
              shouldRefresh = true;
            }
          }
        }
        if (expenseResponse.statusCode == 200) {
          final docs = jsonDecode(expenseResponse.body)['docs'] ?? [];
          if (docs.isNotEmpty) {
            final latestExpenseId = _extractDocId(docs.first);
            if (latestExpenseId != null &&
                latestExpenseId != _latestExpenseId) {
              _latestExpenseId = latestExpenseId;
              shouldRefresh = true;
            }
          }
        }
        if (shouldRefresh) {
          await _updateBranchSummariesSmoothly();
        }
      } catch (e) {
        debugPrint('Live bill check error: $e');
      } finally {
        _isLatestBillCheckInProgress = false;
      }
    });
  }

  Future<void> _updateBranchSummariesSmoothly() async {
    try {
      final token = await _getToken();
      if (token == null) return;

      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(
              fromDate!.year,
              fromDate!.month,
              fromDate!.day,
              23,
              59,
              59,
            );

      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();

      final responses = await Future.wait([
        http.get(
          Uri.parse(
            'https://blackforest.vseyal.com/api/billings?depth=0&limit=0&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr&where[status][in][0]=completed&where[status][in][1]=settled',
          ),
          headers: {'Authorization': 'Bearer $token'},
        ),
        http.get(
          Uri.parse(
            'https://blackforest.vseyal.com/api/expenses?depth=0&limit=0&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr',
          ),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ]);
      final billResponse = responses[0];
      final expenseResponse = responses[1];

      if (billResponse.statusCode != 200 && expenseResponse.statusCode != 200) {
        return;
      }

      final List billDocs = billResponse.statusCode == 200
          ? (jsonDecode(billResponse.body)['docs'] ?? [])
          : [];
      final List expenseDocs = expenseResponse.statusCode == 200
          ? (jsonDecode(expenseResponse.body)['docs'] ?? [])
          : [];

      if (billDocs.isNotEmpty) {
        _latestBillId = _extractDocId(billDocs.first);
      }
      if (expenseDocs.isNotEmpty) {
        _latestExpenseId = _extractDocId(expenseDocs.first);
      }

      final Map<String, Map<String, dynamic>> summaryMap = {};
      double totalSum = 0, cashSum = 0, upiSum = 0, cardSum = 0, expenseSum = 0;
      int totalBills = 0;

      for (var bill in billDocs) {
        final status = (bill['status'] ?? '').toString().toLowerCase().trim();
        if (status != 'completed' && status != 'settled') continue;

        final branch = _extractBranchName(bill);
        final amount = _extractAmount(bill);
        final payment = (bill['paymentMethod'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        summaryMap.putIfAbsent(branch, () {
          return {
            'branch': branch,
            'total': 0.0,
            'bills': 0,
            'cash': 0.0,
            'upi': 0.0,
            'card': 0.0,
            'expense': 0.0,
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

      for (var expense in expenseDocs) {
        final branch = _extractBranchName(expense);
        final amount = _extractExpenseAmount(expense);

        summaryMap.putIfAbsent(branch, () {
          return {
            'branch': branch,
            'total': 0.0,
            'bills': 0,
            'cash': 0.0,
            'upi': 0.0,
            'card': 0.0,
            'expense': 0.0,
          };
        });

        final s = summaryMap[branch]!;
        s['expense'] += amount;
        expenseSum += amount;
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
        grandExpense = expenseSum;
        _lastUpdatedTime = DateFormat('hh:mm:ss a').format(DateTime.now());
      });

      // remove highlight after 1s
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _justUpdatedBranch = null);
      });
    } catch (e) {
      debugPrint('Smooth update error: $e');
    }
  }

  Future<void> _fetchBranchSummaries() async {
    setState(() => _loading = true);
    await _updateBranchSummariesSmoothly();
    if (!mounted) return;
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

  String _extractBranchName(dynamic data) {
    final branch = data?['branch'];
    if (branch is Map) {
      final name = (branch['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
      final nestedId = _extractDocId(branch);
      if (nestedId != null && _branchNameById.containsKey(nestedId)) {
        return _branchNameById[nestedId]!;
      }
    } else if (branch is String) {
      final name = (_branchNameById[branch] ?? branch).trim();
      if (name.isNotEmpty) return name;
    }
    return 'Unknown';
  }

  String? _extractDocId(dynamic data) {
    if (data == null) return null;
    final id = data['id'] ?? data['_id'];
    if (id is Map) {
      final mapId = id[r'$oid'] ?? id['id'];
      return mapId?.toString();
    }
    return id?.toString();
  }

  double _extractExpenseAmount(dynamic expense) {
    if (expense == null) return 0.0;
    final details = expense['details'];
    if (details is List && details.isNotEmpty) {
      double sum = 0.0;
      for (final detail in details) {
        if (detail is! Map) continue;
        final value = detail['amount'];
        if (value is num) {
          sum += value.toDouble();
        } else if (value is String) {
          sum += double.tryParse(value) ?? 0.0;
        }
      }
      return sum;
    }

    final keys = [
      'expenseAmount',
      'expenses',
      'total',
      'totalAmount',
      'amount',
    ];
    for (final key in keys) {
      final value = expense[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  Future<String?> _getToken() async {
    if (_token != null) return _token;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    return _token;
  }

  Future<void> _fetchBranchNameLookup() async {
    final token = await _getToken();
    if (token == null) return;
    try {
      final response = await http.get(
        Uri.parse(
          'https://blackforest.vseyal.com/api/branches?depth=0&limit=3000',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) return;
      final docs = (jsonDecode(response.body)['docs'] ?? []) as List;
      _branchNameById.clear();
      for (final branch in docs) {
        if (branch is! Map) continue;
        final id = _extractDocId(branch);
        final name = (branch['name'] ?? '').toString().trim();
        if (id != null && name.isNotEmpty) {
          _branchNameById[id] = name;
        }
      }
    } catch (e) {
      debugPrint('Branch lookup fetch error: $e');
    }
  }

  Future<void> _initializePage() async {
    await _fetchBranchNameLookup();
    await _fetchBranchSummaries();
    _startLiveBillStream();
  }

  String _shortenBranchName(String name) {
    if (name.isEmpty) return 'UNK';
    return name
        .trim()
        .substring(0, name.length < 3 ? name.length : 3)
        .toUpperCase();
  }

  Widget _buildAnimatedTotal(String branch, double newTotal) {
    final previousTotal = _previousTotals[branch] ?? newTotal;
    _previousTotals[branch] = newTotal;

    final color = branch == _justUpdatedBranch
        ? Colors.green
        : Colors.green.shade700;

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
    final grandHandCash = grandCash - grandExpense;
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
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
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
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            dateLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                      final branchHandCash =
                          ((s['cash'] ?? 0.0) as num).toDouble() -
                          ((s['expense'] ?? 0.0) as num).toDouble();
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
                              ? Colors.green.withValues(alpha: 0.1)
                              : bg,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    shortBranch,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Bills: ${s['bills']}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: _buildAnimatedTotal(
                                    s['branch'],
                                    s['total'],
                                  ),
                                ),
                                Text(
                                  ' ($pct)',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                const Icon(
                                  Icons.money,
                                  color: Colors.black45,
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '₹${s['cash'].toStringAsFixed(0)}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                const Icon(
                                  Icons.qr_code,
                                  color: Colors.black45,
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '₹${s['upi'].toStringAsFixed(0)}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                const Icon(
                                  Icons.credit_card,
                                  color: Colors.black45,
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '₹${s['card'].toStringAsFixed(0)}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text(
                                  'Expense: ₹${s['expense'].toStringAsFixed(0)}',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade700,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Hand Cash = ₹${branchHandCash.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Bills: $grandBills',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              '₹${grandTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 26,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.money,
                              color: Colors.white70,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '₹${grandCash.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Icon(
                              Icons.qr_code,
                              color: Colors.white70,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '₹${grandUpi.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Icon(
                              Icons.credit_card,
                              color: Colors.white70,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '₹${grandCard.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Expense: ₹${grandExpense.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade700,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Hand Cash = ₹${grandHandCash.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_lastUpdatedTime.isNotEmpty)
                          Text(
                            'Last updated: $_lastUpdatedTime',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );

    if (widget.isEmbedded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Branch Wise Bills'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              tooltip: 'Manual Refresh',
              onPressed: _fetchBranchSummaries,
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
          ],
        ),
        body: mainContent,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch Wise Bills'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Manual Refresh',
            onPressed: _fetchBranchSummaries,
            icon: const Icon(Icons.refresh, color: Colors.white),
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
