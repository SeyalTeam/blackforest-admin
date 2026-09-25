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
import 'kitchen_order.dart';
import 'widgets/app_drawer.dart';

class ReportModule {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color primaryColor;
  final Color lightColor;
  final String category; // 'All', 'Billing', 'Analytics', 'Finance'
  final Widget page;
  final String? badge;

  const ReportModule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primaryColor,
    required this.lightColor,
    required this.category,
    required this.page,
    this.badge,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  String _selectedCategory = 'All';
  DateTime _selectedDate = DateTime.now();
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

  final List<ReportModule> _allModules = const [
    ReportModule(
      id: 'live_billing',
      title: 'Live Billing',
      subtitle: 'Real-time billing & receipts',
      icon: Icons.receipt_long_rounded,
      primaryColor: Color(0xFF0284C7),
      lightColor: Color(0xFFE0F2FE),
      category: 'Billing',
      page: BillsDateTimePage(),
      badge: 'LIVE',
    ),
    ReportModule(
      id: 'branch_bills',
      title: 'Branch-wise Bills',
      subtitle: 'Outlets breakdown & sales',
      icon: Icons.storefront_rounded,
      primaryColor: Color(0xFF0F766E),
      lightColor: Color(0xFFCCFBF1),
      category: 'Billing',
      page: BranchwiseBillsPage(),
    ),
    ReportModule(
      id: 'kitchen_order',
      title: 'Kitchen Orders',
      subtitle: 'KOT queue & preparations',
      icon: Icons.restaurant_rounded,
      primaryColor: Color(0xFFEA580C),
      lightColor: Color(0xFFFFEDD5),
      category: 'Billing',
      page: KitchenOrderPage(),
      badge: 'KOT',
    ),
    ReportModule(
      id: 'return_orders',
      title: 'Return Orders',
      subtitle: 'Cancelled & returned bills',
      icon: Icons.assignment_return_rounded,
      primaryColor: Color(0xFFDC2626),
      lightColor: Color(0xFFFEE2E2),
      category: 'Billing',
      page: ReturnOrdersPage(),
    ),
    ReportModule(
      id: 'category_report',
      title: 'Category Sales',
      subtitle: 'Cakes, pastry & item groups',
      icon: Icons.cake_rounded,
      primaryColor: Color(0xFF9333EA),
      lightColor: Color(0xFFF3E8FF),
      category: 'Analytics',
      page: CategorywiseReportPage(),
    ),
    ReportModule(
      id: 'product_report',
      title: 'Product Sales',
      subtitle: 'Item volume & revenue rank',
      icon: Icons.fastfood_rounded,
      primaryColor: Color(0xFF2563EB),
      lightColor: Color(0xFFDBEAFE),
      category: 'Analytics',
      page: ProductwiseReportPage(),
    ),
    ReportModule(
      id: 'timewise_report',
      title: 'Time-wise Report',
      subtitle: 'Hourly peak sales analysis',
      icon: Icons.alarm_rounded,
      primaryColor: Color(0xFF4F46E5),
      lightColor: Color(0xFFE0E7FF),
      category: 'Analytics',
      page: TimewiseReportPage(),
    ),
    ReportModule(
      id: 'waiter_report',
      title: 'Waiter Performance',
      subtitle: 'Staff orders & punch audits',
      icon: Icons.badge_rounded,
      primaryColor: Color(0xFFD97706),
      lightColor: Color(0xFFFEF3C7),
      category: 'Analytics',
      page: WaiterwiseReportPage(),
    ),
    ReportModule(
      id: 'expense_report',
      title: 'Store Expenses',
      subtitle: 'Expense logs & vouchers',
      icon: Icons.account_balance_wallet_rounded,
      primaryColor: Color(0xFFE11D48),
      lightColor: Color(0xFFFFE4E6),
      category: 'Finance',
      page: ExpensewiseReportPage(),
    ),
    ReportModule(
      id: 'closing_entries',
      title: 'Closing Entries',
      subtitle: 'Daily drawer & settlement',
      icon: Icons.point_of_sale_rounded,
      primaryColor: Color(0xFF059669),
      lightColor: Color(0xFFD1FAE5),
      category: 'Finance',
      page: ClosingEntryReportPage(),
      badge: 'DAILY',
    ),
    ReportModule(
      id: 'stock_orders',
      title: 'Stock Orders',
      subtitle: 'Inventory indent & transfers',
      icon: Icons.inventory_2_rounded,
      primaryColor: Color(0xFF78350F),
      lightColor: Color(0xFFFEF3C7),
      category: 'Finance',
      page: StockOrderReportPage(),
    ),
    ReportModule(
      id: 'staff_chat',
      title: 'Staff Comms',
      subtitle: 'Branch chat & announcements',
      icon: Icons.forum_rounded,
      primaryColor: Color(0xFF0284C7),
      lightColor: Color(0xFFE0F2FE),
      category: 'Finance',
      page: AdminChatPage(),
    ),
  ];

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
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    if (MediaQuery.of(context).size.width >= 1024) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => page));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0B355B),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchDashboardData();
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
      final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final end = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
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

  List<ReportModule> get _filteredModules {
    if (_selectedCategory == 'All') return _allModules;
    return _allModules
        .where((m) => m.category.toLowerCase() == _selectedCategory.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool isDesktop = width >= 1024;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Row(
          children: [
            const SizedBox(
              width: 260,
              child: AppDrawer(),
            ),
            VerticalDivider(width: 1, color: Colors.grey[200]),
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
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(child: AppDrawer()),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF0B355B),
          unselectedItemColor: const Color(0xFF94A3B8),
          elevation: 0,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.storefront_outlined),
              activeIcon: Icon(Icons.storefront_rounded),
              label: 'Branches',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.badge_outlined),
              activeIcon: Icon(Icons.badge_rounded),
              label: 'Waiters',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.point_of_sale_outlined),
              activeIcon: Icon(Icons.point_of_sale_rounded),
              label: 'Closing',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.forum_outlined),
              activeIcon: Icon(Icons.forum_rounded),
              label: 'Comms',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab(bool isDesktop) {
    if (_loading && branchSummaries.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF0B355B)),
              SizedBox(height: 16),
              Text(
                'Loading live operations...',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null && branchSummaries.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                ),
                const SizedBox(height: 20),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_error != null && _error!.contains("Session expired")) {
                      _logout(context);
                    } else {
                      _fetchDashboardData();
                    }
                  },
                  icon: Icon(_error != null && _error!.contains("Session expired") ? Icons.login : Icons.refresh_rounded),
                  label: Text(_error != null && _error!.contains("Session expired") ? 'Log In Again' : 'Retry Load'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B355B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildFixedHeader(context, isDesktop),
      body: RefreshIndicator(
        onRefresh: _fetchDashboardData,
        color: const Color(0xFF0B355B),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32.0 : 16.0,
              vertical: 20.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Executive Hero Card
                _buildExecutiveSummaryBanner(),
                const SizedBox(height: 24),

                // Quick Stats & Payment Split
                _buildPaymentSplitCard(),
                const SizedBox(height: 24),

                // Branch Filtering & Overview
                _buildBranchFilterSection(),
                const SizedBox(height: 28),

                // SECTION: Complete Report Root Path Grid
                _buildReportGridSection(isDesktop),
                const SizedBox(height: 28),

                // Closing Settlement Banner
                _buildClosingSettlementCard(),
                const SizedBox(height: 24),

                // Top Branches Leaderboard
                if (branchSummaries.length > 1) ...[
                  _buildTopBranchesCard(),
                  const SizedBox(height: 24),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildFixedHeader(BuildContext context, bool isDesktop) {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    final dateDisplay = isToday
        ? 'Today, ${DateFormat('d MMM yyyy').format(_selectedDate)}'
        : DateFormat('EEE, d MMM yyyy').format(_selectedDate);

    return PreferredSize(
      preferredSize: const Size.fromHeight(68),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF07213A), Color(0xFF0B355B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!isDesktop) ...[
                  IconButton(
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'BLACKFOREST',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateDisplay,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Select Date',
                  icon: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 24),
                  onPressed: _pickDate,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExecutiveSummaryBanner() {
    double selectedSales = grandTotal;
    int selectedBills = grandBills;
    double selectedExpense = grandExpense;

    if (selectedBranch != 'ALL') {
      final s = branchSummaries.firstWhere(
        (b) => b['branch'] == selectedBranch,
        orElse: () => <String, dynamic>{},
      );
      if (s.isNotEmpty) {
        selectedSales = (s['total'] ?? 0.0) as double;
        selectedBills = (s['bills'] ?? 0) as int;
        selectedExpense = (s['expense'] ?? 0.0) as double;
      }
    }

    final double netInHand = selectedSales - selectedExpense;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B355B), Color(0xFF1E4976)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B355B).withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    selectedBranch == 'ALL' ? 'ALL OUTLETS REVENUE' : '${selectedBranch.toUpperCase()} REVENUE',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      '$selectedBills Bills',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                '₹',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _formatCurrency(selectedSales),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Expenses',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${_formatCurrency(selectedExpense)}',
                      style: const TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Container(height: 24, width: 1, color: Colors.white.withOpacity(0.2)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Est. Net Balance',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${_formatCurrency(netInHand)}',
                      style: const TextStyle(
                        color: Color(0xFF86EFAC),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSplitCard() {
    double cash = grandCash;
    double upi = grandUpi;
    double card = grandCard;
    double expense = grandExpense;

    if (selectedBranch != 'ALL') {
      final s = branchSummaries.firstWhere(
        (b) => b['branch'] == selectedBranch,
        orElse: () => <String, dynamic>{},
      );
      if (s.isNotEmpty) {
        cash = (s['cash'] ?? 0.0) as double;
        upi = (s['upi'] ?? 0.0) as double;
        card = (s['card'] ?? 0.0) as double;
        expense = (s['expense'] ?? 0.0) as double;
      }
    }

    double handCash = cash - expense;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Payment Mode Distribution',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              Icon(Icons.pie_chart_outline_rounded, color: Color(0xFF64748B), size: 18),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildPaymentMethodTile(
                  label: 'CASH',
                  amount: cash,
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPaymentMethodTile(
                  label: 'UPI / QR',
                  amount: upi,
                  icon: Icons.qr_code_2_rounded,
                  color: const Color(0xFF8B5CF6),
                  bgColor: const Color(0xFFF5F3FF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPaymentMethodTile(
                  label: 'CARD',
                  amount: card,
                  icon: Icons.credit_card_rounded,
                  color: const Color(0xFF0284C7),
                  bgColor: const Color(0xFFF0F9FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      handCash >= 0 ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                      size: 16,
                      color: handCash >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Cash in Hand (Cash - Exp):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                Text(
                  '₹${_formatCurrency(handCash)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: handCash >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodTile({
    required String label,
    required double amount,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '₹${_formatCurrency(amount)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchFilterSection() {
    final List<String> list = ['ALL', ...branchSummaries.map((s) => s['branch'].toString())];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Filter by Outlet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            if (branchSummaries.isNotEmpty)
              Text(
                '${branchSummaries.length} Outlets Active',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            itemBuilder: (context, index) {
              final b = list[index];
              final isSelected = selectedBranch == b;

              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(
                    b == 'ALL' ? '🌟 ALL BRANCHES' : b.toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF334155),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFF0B355B),
                  backgroundColor: Colors.white,
                  elevation: isSelected ? 2 : 0,
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF0B355B) : const Color(0xFFE2E8F0),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (selected) {
                    setState(() {
                      selectedBranch = b;
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReportGridSection(bool isDesktop) {
    final modules = _filteredModules;
    final categories = ['All', 'Billing', 'Analytics', 'Finance'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All Reports & Modules',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Complete administrative root access (${_allModules.length} Modules)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Category Filter Tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCategory = cat;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      cat == 'All' ? 'All (${_allModules.length})' : cat,
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF475569),
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Grid of Root Modules
        LayoutBuilder(
          builder: (context, constraints) {
            int crossAxisCount = 2;
            if (constraints.maxWidth > 900) {
              crossAxisCount = 4;
            } else if (constraints.maxWidth > 600) {
              crossAxisCount = 3;
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: modules.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: isDesktop ? 1.45 : 1.25,
              ),
              itemBuilder: (context, index) {
                final item = modules[index];
                return _buildModuleCard(item);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildModuleCard(ReportModule item) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: () => _navigateTo(context, item.page),
        borderRadius: BorderRadius.circular(18),
        splashColor: item.primaryColor.withOpacity(0.08),
        highlightColor: item.primaryColor.withOpacity(0.04),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: item.lightColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      item.icon,
                      color: item.primaryColor,
                      size: 22,
                    ),
                  ),
                  if (item.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.primaryColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: Colors.grey[400],
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClosingSettlementCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.point_of_sale_rounded, color: Color(0xFF059669), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Closing Settlement (Today)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => _navigateTo(context, const ClosingEntryReportPage()),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View Details →',
                  style: TextStyle(
                    color: Color(0xFF0B355B),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricMiniCard(
                  label: 'Closed Sales',
                  value: totalClosingSales,
                  color: const Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricMiniCard(
                  label: 'Closed Exp.',
                  value: totalClosingExpenses,
                  color: const Color(0xFFEA580C),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricMiniCard(
                  label: 'Net Settled',
                  value: totalClosingNet,
                  color: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricMiniCard({
    required String label,
    required double value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${_formatCurrency(value)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBranchesCard() {
    final topList = branchSummaries.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.leaderboard_rounded, color: Color(0xFFD97706), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Top Performing Outlets',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => _navigateTo(context, const BranchwiseBillsPage()),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'All Outlets →',
                  style: TextStyle(
                    color: Color(0xFF0B355B),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...topList.asMap().entries.map((entry) {
            final idx = entry.key;
            final branch = entry.value;
            final double amount = (branch['total'] ?? 0.0) as double;
            final int bills = (branch['bills'] ?? 0) as int;
            final double percentage = grandTotal > 0 ? (amount / grandTotal).clamp(0.0, 1.0) : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: idx == 0
                                  ? const Color(0xFFFEF3C7)
                                  : idx == 1
                                      ? const Color(0xFFF1F5F9)
                                      : const Color(0xFFFFF7ED),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: idx == 0
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            (branch['branch'] ?? 'Unknown').toString().toUpperCase(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${_formatCurrency(amount)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            '$bills Bills (${(percentage * 100).toStringAsFixed(1)}%)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        idx == 0 ? const Color(0xFF0B355B) : const Color(0xFF38BDF8),
                      ),
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
