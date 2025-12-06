import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'widgets/app_drawer.dart';

class BillsDateTimePage extends StatefulWidget {
  const BillsDateTimePage({super.key});

  @override
  State<BillsDateTimePage> createState() => _BillsDateTimePageState();
}

class _BillsDateTimePageState extends State<BillsDateTimePage> {
  bool _loading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _loadingSummary = true;
  bool _loadingBranches = true;

  List<dynamic> allBills = [];
  Map<String, String> userMap = {};
  Map<String, String> companyMap = {}; // ✅ NEW
  List<Map<String, String>> branches = [];
  String selectedBranchId = 'ALL';
  int _currentPage = 1;
  final int _limit = 25;

  final ScrollController _scrollController = ScrollController();
  Timer? _autoRefreshTimer;

  double overviewAmount = 0.0;
  int overviewBills = 0;
  double cashTotal = 0.0;
  double upiTotal = 0.0;
  double cardTotal = 0.0;

  DateTime? fromDate;
  DateTime? toDate;

  String selectedPaymentMethod = 'ALL';
  String? _latestBillId;

  @override
  void initState() {
    super.initState();
    fromDate = DateTime.now();
    _fetchCompanies().then((_) {
      _fetchBranches().whenComplete(() {
        _fetchUsers().then((_) {
          _fetchBills().then((_) => _fetchOverview());
        });
      });
    });
    _scrollController.addListener(_onScroll);
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkForNewBills();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  // ✅ Fetch company names
  Future<void> _fetchCompanies() async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token == null) return;
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/companies?limit=1000'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        final Map<String, String> temp = {};
        for (var c in docs) {
          final id = c['id'] ?? c['_id'];
          final name = c['name'] ?? 'Unnamed Company';
          if (id != null) temp[id.toString()] = name.toString();
        }
        setState(() => companyMap = temp);
      }
    } catch (e) {
      debugPrint('Error fetching companies: $e');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 150 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreBills();
    }
  }

  Future<void> _loadMoreBills() async {
    await _fetchBills(page: _currentPage + 1);
  }

  Future<void> _clearAllFilters() async {
    setState(() {
      selectedBranchId = 'ALL';
      fromDate = DateTime.now();
      toDate = null;
      selectedPaymentMethod = 'ALL';
      _currentPage = 1;
      allBills = [];
      _hasMore = true;
    });
    await _fetchBills(page: 1);
    await _fetchOverview();
  }

  Future<void> _onBranchChanged(String? newId) async {
    if (newId == null) return;
    setState(() {
      selectedBranchId = newId;
      _hasMore = true;
      _currentPage = 1;
      allBills = [];
    });
    await _fetchBills(page: 1);
    await _fetchOverview();
  }

  Future<void> _fetchBranches() async {
    setState(() => _loadingBranches = true);
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token == null) return;
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/branches?limit=1000'),
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

  Future<void> _fetchUsers() async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token == null) return;
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/users?limit=1000'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List users = data['docs'] ?? [];
        for (var user in users) {
          final id = user['id'] ?? user['_id'];
          final employee = user['employee'];
          String name = '';
          if (employee != null && employee['name'] != null) {
            name = employee['name'].toString().trim();
          } else if (user['email'] != null) {
            name = user['email'].toString().trim();
          }
          if (id != null && name.isNotEmpty) userMap[id.toString()] = name;
        }
      }
    } catch (e) {
      debugPrint('Error fetching users: $e');
    }
  }

  Future<void> _fetchOverview() async {
    if (fromDate == null) return;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token == null) return;
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);

      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();

      String url =
          'https://admin.theblackforestcakes.com/api/billings?limit=1000&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr';

      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }

      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];

        double sum = 0.0;
        double cash = 0.0;
        double upi = 0.0;
        double card = 0.0;

        for (var bill in docs) {
          final amt = _extractAmount(bill);
          sum += amt;

          var pay = (bill['paymentMethod'] ?? '').toString().trim().toLowerCase();
          if (pay.contains('cash')) cash += amt;
          if (pay.contains('upi')) upi += amt;
          if (pay.contains('card')) card += amt;
        }

        setState(() {
          overviewAmount = sum;
          overviewBills = docs.length;
          cashTotal = cash;
          upiTotal = upi;
          cardTotal = card;
        });
      }
    } catch (e) {
      debugPrint('Overview fetch error: $e');
    } finally {
      setState(() => _loadingSummary = false);
    }
  }

  Future<void> _fetchBills({int page = 1}) async {
    if (fromDate == null) return;
    setState(() {
      if (page == 1) _loading = true;
      _isLoadingMore = page > 1;
    });

    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token == null) return;
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);

      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();

      String url =
          'https://admin.theblackforestcakes.com/api/billings?limit=$_limit&page=$page&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr&sort=-createdAt';

      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }

      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];
        if (docs.isEmpty) {
          setState(() => _hasMore = false);
        } else {
          setState(() {
            if (page == 1) {
              allBills = docs;
            } else {
              allBills.addAll(docs);
            }
            _currentPage = page;
            if (allBills.isNotEmpty) {
              final latest = allBills.first;
              final id = latest['id'] ?? latest['_id'];
              _latestBillId = id?.toString();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching bills: $e');
    } finally {
      setState(() {
        _loading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _checkForNewBills() async {
    if (fromDate == null) return;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token == null) return;
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);

      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();

      String url =
          'https://admin.theblackforestcakes.com/api/billings?limit=1&sort=-createdAt&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr';

      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }

      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];
        if (docs.isNotEmpty) {
          final latest = docs.first;
          final id = latest['id'] ?? latest['_id'];
          final idStr = id?.toString();
          if (idStr != null && idStr != _latestBillId) {
            await _fetchBills(page: 1);
            await _fetchOverview();
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking new bills: $e');
    }
  }

  double _extractAmount(dynamic bill) {
    if (bill == null) return 0.0;
    final keys = ['total', 'totalAmount', 'grandTotal', 'amount'];
    for (var k in keys) {
      if (bill[k] != null) {
        final v = bill[k];
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0;
      }
    }
    return 0;
  }

  // ✅ Popup with dynamic company
  void _showBillPopup(Map<String, dynamic> bill) {
    final items = List<Map<String, dynamic>>.from(bill['items'] ?? []);
    final total = _extractAmount(bill);
    final method = (bill['paymentMethod'] ?? 'Unknown').toString().toUpperCase();
    final invoice = bill['invoiceNumber'] ?? 'N/A';
    final branch = bill['branch']?['name'] ?? 'Unknown';

    // ✅ Extract company name (handles all Payload CMS formats)
    String companyName = 'Unknown Company';
    final company = bill['company'];
    if (company != null) {
      if (company is Map) {
        // if expanded with name, use it directly
        if (company['name'] != null) {
          companyName = company['name'].toString();
        } else if (company['id'] != null &&
            companyMap.containsKey(company['id'].toString())) {
          companyName = companyMap[company['id'].toString()]!;
        } else if (company['_id'] != null &&
            companyMap.containsKey(company['_id'].toString())) {
          companyName = companyMap[company['_id'].toString()]!;
        }
      } else if (company is String &&
          companyMap.containsKey(company.toString())) {
        companyName = companyMap[company.toString()]!;
      }
    }

    final waiter = bill['createdBy']?['employee']?['name'] ??
        bill['createdBy']?['email'] ??
        'Unknown';
    final date = DateTime.tryParse(bill['createdAt'] ?? '');

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: Colors.white,
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Text(
                '🧾 $companyName',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              Text(branch, style: const TextStyle(color: Colors.black54)),
              const Divider(),
              Text('Invoice: $invoice'),
              if (date != null)
                Text(DateFormat('MMM d, yyyy - hh:mm a').format(date.toLocal())),
              const Divider(),

              ...items.map((i) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Text(
                        i['name'] ?? '',
                        style: const TextStyle(fontSize: 14),
                      )),
                  Text(
                    '${i['quantity']} x ${i['unitPrice']} = ${i['subtotal']}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              )),

              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Payment'),
                Text(method)
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Waiter'),
                Text(waiter)
              ]),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total Amount',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('₹${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold))
              ]),
              const SizedBox(height: 10),
              const Text('Thank you for visiting!',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const Text('Powered by VSeyal POS',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
            ]),
          ),
        ),
      ),
    );
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
        _currentPage = 1;
        allBills = [];
      });
      await _fetchBills(page: 1);
      await _fetchOverview();
    }
  }

  void _togglePaymentFilter(String m) {
    setState(() {
      selectedPaymentMethod = selectedPaymentMethod == m ? 'ALL' : m;
    });
  }

  List get _displayedBills {
    if (selectedPaymentMethod == 'ALL') return allBills;
    final key = selectedPaymentMethod.toLowerCase();
    return allBills
        .where((b) =>
        (b['paymentMethod'] ?? '').toString().toLowerCase().contains(key))
        .toList();
  }

  Widget _buildPaymentTile(String type, IconData icon, Color color, double value) {
    return GestureDetector(
      onTap: () => _togglePaymentFilter(type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color:
          selectedPaymentMethod == type ? Colors.grey.shade200 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Text(
                '₹${value.toStringAsFixed(0)}',
                key: ValueKey<double>(value),
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
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

    Widget mainContent = _loading && allBills.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: _pickDateRange,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(dateLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _loadingBranches
                  ? const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator()))
                  : DropdownButtonFormField<String>(
                value: selectedBranchId,
                items: branches
                    .map((b) => DropdownMenuItem<String>(
                  value: b['id'],
                  child: Text(b['name'] ?? 'Unnamed',
                      overflow: TextOverflow.ellipsis),
                ))
                    .toList(),
                onChanged: (v) => _onBranchChanged(v),
                decoration: InputDecoration(
                  labelText: 'Branch',
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Card(
            color: Colors.grey[100],  // UPDATED: Changed from pink[50] to grey[100] for consistency with waiter/time wise (light background)
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: _loadingSummary
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Total Bills: ',
                        style: TextStyle(
                            fontWeight: FontWeight.bold)),
                    Text('$overviewBills',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildPaymentTile(
                          'CASH',
                          Icons.money,
                          Colors.green,
                          cashTotal),
                      _buildPaymentTile(
                          'UPI', Icons.qr_code, Colors.blue, upiTotal),
                      _buildPaymentTile(
                          'CARD',
                          Icons.credit_card,
                          Colors.purple,
                          cardTotal),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 14),
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius:
                        BorderRadius.circular(6)),
                    child: Row(
                      mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Amount:',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight:
                                FontWeight.bold)),
                        Text(
                            '₹${overviewAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.green,
                                fontSize: 28,
                                fontWeight:
                                FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _displayedBills.isEmpty
                ? const Center(child: Text('No bills found'))
                : ListView.builder(
              controller: _scrollController,
              itemCount: _displayedBills.length,
              itemBuilder: (context, index) {
                final bill = _displayedBills[index];
                final branch =
                    bill['branch']?['name'] ?? 'Unknown';
                final amount = _extractAmount(bill);
                final paymentMethod =
                (bill['paymentMethod'] ?? 'unknown')
                    .toString();
                String waiterName = 'Unknown';
                final createdBy = bill['createdBy'];
                if (createdBy != null) {
                  if (createdBy is Map) {
                    waiterName = (createdBy['employee']
                    ?['name'] ??
                        createdBy['email'] ??
                        '')
                        .toString()
                        .trim()
                        .isNotEmpty
                        ? (createdBy['employee']?['name'] ??
                        createdBy['email'])
                        : waiterName;
                  } else if (createdBy is String &&
                      userMap.containsKey(createdBy)) {
                    waiterName = userMap[createdBy]!;
                  }
                }

                final createdAt = bill['createdAt'];
                String timeText = '';
                if (createdAt != null) {
                  final dt = DateTime.tryParse(createdAt);
                  if (dt != null) {
                    if (toDate != null) {
                      timeText = DateFormat('dd.MM.yy - hh:mm a')
                          .format(dt.toLocal());
                    } else {
                      timeText = DateFormat('hh:mm a')
                          .format(dt.toLocal());
                    }
                  }
                }

                final bgColor = index % 2 == 0
                    ? Colors.white  // UPDATED: Changed to white / grey.shade50 for consistency with waiter/time wise
                    : Colors.grey.shade50;

                return GestureDetector(
                  onTap: () => _showBillPopup(bill),
                  child: Container(
                    color: bgColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(branch,
                                    style: const TextStyle(
                                        fontWeight:
                                        FontWeight.bold,
                                        color: Colors.black,
                                        fontSize: 15),
                                    overflow:
                                    TextOverflow.ellipsis),
                              ),
                              Text(
                                  '₹${amount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight:
                                      FontWeight.bold,
                                      color: Colors.green,
                                      fontSize: 15)),
                            ]),
                        const SizedBox(height: 4),
                        Text(
                          '$timeText - $waiterName - ${paymentMethod.toUpperCase()}',
                          style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                              fontWeight:
                              FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoadingMore)
            const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator()),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills (Date / Time Filter)'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Clear All Filters',
            onPressed: _clearAllFilters,
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