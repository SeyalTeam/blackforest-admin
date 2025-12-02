import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TimewiseReportPage extends StatefulWidget {
  const TimewiseReportPage({super.key});
  @override
  State<TimewiseReportPage> createState() => _TimewiseReportPageState();
}

class _TimewiseReportPageState extends State<TimewiseReportPage> {
  bool _loading = true;
  bool _loadingBranches = true;
  bool _loadingUsers = true;
  DateTime? fromDate;
  DateTime? toDate;
  List<Map<String, String>> branches = [];
  String selectedBranchId = 'ALL';
  List<Map<String, String>> employees = [];
  String selectedEmployeeId = 'ALL';
  // grouped data: list of maps { hour: int, time: '6 - 7 AM', amount: double, bills: int, cash: double, upi: double, card: double, avg: double }
  List<Map<String, dynamic>> timeSummaries = [];
  List<dynamic> _allBills = [];
  double grandTotal = 0.0;
  int grandBills = 0;
  double grandCash = 0.0;
  double grandUpi = 0.0;
  double grandCard = 0.0;
  double _previousGrandTotal = 0.0;
  int _previousGrandBills = 0;
  String _lastUpdatedTime = '';
  String? _peakTimeLabel; // for highlight
  final Map<String, double> _previousAmounts = {}; // for tween comparison (keeps per-hour previous amount if needed)
  Timer? _smartTimer;
  String? _latestBillIdChecked; // ID used to detect new bills

  @override
  void initState() {
    super.initState();
    fromDate = DateTime.now();
    _previousGrandTotal = 0.0;
    _previousGrandBills = 0;
    Future.wait([_fetchBranches(), _fetchUsers()]).then((_) => _fetchAndGroup());
    // start smart live refresh
    _startSmartLiveRefresh();
  }

  @override
  void dispose() {
    _smartTimer?.cancel();
    super.dispose();
  }

  void _startSmartLiveRefresh() {
    // Check for a new bill periodically (keeps light requests, only fetching 'latest' lightweight)
    _smartTimer?.cancel();
    _smartTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      await _checkLatestBillAndApply();
    });
  }

  Future<void> _checkLatestBillAndApply() async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token == null || fromDate == null) return;
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59) : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);
      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();
      String url = 'https://admin.theblackforestcakes.com/api/billings?limit=1&sort=-createdAt&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr';
      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }
      if (selectedEmployeeId != 'ALL') {
        url += '&where[createdBy][equals]=$selectedEmployeeId';
      }
      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final docs = data['docs'] ?? [];
      if (docs.isEmpty) return;
      final latest = docs.first;
      final id = (latest['id'] ?? latest['_id'])?.toString();
      if (id == null) return;
      if (_latestBillIdChecked == null) {
        // first time set baseline
        _latestBillIdChecked = id;
        return;
      }
      if (id != _latestBillIdChecked) {
        // New bill detected -> fetch the single bill details and update totals + current hour row
        _latestBillIdChecked = id;
        await _applySingleBillToSummary(latest);
        setState(() {
          _lastUpdatedTime = DateFormat('hh:mm:ss a').format(DateTime.now());
        });
      }
    } catch (e) {
      debugPrint('Smart check error: $e');
    }
  }

  Future<void> _applySingleBillToSummary(dynamic bill) async {
    try {
      // Check if matches employee filter
      if (selectedEmployeeId != 'ALL') {
        final createdBy = bill['createdBy'];
        String idStr = '';
        if (createdBy is String) {
          idStr = createdBy;
        } else if (createdBy is Map) {
          idStr = (createdBy['id'] ?? createdBy['_id'])?.toString() ?? '';
        }
        if (idStr != selectedEmployeeId) return; // skip
      }
      _allBills.add(bill);
      // Extract amount and hour
      final amt = _extractAmount(bill);
      final created = _parseCreatedAt(bill);
      if (amt == 0 || created == null) {
        // still update totals to be safe by recalculating
        await _fetchTotalsAndUpdate();
        return;
      }
      final local = created.toLocal();
      final hour = local.hour;
      final pm = (bill['paymentMethod'] ?? '').toString().toLowerCase();
      // Update grand totals with animation (we'll change state so Animated widgets animate)
      setState(() {
        grandTotal += amt;
        grandBills += 1;
        if (pm.contains('cash')) grandCash += amt;
        if (pm.contains('upi')) grandUpi += amt;
        if (pm.contains('card')) grandCard += amt;
      });
      // Find hour entry in timeSummaries
      final idx = timeSummaries.indexWhere((e) => (e['hour'] ?? -1) == hour);
      if (idx != -1) {
        // Update this entry silently (no animation) by mutating its values
        final entry = timeSummaries[idx];
        entry['amount'] = (entry['amount'] as double) + amt;
        entry['bills'] = (entry['bills'] as int) + 1;
        entry['cash'] = (entry['cash'] as double) + (pm.contains('cash') ? amt : 0.0);
        entry['upi'] = (entry['upi'] as double) + (pm.contains('upi') ? amt : 0.0);
        entry['card'] = (entry['card'] as double) + (pm.contains('card') ? amt : 0.0);
        entry['avg'] = (entry['bills'] > 0) ? (entry['amount'] / entry['bills']) : 0.0;
        // ensure previous amounts tracking for any future animation needs
        _previousAmounts[entry['time'] as String] = entry['amount'] as double;
        // Force rebuild to show updated numbers (row will update but without big animations)
        setState(() {});
      } else {
        // Hour missing: insert a new hour row in descending order
        final label = _hourLabel(hour);
        final newRow = {
          'hour': hour,
          'time': label,
          'amount': amt,
          'bills': 1,
          'cash': pm.contains('cash') ? amt : 0.0,
          'upi': pm.contains('upi') ? amt : 0.0,
          'card': pm.contains('card') ? amt : 0.0,
          'avg': amt,
        };
        // insert in correct position (descending hour order)
        final insertIndex = timeSummaries.indexWhere((r) => (r['hour'] as int) < hour);
        if (insertIndex == -1) {
          timeSummaries.add(newRow);
        } else {
          timeSummaries.insert(insertIndex, newRow);
        }
        // keep previous amounts map
        _previousAmounts[label] = newRow['amount'] as double;
        setState(() {});
      }
      // Optionally re-calc peak hour (silent)
      _recalcPeakSilent();
    } catch (e) {
      debugPrint('applySingleBill error: $e');
    }
  }

  Future<void> _fetchTotalsAndUpdate() async {
    try {
      if (fromDate == null) return;
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token == null) return;
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59) : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);
      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();
      String url = 'https://admin.theblackforestcakes.com/api/billings?limit=0&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr';
      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }
      if (selectedEmployeeId != 'ALL') {
        url += '&where[createdBy][equals]=$selectedEmployeeId';
      }
      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final docs = data['docs'] ?? [];
      double sum = 0.0;
      int bills = 0;
      double cash = 0.0;
      double upi = 0.0;
      double card = 0.0;
      for (var b in docs) {
        final amt = _extractAmount(b);
        sum += amt;
        bills++;
        final pm = (b['paymentMethod'] ?? '').toString().toLowerCase();
        if (pm.contains('cash')) cash += amt;
        if (pm.contains('upi')) upi += amt;
        if (pm.contains('card')) card += amt;
      }
      setState(() {
        grandTotal = sum;
        grandBills = bills;
        grandCash = cash;
        grandUpi = upi;
        grandCard = card;
      });
    } catch (e) {
      debugPrint('fetchTotalsAndUpdate error: $e');
    }
  }

  void _recalcPeakSilent() {
    if (timeSummaries.isEmpty) {
      _peakTimeLabel = null;
      return;
    }
    final peak = timeSummaries.reduce((a, b) => (a['amount'] as double) >= (b['amount'] as double) ? a : b);
    _peakTimeLabel = peak['time'] as String;
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
        final docs = data['docs'] ?? [];
        final list = <Map<String, String>>[{'id': 'ALL', 'name': 'All Branches'}];
        for (var b in docs) {
          final id = (b['id'] ?? b['_id'])?.toString();
          final name = (b['name'] ?? 'Unnamed Branch').toString();
          if (id != null) list.add({'id': id, 'name': name});
        }
        setState(() => branches = list);
      }
    } catch (e) {
      debugPrint('fetch branches error: $e');
    } finally {
      setState(() => _loadingBranches = false);
    }
  }

  Future<void> _fetchUsers() async {
    setState(() => _loadingUsers = true);
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
        final docs = data['docs'] ?? [];
        final list = <Map<String, String>>[{'id': 'ALL', 'name': 'All Waiters'}];
        for (var u in docs) {
          final id = (u['id'] ?? u['_id'])?.toString();
          String name = '';
          if (u['employee'] != null && u['employee']['name'] != null) {
            name = u['employee']['name'].toString();
          } else if (u['email'] != null) {
            name = u['email'].toString();
          }
          if (id != null && name.isNotEmpty) list.add({'id': id, 'name': name});
        }
        setState(() => employees = list);
      }
    } catch (e) {
      debugPrint('fetch users error: $e');
    } finally {
      setState(() => _loadingUsers = false);
    }
  }

  Future<void> _pickRangeAndRefresh() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: fromDate != null && toDate != null ? DateTimeRange(start: fromDate!, end: toDate!) : DateTimeRange(start: now, end: now),
    );
    if (picked != null) {
      setState(() {
        fromDate = picked.start;
        toDate = picked.end;
      });
      await _fetchAndGroup();
    }
  }

  Future<void> _fetchAndGroup() async {
    if (fromDate == null) return;
    setState(() {
      _loading = true;
    });
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token == null) return;
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59) : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);
      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();
      var url = 'https://admin.theblackforestcakes.com/api/billings?limit=0&where[createdAt][greater_than]=$startStr&where[createdAt][less_than]=$endStr&sort=createdAt';
      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }
      if (selectedEmployeeId != 'ALL') {
        url += '&where[createdBy][equals]=$selectedEmployeeId';
      }
      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      List docs = [];
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        docs = data['docs'] ?? [];
      } else {
        debugPrint('billings fetch failed: ${res.statusCode}');
      }
      _allBills = docs;
      // group by hour slots based on createdAt (local time)
      final Map<int, Map<String, dynamic>> grouping = {};
      double totalSum = 0.0;
      int totalBills = 0;
      double cash = 0.0;
      double upi = 0.0;
      double card = 0.0;
      for (var bill in docs) {
        final createdAtRaw = bill['createdAt'] ?? bill['created_at'];
        DateTime? dt = _parseCreatedAtRaw(createdAtRaw);
        if (dt == null) continue;
        final local = dt.toLocal();
        final hour = local.hour; // 0..23
        final amount = _extractAmount(bill);
        final pm = (bill['paymentMethod'] ?? '').toString().toLowerCase();
        grouping.putIfAbsent(hour, () {
          return {
            'hour': hour,
            'amount': 0.0,
            'bills': 0,
            'cash': 0.0,
            'upi': 0.0,
            'card': 0.0,
          };
        });
        final entry = grouping[hour]!;
        entry['amount'] = (entry['amount'] as double) + amount;
        entry['bills'] = (entry['bills'] as int) + 1;
        if (pm.contains('cash')) {
          entry['cash'] = (entry['cash'] as double) + amount;
          cash += amount;
        }
        if (pm.contains('upi')) {
          entry['upi'] = (entry['upi'] as double) + amount;
          upi += amount;
        }
        if (pm.contains('card')) {
          entry['card'] = (entry['card'] as double) + amount;
          card += amount;
        }
        totalSum += amount;
        totalBills++;
      }
      // convert grouping map -> list and sort by hour descending (latest first)
      final List<Map<String, dynamic>> rows = grouping.values.map((e) {
        final bills = e['bills'] as int;
        final amt = e['amount'] as double;
        final avg = bills > 0 ? (amt / bills) : 0.0;
        final hour = e['hour'] as int;
        return {
          'hour': hour,
          'time': _hourLabel(hour),
          'amount': amt,
          'bills': bills,
          'cash': e['cash'],
          'upi': e['upi'],
          'card': e['card'],
          'avg': avg,
        };
      }).toList();
      rows.sort((a, b) => (b['hour'] as int).compareTo(a['hour'] as int));
      // determine peak hour (largest amount)
      String? peak;
      if (rows.isNotEmpty) {
        final sortedByAmt = List.from(rows);
        sortedByAmt.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
        peak = sortedByAmt.first['time'] as String;
      }
      // store previous amounts for animation references (if needed)
      for (var r in rows) {
        final t = r['time'] as String;
        _previousAmounts.putIfAbsent(t, () => r['amount'] as double);
      }
      // set latestBill baseline (fetch the latest id so smart refresh compares correctly)
      String? latestId;
      if (docs.isNotEmpty) {
        // docs sorted by createdAt ascending due to sort=createdAt; but we want latest -> use last
        final latestDoc = docs.last;
        latestId = (latestDoc['id'] ?? latestDoc['_id'])?.toString();
      }
      setState(() {
        timeSummaries = rows;
        grandTotal = totalSum;
        grandBills = totalBills;
        grandCash = cash;
        grandUpi = upi;
        grandCard = card;
        _peakTimeLabel = peak;
        _latestBillIdChecked = latestId;
        _lastUpdatedTime = DateFormat('hh:mm:ss a').format(DateTime.now());
      });
      // After a microtask update, allow previous amounts map to update to new values
      Future.microtask(() {
        for (var r in rows) {
          final t = r['time'] as String;
          _previousAmounts[t] = r['amount'] as double;
        }
      });
    } catch (e) {
      debugPrint('fetchAndGroup error: $e');
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  DateTime? _parseCreatedAt(dynamic bill) {
    final createdAtRaw = bill['createdAt'] ?? bill['created_at'];
    return _parseCreatedAtRaw(createdAtRaw);
  }

  DateTime? _parseCreatedAtRaw(dynamic createdAtRaw) {
    if (createdAtRaw == null) return null;
    try {
      if (createdAtRaw is String) {
        return DateTime.tryParse(createdAtRaw);
      }
      if (createdAtRaw is Map) {
        // handle {"$date":"..."} style
        final d = createdAtRaw['\$date'] ?? createdAtRaw['date'] ?? createdAtRaw['\$t'];
        if (d is String) return DateTime.tryParse(d);
        if (d is Map && d['\$date'] != null) return DateTime.tryParse(d['\$date']);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _hourLabel(int hour) {
    // example: 6 -> "6 - 7 AM", 0 -> "12 - 1 AM"
    final start = DateTime(0, 1, 1, hour);
    final end = DateTime(0, 1, 1, (hour + 1) % 24);
    final fmt = DateFormat('h a'); // "6 AM"
    return '${fmt.format(start)} - ${fmt.format(end)}';
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

  Future<void> _showBranchPopup(int hour) async {
    final filteredBills = _allBills.where((b) {
      final dt = _parseCreatedAt(b);
      return dt != null && dt.toLocal().hour == hour;
    }).toList();
    if (filteredBills.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${_hourLabel(hour)}'),
          content: Text('No data'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close'))],
        ),
      );
      return;
    }
    final Map<String, Map<String, dynamic>> branchMap = {};
    double popupTotal = 0.0;
    int popupBills = 0;
    double popupCash = 0.0;
    double popupUpi = 0.0;
    double popupCard = 0.0;
    for (var bill in filteredBills) {
      final branchRaw = bill['branch'];
      String branch = 'Unknown';
      if (branchRaw is Map && branchRaw['name'] != null) {
        branch = branchRaw['name'].toString();
      } else if (branchRaw is String) {
        branch = branchRaw;
      } else if (branchRaw is Map && branchRaw['id'] != null) {
        // Optionally map ID to name from branches list
        final found = branches.firstWhere((br) => br['id'] == branchRaw['id'].toString(), orElse: () => {'name': 'Unknown'});
        branch = found['name'] ?? 'Unknown';
      }
      final amt = _extractAmount(bill);
      final pm = (bill['paymentMethod'] ?? '').toLowerCase();
      branchMap.putIfAbsent(branch, () => {
        'branch': branch,
        'total': 0.0,
        'bills': 0,
        'cash': 0.0,
        'upi': 0.0,
        'card': 0.0,
      });
      final s = branchMap[branch]!;
      s['total'] += amt;
      s['bills'] += 1;
      if (pm.contains('cash')) s['cash'] += amt;
      if (pm.contains('upi')) s['upi'] += amt;
      if (pm.contains('card')) s['card'] += amt;
      popupTotal += amt;
      popupBills += 1;
      if (pm.contains('cash')) popupCash += amt;
      if (pm.contains('upi')) popupUpi += amt;
      if (pm.contains('card')) popupCard += amt;
    }
    final list = branchMap.values.toList()..sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${_hourLabel(hour)}'),
            IconButton(
              icon: Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (c, i) {
              final s = list[i];
              final pct = popupTotal > 0 ? ((s['total'] / popupTotal) * 100).toStringAsFixed(1) : '0.0';
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s['branch'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('₹${(s['total'] as double).toStringAsFixed(2)} ($pct%)', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.money, size: 16, color: Colors.black54),
                          const SizedBox(width: 6),
                          Text('₹${(s['cash'] as double).toStringAsFixed(0)}'),
                          const SizedBox(width: 12),
                          const Icon(Icons.qr_code, size: 16, color: Colors.black54),
                          const SizedBox(width: 6),
                          Text('₹${(s['upi'] as double).toStringAsFixed(0)}'),
                          const SizedBox(width: 12),
                          const Icon(Icons.credit_card, size: 16, color: Colors.black54),
                          const SizedBox(width: 6),
                          Text('₹${(s['card'] as double).toStringAsFixed(0)}'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, Map<String, dynamic> row, bool isPeak, int index) {
    final timeLabel = row['time']?.toString() ?? '';
    final amount = (row['amount'] ?? 0.0) as double;
    final bills = (row['bills'] ?? 0) as int;
    final cash = (row['cash'] ?? 0.0) as double;
    final upi = (row['upi'] ?? 0.0) as double;
    final card = (row['card'] ?? 0.0) as double;
    final avg = (row['avg'] ?? 0.0) as double;
    final bg = index % 2 == 0 ? Colors.white : Colors.grey.shade50;
    final highlight = isPeak ? Colors.amber.withOpacity(0.12) : Colors.transparent;
    return GestureDetector(
      onTap: () => _showBranchPopup(row['hour'] as int),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: highlight == Colors.transparent ? bg : highlight,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [ BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)), ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // First Row: Time + Bills Chip + Aligned Amount
            Row(
              children: [
                // Time and bills chip (left side)
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$bills bills',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Right-aligned fixed-width ₹ total
                SizedBox(
                  width: 140, // a little wider for big amounts
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '₹${amount.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: 'RobotoMono', // monospaced digits
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Second Row: Payment breakdown + average
            Row(
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Icon(Icons.money, size: 16, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text('₹${cash.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                        const SizedBox(width: 12),
                        Icon(Icons.qr_code, size: 16, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text('₹${upi.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                        const SizedBox(width: 12),
                        Icon(Icons.credit_card, size: 16, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text('₹${card.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Avg ₹${avg.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onBranchChanged(String? v) async {
    if (v == null) return;
    setState(() {
      selectedBranchId = v;
      _loading = true;
    });
    await _fetchAndGroup();
  }

  Future<void> _onEmployeeChanged(String? v) async {
    if (v == null) return;
    setState(() {
      selectedEmployeeId = v;
      _loading = true;
    });
    await _fetchAndGroup();
  }

  @override
  Widget build(BuildContext context) {
    final safeFrom = fromDate ?? DateTime.now();
    final dateFmt = DateFormat('MMM d');
    final dateLabel = toDate == null ? '${dateFmt.format(safeFrom)}' : '${dateFmt.format(safeFrom)} - ${dateFmt.format(toDate!)}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time wise Report'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh (today)',
            onPressed: () async {
              setState(() {
                fromDate = DateTime.now();
                toDate = null;
                _loading = true;
              });
              await _fetchAndGroup();
            },
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Date selector
            InkWell(
              onTap: _pickRangeAndRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dateLabel,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Employee filter
            Row(
              children: [
                Expanded(
                  child: _loadingUsers
                      ? const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()))
                      : DropdownButtonFormField<String>(
                    value: selectedEmployeeId,
                    items: employees.map((e) => DropdownMenuItem<String>(
                      value: e['id'],
                      child: Text(e['name'] ?? '', overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: _onEmployeeChanged,
                    decoration: InputDecoration(
                      labelText: 'Waiter',
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Branch filter
            Row(children: [
              Expanded(
                child: _loadingBranches
                    ? const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()))
                    : DropdownButtonFormField<String>(
                  value: selectedBranchId,
                  items: branches.map((b) => DropdownMenuItem<String>(value: b['id'], child: Text(b['name'] ?? 'Unnamed', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: _onBranchChanged,
                  decoration: InputDecoration(
                    labelText: 'Branch',
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : timeSummaries.isEmpty
                  ? const Center(child: Text('No data for selected range'))
                  : ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: timeSummaries.length,
                itemBuilder: (context, index) {
                  final r = timeSummaries[index];
                  final isPeak = (_peakTimeLabel != null && _peakTimeLabel == r['time']);
                  return _buildRow(context, r, isPeak, index);
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
                        Text('Total Bills: $grandBills', style: const TextStyle(color: Colors.white, fontSize: 15)),
                        Text('₹${grandTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 26)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.money, color: Colors.white70, size: 20),
                        const SizedBox(width: 6),
                        Text('₹${grandCash.toStringAsFixed(0)}', style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold)),
                        const SizedBox(width: 14),
                        const Icon(Icons.qr_code, color: Colors.white70, size: 20),
                        const SizedBox(width: 6),
                        Text('₹${grandUpi.toStringAsFixed(0)}', style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold)),
                        const SizedBox(width: 14),
                        const Icon(Icons.credit_card, color: Colors.white70, size: 20),
                        const SizedBox(width: 6),
                        Text('₹${grandCard.toStringAsFixed(0)}', style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_lastUpdatedTime.isNotEmpty) Text('Last updated: $_lastUpdatedTime', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}