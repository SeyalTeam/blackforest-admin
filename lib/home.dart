import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login.dart';
import 'admin_chat_page.dart';
import 'branchwise_bills.dart';
import 'bills_date_time_page.dart';
import 'timewise_report.dart';
import 'waiterwise_report.dart';
import 'closingentry_report.dart';
import 'expensewise_report.dart';
import 'return_orders.dart';
import 'stockorder_report.dart';
import 'categorywise_report.dart';
import 'productwise_report.dart';

import 'widgets/app_drawer.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  int _selectedGridIndex = 0;
  bool _loading = true;
  String? _error;

  // Data loaded for today
  double totalBalance = 0.0;
  List<Map<String, dynamic>> branchSummaries = [];
  double grandTotal = 0.0;
  int grandBills = 0;
  double grandCash = 0.0;
  double grandUpi = 0.0;
  double grandCard = 0.0;
  double grandExpense = 0.0;

  // Closing entries data
  double totalClosingSales = 0.0;
  double totalClosingExpenses = 0.0;
  double totalClosingNet = 0.0;

  String selectedBranch = 'ALL';
  String? _token;
  final Map<String, String> _branchNameById = {};

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _logout(BuildContext context) async {
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _notImplemented(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature: Not implemented yet'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    if (MediaQuery.of(context).size.width >= 1024) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => page));
    }
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _loading = true);
    try {
      final token = await _getToken();
      if (token == null) {
        setState(() {
          _loading = false;
          _error = "Not authenticated";
        });
        return;
      }

      // 1. Fetch branch lookup
      await _fetchBranchNameLookup(token);

      // 2. Fetch billings, expenses, and closing entries
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
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
        http.get(
          Uri.parse(
            'https://blackforest.vseyal.com/api/closing-entries?depth=1&limit=10000&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr',
          ),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ]);

      final billResponse = responses[0];
      final expenseResponse = responses[1];
      final closingResponse = responses[2];

      if (billResponse.statusCode == 401 ||
          expenseResponse.statusCode == 401 ||
          closingResponse.statusCode == 401) {
        setState(() {
          _loading = false;
          _error = "Session expired. Please log in again.";
        });
        return;
      }

      if (billResponse.statusCode != 200) {
        throw Exception("Billing API returned status ${billResponse.statusCode}");
      }
      if (expenseResponse.statusCode != 200) {
        throw Exception("Expense API returned status ${expenseResponse.statusCode}");
      }
      if (closingResponse.statusCode != 200) {
        throw Exception("Closing API returned status ${closingResponse.statusCode}");
      }

      // Parse closing entries
      double cSales = 0.0;
      double cExp = 0.0;
      double cNet = 0.0;
      final docs = jsonDecode(closingResponse.body)['docs'] ?? [];
      for (var d in docs) {
        cSales += (d["totalSales"] ?? 0).toDouble();
        cExp += (d["expenses"] ?? 0).toDouble();
        cNet += (d["net"] ?? 0).toDouble();
      }

      // Parse billings and expenses
      final List billDocs = jsonDecode(billResponse.body)['docs'] ?? [];
      final List expenseDocs = jsonDecode(expenseResponse.body)['docs'] ?? [];

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

      for (var exp in expenseDocs) {
        final branch = _extractBranchName(exp);
        final amount = _extractExpenseAmount(exp);

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

      setState(() {
        totalBalance = cNet;
        totalClosingSales = cSales;
        totalClosingExpenses = cExp;
        totalClosingNet = cNet;

        grandTotal = totalSum;
        grandBills = totalBills;
        grandCash = cashSum;
        grandUpi = upiSum;
        grandCard = cardSum;
        grandExpense = expenseSum;

        branchSummaries = summaryMap.values.toList()
          ..sort((a, b) => (b['total'] as double).compareTo(a['total']));

        _error = null;
      });
    } catch (e) {
      debugPrint("Dashboard fetch error: $e");
      setState(() => _error = "Error loading today's data: $e");
    } finally {
      setState(() => _loading = false);
    }
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

  Future<void> _fetchBranchNameLookup(String token) async {
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

  Future<String?> _getToken() async {
    if (_token != null) return _token;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    return _token;
  }

  String _formatCurrency(double? val) {
    if (val == null || val.isNaN || val.isInfinite) return '0.00';
    try {
      final formatter = NumberFormat('#,##,##0.00');
      return formatter.format(val);
    } catch (e) {
      try {
        return val.toStringAsFixed(2);
      } catch (_) {
        return '0.00';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width >= 1024;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        body: Row(
          children: [
            Container(
              width: 250,
              color: Colors.white,
              child: const AppDrawer(),
            ),
            Expanded(
              child: _buildDashboardTab(true),
            ),
          ],
        ),
      );
    }

    final List<Widget> tabs = [
      _buildDashboardTab(false),
      const BranchwiseBillsPage(isEmbedded: true),
      const WaiterwiseReportPage(isEmbedded: true),
      const ClosingEntryReportPage(isEmbedded: true),
      const AdminChatPage(isEmbedded: true),
    ];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      drawer: const Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(child: AppDrawer()),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0B355B),
        unselectedItemColor: Colors.grey[500],
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront_outlined),
            activeIcon: Icon(Icons.storefront),
            label: 'Branch',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_search_outlined),
            activeIcon: Icon(Icons.person_search),
            label: 'Waiter',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Closing',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_outlined),
            activeIcon: Icon(Icons.chat),
            label: 'Chat',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(bool isDesktop) {
    if (_loading && branchSummaries.isEmpty) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0B355B)),
        ),
      );
    }

    if (_error != null && branchSummaries.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    if (_error != null && _error!.contains("Session expired")) {
                      _logout(context);
                    } else {
                      _fetchDashboardData();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B355B),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_error != null && _error!.contains("Session expired") ? 'Log In' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDashboardData,
      color: const Color(0xFF0B355B),
      child: Scaffold(
        backgroundColor: isDesktop ? Colors.grey[100] : Colors.white,
        body: Stack(
          children: [
            Container(
              height: 150,
              decoration: const BoxDecoration(
                color: Color(0xFF0B355B),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'BLACKFOREST',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      Stack(
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.notifications_none, color: Colors.white, size: 26),
                            onPressed: () => _notImplemented(context, 'Notifications'),
                          ),
                          Positioned(
                            right: 2,
                            top: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 110),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 16,
                            offset: const Offset(0, -6),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 32.0, bottom: 24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[400],
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Total balance',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(Icons.info_outline, size: 16, color: Colors.grey[400]),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '₹${_formatCurrency(grandTotal)}',
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isDesktop) ...[
                            _buildMockupGrid(),
                            const SizedBox(height: 32),
                          ],
                          if (isDesktop) ...[
                            const SizedBox(height: 20),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                'Quick Actions',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _quickActionItem('Billing', Icons.receipt_long, Colors.blue, () => _navigateTo(context, const BillsDateTimePage())),
                                  _quickActionItem('Expenses', Icons.money_off, Colors.orange, () => _navigateTo(context, const ExpensewiseReportPage())),
                                  _quickActionItem('Stock', Icons.inventory_2, Colors.brown, () => _navigateTo(context, const StockOrderReportPage())),
                                  _quickActionItem('Return', Icons.assignment_return, Colors.red, () => _navigateTo(context, const ReturnOrdersPage())),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildBranchWiseBillsCard(),
                            const SizedBox(height: 20),
                            _buildClosingSettlementCard(),
                            const SizedBox(height: 24),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                'Operations Grid',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Wrap(
                                  spacing: 20,
                                  runSpacing: 16,
                                  alignment: WrapAlignment.spaceEvenly,
                                  children: [
                                    _operationsGridItem('CAKE', Icons.cake, Colors.purple, () => _navigateTo(context, const CategorywiseReportPage())),
                                    _operationsGridItem('LIVE', Icons.stream, Colors.green, () => _navigateTo(context, const BillsDateTimePage())),
                                    _operationsGridItem('TABLE', Icons.table_restaurant, Colors.teal, () => _notImplemented(context, 'Table-wise Report')),
                                    _operationsGridItem('TIME', Icons.alarm, Colors.blue, () => _navigateTo(context, const TimewiseReportPage())),
                                    _operationsGridItem('EXPENSE', Icons.receipt, Colors.orange, () => _navigateTo(context, const ExpensewiseReportPage())),
                                    _operationsGridItem('CLOSING', Icons.account_balance_wallet, Colors.deepPurple, () => _navigateTo(context, const ClosingEntryReportPage())),
                                    _operationsGridItem('PRODUCT', Icons.fastfood, Colors.cyan, () => _navigateTo(context, const ProductwiseReportPage())),
                                    _operationsGridItem('CATEGORY', Icons.category, Colors.indigo, () => _navigateTo(context, const CategorywiseReportPage())),
                                    _operationsGridItem('RETURN', Icons.assignment_return, Colors.red, () => _navigateTo(context, const ReturnOrdersPage())),
                                    _operationsGridItem('STOCK', Icons.inventory, Colors.brown, () => _navigateTo(context, const StockOrderReportPage())),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildSettingsCard(),
                            const SizedBox(height: 40),
                          ],
                        ],
                      ),
                    )
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBranchWiseBillsCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey[200]!, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Branch Wise Bills',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                TextButton(
                  onPressed: () {
                    if (MediaQuery.of(context).size.width >= 1024) {
                      _navigateTo(context, const BranchwiseBillsPage());
                    } else {
                      setState(() {
                        _currentIndex = 1;
                      });
                    }
                  },
                  child: const Text('See all', style: TextStyle(color: Color(0xFF0B355B), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildBranchPills(),
            const SizedBox(height: 16),
            _buildSelectedBranchMetrics(),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchPills() {
    final List<String> list = ['ALL', ...branchSummaries.map((s) => s['branch'].toString())];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemBuilder: (context, index) {
          final b = list[index];
          final isSelected = selectedBranch == b;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(
                b == 'ALL' ? 'ALL BRANCH' : b.toUpperCase(),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              selected: isSelected,
              selectedColor: const Color(0xFF0B355B),
              backgroundColor: Colors.grey[100],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onSelected: (selected) {
                setState(() {
                  selectedBranch = b;
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedBranchMetrics() {
    double total = 0.0;
    int bills = 0;
    double cash = 0.0;
    double upi = 0.0;
    double card = 0.0;
    double expense = 0.0;

    if (selectedBranch == 'ALL') {
      total = grandTotal;
      bills = grandBills;
      cash = grandCash;
      upi = grandUpi;
      card = grandCard;
      expense = grandExpense;
    } else {
      final s = branchSummaries.firstWhere(
        (element) => element['branch'] == selectedBranch,
        orElse: () => <String, dynamic>{},
      );
      if (s.isNotEmpty) {
        total = (s['total'] ?? 0.0) as double;
        bills = (s['bills'] ?? 0) as int;
        cash = (s['cash'] ?? 0.0) as double;
        upi = (s['upi'] ?? 0.0) as double;
        card = (s['card'] ?? 0.0) as double;
        expense = (s['expense'] ?? 0.0) as double;
      }
    }

    double handCash = cash - expense;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Billings', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 4),
                Text('₹${_formatCurrency(total)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Bills Count', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 4),
                Text('$bills', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ],
        ),
        const Divider(height: 24, thickness: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _paymentMethodItem('CASH', cash, Icons.money, Colors.green),
            _paymentMethodItem('UPI', upi, Icons.qr_code, Colors.purple),
            _paymentMethodItem('CARD', card, Icons.credit_card, Colors.blue),
          ],
        ),
        const Divider(height: 24, thickness: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Expenses', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 4),
                Text('₹${_formatCurrency(expense)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.redAccent)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Hand Cash', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 4),
                Text('₹${_formatCurrency(handCash)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: handCash >= 0 ? Colors.green : Colors.red)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _paymentMethodItem(String name, double amount, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 4),
        Text('₹${_formatCurrency(amount)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildClosingSettlementCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey[200]!, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Closing Settlement (Today)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                TextButton(
                  onPressed: () {
                    if (MediaQuery.of(context).size.width >= 1024) {
                      _navigateTo(context, const ClosingEntryReportPage());
                    } else {
                      setState(() {
                        _currentIndex = 3;
                      });
                    }
                  },
                  child: const Text('Details', style: TextStyle(color: Color(0xFF0B355B), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _settlementMetric('Sales', totalClosingSales, Colors.blue),
                _settlementMetric('Expenses', totalClosingExpenses, Colors.orange),
                _settlementMetric('Net Settled', totalClosingNet, Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _settlementMetric(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        const SizedBox(height: 4),
        Text('₹${_formatCurrency(value)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _quickActionItem(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _operationsGridItem(String label, IconData icon, Color color, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.15), width: 1),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey[200]!, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.grey[50],
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.black87),
            title: const Text('Settings / Config', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _notImplemented(context, 'Settings'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 14)),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMockupGrid() {
    final List<Map<String, dynamic>> items = [
      {
        'label': 'BILLING',
        'icon': Icons.receipt_long,
        'page': const BillsDateTimePage(),
      },
      {
        'label': 'EXPENSES',
        'icon': Icons.account_balance_wallet_outlined,
        'page': const ExpensewiseReportPage(),
      },
      {
        'label': 'STOCK',
        'icon': Icons.analytics_outlined,
        'page': const StockOrderReportPage(),
      },
      {
        'label': 'RETURN',
        'icon': Icons.replay,
        'page': const ReturnOrdersPage(),
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = _selectedGridIndex == index;
          return Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedGridIndex = index;
                  });
                  _navigateTo(context, item['page'] as Widget);
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF0B355B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Icon(
                      item['icon'] as IconData,
                      color: isSelected ? Colors.white : const Color(0xFF0B355B),
                      size: 26,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item['label'] as String,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
