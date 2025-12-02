import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ExpensewiseReportPage extends StatefulWidget {
  const ExpensewiseReportPage({super.key});

  @override
  State<ExpensewiseReportPage> createState() => _ExpensewiseReportPageState();
}

class _ExpensewiseReportPageState extends State<ExpensewiseReportPage> {
  bool _initialLoading = true;
  bool _loadingBranches = true;
  DateTime? fromDate;
  DateTime? toDate;
  List<Map<String, String>> branches = [];
  String selectedBranchId = 'ALL';
  List<String> sources = [];
  String selectedSource = 'ALL';

  Map<String, List<Map<String, dynamic>>> expenseDetails = {};

  List<dynamic> allExpenses = [];

  String? _latestExpenseId;
  Timer? _smartTimer;

  double grandTotal = 0.0;
  int grandCount = 0;

  final Map<String, GlobalKey> _sourceKeys = {};

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
    await _fetchAndGroup(initial: true);
    _startSmartRefresh();
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

  void _startSmartRefresh() {
    _smartTimer?.cancel();
    _smartTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      try {
        final newId = await _checkLatestExpenseId();
        if (newId != null && newId != _latestExpenseId) {
          _latestExpenseId = newId;
          await _fetchAndGroup();
        }
      } catch (e) {
        debugPrint('smart refresh error: $e');
      }
    });
  }

  Future<String?> _checkLatestExpenseId() async {
    try {
      final token = await _getToken();
      if (fromDate == null) return null;
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);
      var url =
          'https://admin.theblackforestcakes.com/api/expenses?limit=1&sort=-createdAt'
          '&where[createdAt][greater_than]=${start.toUtc().toIso8601String()}'
          '&where[createdAt][less_than]=${end.toUtc().toIso8601String()}';
      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }
      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        if (docs.isNotEmpty) {
          final expense = docs.first;
          final id = expense['id'] ?? expense['_id'] ?? (expense['_id']?['\$oid']);
          return id?.toString();
        }
      }
    } catch (e) {
      debugPrint('checkLatestExpenseId error: $e');
    }
    return null;
  }

  Future<void> _fetchAndGroup({bool initial = false}) async {
    if (fromDate == null) return;
    if (initial) {
      setState(() => _initialLoading = true);
    }
    try {
      final token = await _getToken();
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);

      var baseUrl =
          'https://admin.theblackforestcakes.com/api/expenses?limit=1000&where[createdAt][greater_than]='
          '${start.toUtc().toIso8601String()}&where[createdAt][less_than]='
          '${end.toUtc().toIso8601String()}&sort=createdAt';

      if (selectedBranchId != 'ALL') {
        baseUrl += '&where[branch][equals]=$selectedBranchId';
      }

      List<dynamic> allDocs = [];
      int page = 1;

      while (true) {
        final url = '$baseUrl&page=$page';
        final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
        if (res.statusCode != 200) break;

        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        if (docs.isEmpty) break;

        allDocs.addAll(docs);
        if (!(data['hasNextPage'] ?? false)) break;
        page++;
      }

      allExpenses = allDocs;

      final Set<String> uniqueSources = {};
      final Map<String, List<Map<String, dynamic>>> branchDetails = {};

      for (var expense in allDocs) {
        String branchName = 'Unknown';
        final branch = expense['branch'];

        if (branch != null) {
          if (branch is Map) {
            branchName = (branch['name'] ?? 'Unknown').toString();
          } else if (branch is String) {
            final match = branches.firstWhere(
                  (b) => b['id'] == branch,
              orElse: () => {'name': 'Unknown'},
            );
            branchName = match['name']!;
          }
        }

        DateTime? expDate;
        final dateRaw = expense['createdAt'] ?? expense['date'];

        if (dateRaw != null) {
          if (dateRaw is Map && dateRaw[r'$date'] != null) {
            expDate = DateTime.tryParse(dateRaw[r'$date']);
          } else if (dateRaw is String) {
            expDate = DateTime.tryParse(dateRaw);
          }
        }

        final istDate = expDate != null ? expDate.add(const Duration(hours: 5, minutes: 30)) : null;
        final formattedDate = istDate != null
            ? DateFormat('MMM d, yyyy h:mm a').format(istDate)
            : 'Unknown';

        final details = expense['details'] ?? [];

        for (var detail in details) {
          final source = (detail['source'] ?? 'UNKNOWN').toString();
          uniqueSources.add(source);

          final amount = (detail['amount'] ?? 0.0).toDouble();
          final reason = (detail['reason'] ?? 'No reason').toString();

          branchDetails.putIfAbsent(branchName, () => []);
          branchDetails[branchName]!.add({
            'date': expDate,
            'formattedDate': formattedDate,
            'source': source,
            'reason': reason.toUpperCase(),   // ← FULLY CAPS ADDED HERE
            'amount': amount,
          });
        }
      }

      if (selectedSource != 'ALL') {
        for (var entry in branchDetails.entries.toList()) {
          final filtered = entry.value.where((d) => d['source'] == selectedSource).toList();
          if (filtered.isEmpty) {
            branchDetails.remove(entry.key);
          } else {
            branchDetails[entry.key] = filtered;
          }
        }
      }

      double totalSum = 0.0;
      int totalCount = 0;

      for (var list in branchDetails.values) {
        for (var d in list) {
          totalSum += d['amount'] as double;
          totalCount++;
        }
      }

      List<String> sourceList = ['ALL', ...uniqueSources.toList()..sort()];

      setState(() {
        expenseDetails = branchDetails;
        grandTotal = totalSum;
        grandCount = totalCount;
        sources = sourceList;
      });

      if (allDocs.isNotEmpty) {
        final latest = allDocs.last;
        final id = latest['id'] ?? latest['_id'] ?? (latest['_id']?['\$oid']);
        _latestExpenseId = id?.toString();
      }
    } catch (e) {
      debugPrint('fetchAndGroup error: $e');
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  Future<void> _onSourceChanged(String v) async {
    String oldSource = selectedSource;
    if (selectedSource == v && v != 'ALL') {
      selectedSource = 'ALL';
    } else {
      selectedSource = v;
    }
    setState(() {});
    await _fetchAndGroup();

    if (selectedSource != oldSource) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sourceKeys[selectedSource]?.currentContext != null) {
          Scrollable.ensureVisible(_sourceKeys[selectedSource]!.currentContext!,
              alignment: 0.5, duration: const Duration(milliseconds: 300));
        }
      });
    }
  }

  Widget _buildSourceFilter() {
    return SizedBox(
      height: 32,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: sources.map((s) {
            _sourceKeys.putIfAbsent(s, () => GlobalKey());
            final isSelected = selectedSource == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton(
                key: _sourceKeys[s],
                onPressed: () => _onSourceChanged(s),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected ? Colors.black : Colors.grey.shade300,
                  foregroundColor: isSelected ? Colors.white : Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  elevation: 2,
                  shadowColor: Colors.black.withOpacity(0.2),
                ),
                child: Text(s, style: const TextStyle(fontSize: 12)),
              ),
            );
          }).toList(),
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
      });
      await _fetchAndGroup(initial: false);
    }
  }

  Future<void> _onRefreshPressed() async {
    setState(() {
      fromDate = DateTime.now();
      toDate = null;
      selectedBranchId = 'ALL';
      selectedSource = 'ALL';
    });
    await _fetchAndGroup(initial: false);
  }

  Widget _buildDateSelector() {
    final safeFrom = fromDate ?? DateTime.now();
    final dateFmt = DateFormat('MMM d');
    final label = toDate == null
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
      items: branches
          .map((b) {
        final name = b['name'] ?? 'Unnamed';
        final abbr =
        b['id'] == 'ALL' ? 'All Branches' : name.substring(0, min(3, name.length)).toUpperCase();
        return DropdownMenuItem<String>(
          value: b['id'],
          child: Text(abbr, overflow: TextOverflow.ellipsis),
        );
      })
          .toList(),
      onChanged: (v) async {
        if (v == null) return;
        setState(() => selectedBranchId = v);
        await _fetchAndGroup();
      },
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        isDense: true,
      ),
    );
  }

  String _formatAmount(double amt) {
    if (amt == amt.floor()) {
      return amt.toInt().toString();
    } else {
      return amt.toStringAsFixed(2);
    }
  }

  void _showExpenseDetailsPopup(
      String category, String reason, double amount, String formattedDate) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.all(24),
        title: Text(
          formattedDate,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Category:', category),
            const SizedBox(height: 8),
            _buildDetailRow('Reason:', reason.toUpperCase()), // UPDATED → CAPS
            const SizedBox(height: 8),
            _buildDetailRow('Amount:', _formatAmount(amount)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 14, color: Colors.black54)),
        ),
      ],
    );
  }

  Widget _buildBranchCard(String branchName) {
    List<Map<String, dynamic>> details = expenseDetails[branchName] ?? [];

    details.sort((a, b) {
      final dateA = a['date'] as DateTime?;
      final dateB = b['date'] as DateTime?;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateB.compareTo(dateA);
    });

    double branchTotal = details.fold(0.0, (sum, d) => sum + (d['amount'] as double));
    int branchCount = details.length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(branchName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              const Spacer(),
              Text(
                _formatAmount(branchTotal),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('$branchCount items',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          if (details.isEmpty)
            const Center(child: Text('No expenses'))
          else ...[
            Row(
              children: const [
                Expanded(
                    child: Text('Category',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(
                    child: Text('Reason',
                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                Expanded(
                    child: Align(
                        alignment: Alignment.centerRight,
                        child: Text('Amount',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
              ],
            ),
            const Divider(height: 8),
            ...details.asMap().entries.map((entry) {
              int idx = entry.key;
              Map<String, dynamic> d = entry.value;
              final bgColor = idx % 2 == 0 ? Colors.white : Colors.grey.shade100;

              return GestureDetector(
                onTap: () => _showExpenseDetailsPopup(
                  d['source'] as String,
                  d['reason'] as String,
                  d['amount'] as double,
                  d['formattedDate'] as String,
                ),
                child: Container(
                  color: bgColor,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(d['source'] as String,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis)),
                      Expanded(
                          child: Text(
                            (d['reason'] as String).toUpperCase(), // UPDATED → CAPS
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          )),
                      Expanded(
                          child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                _formatAmount(d['amount'] as double),
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold),
                              ))),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Text('Total Items: $grandCount',
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        const Spacer(),
        Text(_formatAmount(grandTotal),
            style:
            const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 20)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeFrom = fromDate ?? DateTime.now();
    final dateFmt = DateFormat('MMM d');
    final dateLabel = toDate == null
        ? dateFmt.format(safeFrom)
        : '${dateFmt.format(safeFrom)} - ${dateFmt.format(toDate!)}';

    List<String> branchNames = expenseDetails.keys.toList();
    branchNames.sort((a, b) {
      double totalA = expenseDetails[a]!.fold(0.0, (sum, d) => sum + (d['amount'] as double));
      double totalB = expenseDetails[b]!.fold(0.0, (sum, d) => sum + (d['amount'] as double));
      return totalB.compareTo(totalA);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense-wise Report'),
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
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(
            children: [
              _buildDateSelector(),
              const SizedBox(width: 12),
              Expanded(child: _buildBranchFilter()),
            ],
          ),
          const SizedBox(height: 12),
          _buildSourceFilter(),
          const SizedBox(height: 12),
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: (details) async {
                final int index = sources.indexOf(selectedSource);
                String? newSource;

                if (details.primaryVelocity! < 0) {
                  if (index < sources.length - 1) newSource = sources[index + 1];
                } else if (details.primaryVelocity! > 0) {
                  if (index > 0) newSource = sources[index - 1];
                }

                if (newSource != null) {
                  String oldSource = selectedSource;
                  selectedSource = newSource;
                  setState(() {});
                  await _fetchAndGroup();

                  if (selectedSource != oldSource) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _sourceKeys[selectedSource]?.currentContext != null) {
                        Scrollable.ensureVisible(_sourceKeys[selectedSource]!.currentContext!,
                            alignment: 0.5, duration: const Duration(milliseconds: 300));
                      }
                    });
                  }
                }
              },
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : branchNames.isEmpty
                  ? const Center(child: Text('No data for selected range'))
                  : ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: branchNames.length,
                itemBuilder: (context, index) =>
                    _buildBranchCard(branchNames[index]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildFooter(),
        ]),
      ),
    );
  }
}
