import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'widgets/app_drawer.dart';

class WaiterwiseReportPage extends StatefulWidget {
  final bool isEmbedded;
  const WaiterwiseReportPage({super.key, this.isEmbedded = false});
  @override
  State<WaiterwiseReportPage> createState() => _WaiterwiseReportPageState();
}

class _WaiterwiseReportPageState extends State<WaiterwiseReportPage> {
  bool _initialLoading = true;
  bool _loadingBranches = true;
  bool _loadingWaiters = true;
  DateTime? fromDate;
  DateTime? toDate;
  List<Map<String, String>> branches = [];
  String selectedBranchId = 'ALL';
  List<Map<String, dynamic>> waiters = []; // registered waiters list {id, name}
  String selectedWaiterId = 'ALL';
  // summary per waiter: list of maps { waiterId, waiterName, total, bills, cash, upi, card, avg }
  List<Map<String, dynamic>> waiterSummaries = [];
  // previous totals for tween animation keyed by waiterId
  final Map<String, double> _previousTotals = {};
  // which waiter id was just updated (highlight)
  String? _justUpdatedWaiterId;
  // grand totals
  double grandTotal = 0.0;
  int grandBills = 0;
  // to detect new bills (smart refresh)
  String? _latestBillId;
  Timer? _smartTimer;
  bool _isSmartRefreshInProgress = false;

  @override
  void initState() {
    super.initState();
    fromDate = DateTime.now();
    _bootstrap();
  }

  @override
  void dispose() {
    _smartTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _fetchBranches();
    await _fetchWaiters(); // populate waiter filter list
    await _fetchAndGroup(initial: true);
    // start smart live refresh
    _startSmartRefresh();
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
        Uri.parse('https://blackforest.vseyal.com/api/branches?limit=3000'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        final list = <Map<String, String>>[
          {'id': 'ALL', 'name': 'All Branches'},
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

  Future<void> _fetchWaiters() async {
    setState(() => _loadingWaiters = true);
    try {
      final token = await _getToken();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('https://blackforest.vseyal.com/api/users?limit=3000'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        final list = <Map<String, dynamic>>[
          {'id': 'ALL', 'name': 'All Waiters'},
        ];
        for (var u in docs) {
          final id = (u['id'] ?? u['_id'])?.toString();
          // prefer employee.name if exists
          String name = '';
          if (u['employee'] != null && u['employee']['name'] != null) {
            name = u['employee']['name'].toString();
          } else if (u['email'] != null) {
            name = u['email'].toString();
          }
          if (id != null && name.isNotEmpty) list.add({'id': id, 'name': name});
        }
        setState(() => waiters = list);
      }
    } catch (e) {
      debugPrint('fetchWaiters error: $e');
    } finally {
      setState(() => _loadingWaiters = false);
    }
  }

  // Smart timer that only triggers full fetch when new bill id changes
  void _startSmartRefresh() {
    _smartTimer?.cancel();
    _smartTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_isSmartRefreshInProgress) return;
      _isSmartRefreshInProgress = true;
      try {
        final newId = await _checkLatestBillId();
        if (newId != null && newId != _latestBillId) {
          _latestBillId = newId;
          // update (smart) - this function will only mutate changed rows
          await _fetchAndGroup();
        }
      } catch (e) {
        debugPrint('smart refresh error: $e');
      } finally {
        _isSmartRefreshInProgress = false;
      }
    });
  }

  Future<String?> _checkLatestBillId() async {
    try {
      final token = await _getToken();
      if (token == null || fromDate == null) return null;
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
      var url =
          'https://blackforest.vseyal.com/api/billings?limit=1&sort=-createdAt&where[createdAt][greater_than]=${start.toUtc().toIso8601String()}&where[createdAt][less_than]=${end.toUtc().toIso8601String()}&where[status][in][0]=completed&where[status][in][1]=settled';
      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }
      final res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        if (docs.isNotEmpty) {
          final bill = docs.first;
          final id = bill['id'] ?? bill['_id'] ?? (bill['_id']?['\$oid']);
          return id?.toString();
        }
      }
    } catch (e) {
      debugPrint('checkLatestBillId error: $e');
    }
    return null;
  }

  // Main fetch & grouping function — groups bills by waiter (createdBy)
  // When initial==true we populate the whole list and set initial loading.
  // On subsequent calls we only update changed rows to avoid blinking.
  Future<void> _fetchAndGroup({bool initial = false}) async {
    if (fromDate == null) return;
    if (initial) {
      setState(() => _initialLoading = true);
    }
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
      var baseUrl =
          'https://blackforest.vseyal.com/api/billings?limit=0&where[status][in][0]=completed&where[status][in][1]=settled&where[createdAt][greater_than]=${start.toUtc().toIso8601String()}&where[createdAt][less_than]=${end.toUtc().toIso8601String()}&sort=createdAt';
      if (selectedBranchId != 'ALL') {
        baseUrl += '&where[branch][equals]=$selectedBranchId';
      }
      List<dynamic> allDocs = [];
      int page = 1;
      while (true) {
        final url = '$baseUrl&page=$page';
        final res = await http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode != 200) {
          debugPrint('billings fetch failed: ${res.statusCode}');
          break;
        }
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        if (docs.isEmpty) break;
        allDocs.addAll(docs);
        if (!(data['hasNextPage'] ?? false)) break;
        page++;
      }
      // Group by waiter id (createdBy) — handle createdBy being string or map
      final Map<String, Map<String, dynamic>> map = {};
      double totalSum = 0.0;
      int totalBills = 0;
      for (var bill in allDocs) {
        final status = (bill['status'] ?? '').toString().toLowerCase().trim();
        if (status != 'completed' && status != 'settled') continue;

        // find waiter id & name
        String waiterId = 'UNKNOWN';
        String waiterName = 'Unknown';
        final createdBy = bill['createdBy'];
        if (createdBy != null) {
          if (createdBy is Map) {
            final id =
                createdBy['id'] ??
                createdBy['_id'] ??
                (createdBy['_id']?['\$oid']);
            if (id != null) waiterId = id.toString();
            // prefer employee.name
            if (createdBy['employee'] != null &&
                createdBy['employee']['name'] != null) {
              waiterName = createdBy['employee']['name'].toString();
            } else if (createdBy['email'] != null) {
              waiterName = createdBy['email'].toString();
            }
          } else if (createdBy is String) {
            waiterId = createdBy;
            // try match from waiters list
            final match = waiters.firstWhere(
              (w) => w['id'] == waiterId,
              orElse: () => {},
            );
            if (match.isNotEmpty) waiterName = match['name']!;
          }
        }
        final amount = _extractAmount(bill);
        final pm = (bill['paymentMethod'] ?? '').toString().toLowerCase();
        map.putIfAbsent(waiterId, () {
          return {
            'waiterId': waiterId,
            'waiterName': waiterName,
            'total': 0.0,
            'bills': 0,
            'cash': 0.0,
            'upi': 0.0,
            'card': 0.0,
            'avg': 0.0,
          };
        });
        final entry = map[waiterId]!;
        entry['total'] = (entry['total'] as double) + amount;
        entry['bills'] = (entry['bills'] as int) + 1;
        if (pm.contains('cash'))
          entry['cash'] = (entry['cash'] as double) + amount;
        if (pm.contains('upi'))
          entry['upi'] = (entry['upi'] as double) + amount;
        if (pm.contains('card'))
          entry['card'] = (entry['card'] as double) + amount;
        totalSum += amount;
        totalBills++;
      }
      // Convert to list and sort by total descending
      final List<Map<String, dynamic>> rows = map.values.map((e) {
        final bills = e['bills'] as int;
        final amt = e['total'] as double;
        final avg = bills > 0 ? (amt / bills) : 0.0;
        return {
          'waiterId': e['waiterId'],
          'waiterName': e['waiterName'],
          'total': amt,
          'bills': bills,
          'cash': e['cash'],
          'upi': e['upi'],
          'card': e['card'],
          'avg': avg,
        };
      }).toList();
      // Optionally filter to a particular waiter
      List<Map<String, dynamic>> filteredRows = rows;
      if (selectedWaiterId != 'ALL') {
        filteredRows = rows
            .where((r) => r['waiterId'] == selectedWaiterId)
            .toList();
      }
      // sort by total descending so top performers show first
      filteredRows.sort(
        (a, b) => (b['total'] as double).compareTo(a['total'] as double),
      );

      final previousById = <String, Map<String, dynamic>>{};
      for (final row in waiterSummaries) {
        final id = row['waiterId']?.toString();
        if (id != null && id.isNotEmpty) {
          previousById[id] = row;
        }
      }

      String? updatedWaiterId;
      for (final row in filteredRows) {
        final id = row['waiterId']?.toString();
        if (id == null || id.isEmpty) continue;
        final prev = previousById[id];
        final currentTotal = (row['total'] ?? 0.0) as double;
        final currentBills = (row['bills'] ?? 0) as int;
        if (prev != null) {
          final prevTotal = (prev['total'] ?? 0.0) as double;
          final prevBills = (prev['bills'] ?? 0) as int;
          if (updatedWaiterId == null &&
              (prevTotal != currentTotal || prevBills != currentBills)) {
            updatedWaiterId = id;
          }
          _previousTotals.putIfAbsent(id, () => prevTotal);
        }
      }

      final nextPreviousTotals = <String, double>{};
      for (final row in filteredRows) {
        final id = row['waiterId']?.toString();
        if (id == null || id.isEmpty) continue;
        final currentTotal = (row['total'] ?? 0.0) as double;
        nextPreviousTotals[id] = _previousTotals[id] ?? currentTotal;
      }

      String? latestId;
      if (allDocs.isNotEmpty) {
        final latest = allDocs.last;
        final id = latest['id'] ?? latest['_id'] ?? (latest['_id']?['\$oid']);
        latestId = id?.toString();
      }

      if (!mounted) return;
      setState(() {
        waiterSummaries = filteredRows;
        grandTotal = totalSum;
        grandBills = totalBills;
        _previousTotals
          ..clear()
          ..addAll(nextPreviousTotals);
        if (latestId != null) {
          _latestBillId = latestId;
        }
        _justUpdatedWaiterId = updatedWaiterId;
        _initialLoading = false;
      });

      if (updatedWaiterId != null) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted && _justUpdatedWaiterId == updatedWaiterId) {
            setState(() => _justUpdatedWaiterId = null);
          }
        });
      }
    } catch (e) {
      debugPrint('fetchAndGroup error: $e');
    } finally {
      if (initial && mounted && _initialLoading) {
        setState(() => _initialLoading = false);
      }
    }
  }

  double _extractAmount(dynamic bill) {
    if (bill == null) return 0.0;
    final keys = ['total', 'totalAmount', 'grandTotal', 'amount'];
    for (var k in keys) {
      if (bill[k] != null) {
        final v = bill[k];
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
      }
    }
    return 0.0;
  }

  Future<List<Map<String, dynamic>>> _fetchWaiterBranchSummaries(
    String waiterId,
  ) async {
    try {
      final token = await _getToken();
      if (token == null) return [];
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
      var baseUrl =
          'https://blackforest.vseyal.com/api/billings?limit=0&where[status][in][0]=completed&where[status][in][1]=settled&where[createdAt][greater_than]=${start.toUtc().toIso8601String()}&where[createdAt][less_than]=${end.toUtc().toIso8601String()}&where[createdBy][equals]=$waiterId&sort=createdAt';
      if (selectedBranchId != 'ALL') {
        baseUrl += '&where[branch][equals]=$selectedBranchId';
      }
      List<dynamic> allDocs = [];
      int page = 1;
      while (true) {
        final url = '$baseUrl&page=$page';
        final res = await http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode != 200) {
          debugPrint('billings fetch failed: ${res.statusCode}');
          break;
        }
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        if (docs.isEmpty) break;
        allDocs.addAll(docs);
        if (!(data['hasNextPage'] ?? false)) break;
        page++;
      }
      // Group by branch
      final Map<String, Map<String, dynamic>> map = {};
      for (var bill in allDocs) {
        final status = (bill['status'] ?? '').toString().toLowerCase().trim();
        if (status != 'completed' && status != 'settled') continue;

        String branchId = 'UNKNOWN';
        String branchName = 'Unknown';
        final branch = bill['branch'];
        if (branch != null) {
          if (branch is Map) {
            final id =
                branch['id'] ?? branch['_id'] ?? (branch['_id']?['\$oid']);
            if (id != null) branchId = id.toString();
            branchName = (branch['name'] ?? 'Unknown').toString();
          } else if (branch is String) {
            branchId = branch;
            // try match from branches list
            final match = branches.firstWhere(
              (b) => b['id'] == branchId,
              orElse: () => {'name': 'Unknown'},
            );
            branchName = match['name']!;
          }
        }
        final amount = _extractAmount(bill);
        map.putIfAbsent(branchId, () {
          return {
            'branchId': branchId,
            'branchName': branchName,
            'total': 0.0,
            'bills': 0,
          };
        });
        final entry = map[branchId]!;
        entry['total'] = (entry['total'] as double) + amount;
        entry['bills'] = (entry['bills'] as int) + 1;
      }
      // Convert to list and sort by total descending
      final List<Map<String, dynamic>> rows = map.values.toList();
      rows.sort(
        (a, b) => (b['total'] as double).compareTo(a['total'] as double),
      );
      return rows;
    } catch (e) {
      debugPrint('_fetchWaiterBranchSummaries error: $e');
      return [];
    }
  }

  void _showWaiterDetails(String waiterId, String waiterName) {
    final safeFrom = fromDate ?? DateTime.now();
    final dateFmt = DateFormat('MMM d');
    final dateLabel = toDate == null
        ? dateFmt.format(safeFrom)
        : '${dateFmt.format(safeFrom)} - ${dateFmt.format(toDate!)}';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.all(16),
        content: SizedBox(
          width: 300,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchWaiterBranchSummaries(waiterId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 300,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError ||
                  !snapshot.hasData ||
                  snapshot.data!.isEmpty) {
                return const SizedBox(
                  height: 300,
                  child: Center(child: Text('No data available')),
                );
              }
              final branchesData = snapshot.data!;
              double grandTotal = 0.0;
              int grandBills = 0;
              for (var b in branchesData) {
                grandTotal += b['total'] as double;
                grandBills += b['bills'] as int;
              }
              return SizedBox(
                height: 300,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Text(
                          'Waiter: $waiterName',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Center(child: Text('Date: $dateLabel')),
                      const Divider(),
                      ...branchesData.map((b) {
                        final branchName = b['branchName'] as String;
                        final total = b['total'] as double;
                        final bills = b['bills'] as int;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Branch: $branchName'),
                            Text('Bills: $bills'),
                            Text('Total: ₹${total.toStringAsFixed(2)}'),
                            const Divider(),
                          ],
                        );
                      }),
                      Text('Grand Bills: $grandBills'),
                      Text('Grand Total: ₹${grandTotal.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // UI helpers
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
      await _fetchAndGroup(initial: false);
    }
  }

  Future<void> _onRefreshPressed() async {
    // reset to today by user's request
    setState(() {
      fromDate = DateTime.now();
      toDate = null;
      selectedWaiterId = 'ALL';
      selectedBranchId = 'ALL';
    });
    await _fetchAndGroup(initial: false);
  }

  Widget _buildDateSelector() {
    final safeFrom = fromDate ?? DateTime.now();
    final dateFmt = DateFormat('MMM d'); // e.g., Nov 14
    final label = toDate == null
        ? dateFmt.format(safeFrom)
        : '${dateFmt.format(safeFrom)} - ${dateFmt.format(toDate!)}';
    return InkWell(
      onTap: _pickDateRange,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaiterFilter() {
    return _loadingWaiters
        ? const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator()),
          )
        : DropdownButtonFormField<String>(
            value: selectedWaiterId,
            items: waiters
                .map(
                  (w) => DropdownMenuItem<String>(
                    value: w['id'],
                    child: Text(
                      w['name'] ?? 'Unnamed',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) async {
              if (v == null) return;
              setState(() {
                selectedWaiterId = v;
              });
              await _fetchAndGroup();
            },
            decoration: InputDecoration(
              labelText: 'Waiter',
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          );
  }

  Widget _buildBranchFilter() {
    return _loadingBranches
        ? const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator()),
          )
        : DropdownButtonFormField<String>(
            value: selectedBranchId,
            items: branches
                .map(
                  (b) => DropdownMenuItem<String>(
                    value: b['id'],
                    child: Text(
                      b['name'] ?? 'Unnamed',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) async {
              if (v == null) return;
              setState(() {
                selectedBranchId = v;
              });
              await _fetchAndGroup();
            },
            decoration: InputDecoration(
              labelText: 'Branch',
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          );
  }

  Widget _buildRow(int index) {
    final r = waiterSummaries[index];
    final waiterId = r['waiterId'].toString();
    final waiterName = r['waiterName']?.toString() ?? 'Unknown';
    final total = (r['total'] ?? 0.0) as double;
    final bills = (r['bills'] ?? 0) as int;
    final cash = (r['cash'] ?? 0.0) as double;
    final upi = (r['upi'] ?? 0.0) as double;
    final card = (r['card'] ?? 0.0) as double;
    final avg = (r['avg'] ?? 0.0) as double;
    final bg = index % 2 == 0 ? Colors.white : Colors.grey.shade50;
    final highlight = waiterId == _justUpdatedWaiterId
        ? Colors.green.withOpacity(0.08)
        : bg;
    return InkWell(
      onTap: () => _showWaiterDetails(waiterId, waiterName),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: highlight,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // first row: waiter name (left), bills chip (left), amount (right)
            Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          waiterName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$bills bills',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // amount - fixed width to align vertically
                SizedBox(
                  width: 140,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: _previousTotals[waiterId] ?? total,
                        end: total,
                      ),
                      duration: const Duration(milliseconds: 700),
                      builder: (context, val, _) {
                        return Text(
                          '₹${val.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        );
                      },
                      onEnd: () {
                        _previousTotals[waiterId] = total;
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // second row: payment breakdown + avg
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.money,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '₹${cash.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.qr_code,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '₹${upi.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.credit_card,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '₹${card.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  'Avg ₹${avg.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Text(
            'Total Bills: $grandBills',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Text(
            '₹${grandTotal.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    final safeFrom = fromDate ?? DateTime.now();
    final dateFmt = DateFormat('MMM d'); // e.g., Nov 14
    final dateLabel = toDate == null
        ? dateFmt.format(safeFrom)
        : '${dateFmt.format(safeFrom)} - ${dateFmt.format(toDate!)}';

    Widget mainContent = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Row 1: compact calendar (left) and refresh already in appbar; kept simple
          Align(alignment: Alignment.centerLeft, child: _buildDateSelector()),
          const SizedBox(height: 12),
          // Row 2: waiter filter (full width)
          Row(children: [Expanded(child: _buildWaiterFilter())]),
          const SizedBox(height: 12),
          // Row 3: branch filter (full width)
          Row(children: [Expanded(child: _buildBranchFilter())]),
          const SizedBox(height: 12),
          // List
          Expanded(
            child: _initialLoading
                ? const Center(child: CircularProgressIndicator())
                : waiterSummaries.isEmpty
                ? const Center(child: Text('No data for selected range'))
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: waiterSummaries.length,
                    itemBuilder: (context, index) => _buildRow(index),
                  ),
          ),
          const SizedBox(height: 12),
          // Footer summary
          _buildFooter(),
        ],
      ),
    );

    if (widget.isEmbedded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Waiter-wise Report'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              tooltip: 'Refresh (reset to today)',
              onPressed: _onRefreshPressed,
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
          ],
        ),
        body: mainContent,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Waiter-wise Report'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh (reset to today)',
            onPressed: _onRefreshPressed,
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
