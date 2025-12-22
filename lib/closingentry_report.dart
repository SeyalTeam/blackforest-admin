import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/app_drawer.dart';

class ClosingEntryReportPage extends StatefulWidget {
  final String? initialBranchId;
  final bool? initialCombinedView;
  final DateTime? initialFromDate;
  final DateTime? initialToDate;

  const ClosingEntryReportPage({
    super.key,
    this.initialBranchId,
    this.initialCombinedView,
    this.initialFromDate,
    this.initialToDate,
  });

  @override
  State<ClosingEntryReportPage> createState() => _ClosingEntryReportPageState();
}

class _ClosingEntryReportPageState extends State<ClosingEntryReportPage> {
  bool _loading = true;
  bool _loadingBranches = true;
  DateTime? fromDate;
  DateTime? toDate;
  List<Map<String, String>> branches = [];
  String selectedBranchId = "ALL";
  List<Map<String, dynamic>> entries = [];
  double totalSales = 0;
  double totalExpenses = 0;
  double totalNet = 0;
  double totalReturns = 0;
  double totalStockOrders = 0;
  double totalCash = 0;
  double totalUpi = 0;
  double totalCard = 0;
  double totalPayments = 0;
  double totalProductDif = 0;
  double totalSalesDif = 0;
  bool _combinedView = true;
  bool _branchFilterEnabled = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    fromDate = widget.initialFromDate ?? now;
    toDate = widget.initialToDate ?? now;
    if (widget.initialBranchId != null) {
      selectedBranchId = widget.initialBranchId!;
      _branchFilterEnabled = false;
    }
    if (widget.initialCombinedView != null) {
      _combinedView = widget.initialCombinedView!;
    }
    _fetchBranches().then((_) => _fetchEntries());
  }

  Future<void> _fetchBranches() async {
    setState(() => _loadingBranches = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      final url = Uri.parse(
          "https://admin.theblackforestcakes.com/api/branches?limit=3000");
      final res = await http.get(url, headers: {"Authorization": "Bearer $token"});
      final data = jsonDecode(res.body);
      final docs = data["docs"] ?? [];
      final list = <Map<String, String>>[
        {"id": "ALL", "name": "All Branches"}
      ];
      for (var b in docs) {
        final id = (b["id"] ?? b["_id"]).toString();
        final name = (b["name"] ?? "Unnamed").toString();
        list.add({"id": id, "name": name});
      }
      setState(() => branches = list);
    } catch (e) {
      debugPrint("Branch error: $e");
    } finally {
      setState(() => _loadingBranches = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: fromDate!, end: toDate!),
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() {
        fromDate = picked.start;
        toDate = picked.end;
      });
      await _fetchEntries();
    }
  }

  Future<void> _fetchEntries() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = DateTime(
          toDate!.year, toDate!.month, toDate!.day, 23, 59, 59);
      final startStr = start.toUtc().toIso8601String();
      final endStr = end.toUtc().toIso8601String();
      String url =
          "https://admin.theblackforestcakes.com/api/closing-entries?depth=1&limit=10000"
          "&where[createdAt][greater_than]=$startStr"
          "&where[createdAt][less_than]=$endStr";
      if (selectedBranchId != "ALL") {
        url += "&where[branch][equals]=$selectedBranchId";
      }
      final res = await http.get(Uri.parse(url),
          headers: {"Authorization": "Bearer $token"});
      final data = jsonDecode(res.body);
      final docs = data["docs"] ?? [];
      double tSales = 0, tExp = 0, tNet = 0, tReturn = 0, tStock = 0, tCash = 0, tUpi = 0, tCard = 0, tPayments = 0;
      for (var d in docs) {
        tSales += (d["totalSales"] ?? 0).toDouble();
        tExp += (d["expenses"] ?? 0).toDouble();
        tNet += (d["net"] ?? 0).toDouble();
        tReturn += (d["returnTotal"] ?? 0).toDouble();
        tStock += (d["stockOrders"] ?? 0).toDouble();
        tPayments += (d["totalPayments"] ?? 0).toDouble();
        tCash += (d["cash"] ?? 0).toDouble();
        tUpi += (d["upi"] ?? 0).toDouble();
        tCard += (d["creditCard"] ?? 0).toDouble();
      }
      setState(() {
        entries = docs.cast<Map<String, dynamic>>();
        entries.sort((a, b) => DateTime.parse(b['createdAt'])
            .compareTo(DateTime.parse(a['createdAt'])));
        totalExpenses = tExp;
        totalSales = tSales;
        totalNet = tNet;
        totalReturns = tReturn;
        totalStockOrders = tStock;
        totalCash = tCash;
        totalUpi = tUpi;
        totalCard = tCard;
        totalPayments = tExp + tPayments; // Total Payments = Expenses + Total Payments
        totalProductDif = totalStockOrders - totalReturns;
        totalSalesDif = totalPayments - totalSales; // Sales Dif = Total Payments - Total Sales (expenses already included in totalPayments)
      });
    } catch (e) {
      debugPrint("Fetch error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _headerButton() {
    final fmt = DateFormat("MMM d");
    final fromLabel = fmt.format(fromDate!);
    final toLabel = fmt.format(toDate!);
    final bool sameDay = fromDate!.year == toDate!.year && fromDate!.month == toDate!.month && fromDate!.day == toDate!.day;
    final label = sameDay ? fromLabel : "$fromLabel - $toLabel";
    return InkWell(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
            color: Colors.black, borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleIcon() {
    return IconButton(
      icon: Icon(
        _combinedView ? Icons.view_list : Icons.view_list_outlined,
        color: Colors.black,
      ),
      onPressed: () {
        setState(() => _combinedView = !_combinedView);
      },
    );
  }

  Widget _branchFilter() {
    return _loadingBranches
        ? const SizedBox(
      height: 40,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    )
        : DropdownButtonFormField<String>(
      value: selectedBranchId,
      decoration: InputDecoration(
        labelText: "Branch",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      items: branches
          .map((b) => DropdownMenuItem(value: b["id"], child: Text(b["name"]!)))
          .toList(),
      onChanged: _branchFilterEnabled ? (v) {
        setState(() => selectedBranchId = v!);
        _fetchEntries();
      } : null,
    );
  }

  List<Map<String, dynamic>> _getDisplayedEntries() {
    if (!_combinedView) {
      return entries;
    }
    final Map<String, Map<String, dynamic>> combined = {};
    for (var e in entries) {
      final branchId = e["branch"]?["id"] ?? "unknown";
      final entryDate = DateTime.tryParse(e["createdAt"] ?? "");
      if (entryDate == null) continue;
      final dateKey =
          '${entryDate.year}-${entryDate.month.toString().padLeft(2, '0')}-${entryDate.day.toString().padLeft(2, '0')}';
      final key = '${branchId}_$dateKey';
      if (!combined.containsKey(key)) {
        combined[key] = {
          "branch": e["branch"],
          "date": entryDate,
          "systemSales": 0.0,
          "manualSales": 0.0,
          "onlineSales": 0.0,
          "expenses": 0.0,
          "returnTotal": 0.0,
          "stockOrders": 0.0,
          "totalSales": 0.0,
          "totalPayments": 0.0,
          "net": 0.0,
          "count": 0,
          "lastUpdated": null,
          "cash": 0.0,
          "upi": 0.0,
          "creditCard": 0.0,
        };
      }
      combined[key]!["systemSales"] += (e["systemSales"] ?? 0).toDouble();
      combined[key]!["manualSales"] += (e["manualSales"] ?? 0).toDouble();
      combined[key]!["onlineSales"] += (e["onlineSales"] ?? 0).toDouble();
      combined[key]!["expenses"] += (e["expenses"] ?? 0).toDouble();
      combined[key]!["returnTotal"] += (e["returnTotal"] ?? 0).toDouble();
      combined[key]!["stockOrders"] += (e["stockOrders"] ?? 0).toDouble();
      combined[key]!["totalSales"] += (e["totalSales"] ?? 0).toDouble();
      combined[key]!["totalPayments"] += (e["totalPayments"] ?? 0).toDouble();
      combined[key]!["net"] += (e["net"] ?? 0).toDouble();
      combined[key]!["cash"] += (e["cash"] ?? 0).toDouble();
      combined[key]!["upi"] += (e["upi"] ?? 0).toDouble();
      combined[key]!["creditCard"] += (e["creditCard"] ?? 0).toDouble();
      combined[key]!["count"] += 1;
      final currentTime = DateTime.parse(e["createdAt"]);
      if (combined[key]!["lastUpdated"] == null ||
          currentTime.isAfter(combined[key]!["lastUpdated"])) {
        combined[key]!["lastUpdated"] = currentTime;
      }
    }
    var combinedList = combined.values.toList();
    combinedList.sort((a, b) => b['date'].compareTo(a['date']));
    return combinedList;
  }

  String _formatAmount(dynamic value) {
    if (value is! double) return value.toString();
    if (value == value.floor()) {
      return value.toInt().toString();
    } else {
      return value.toStringAsFixed(2);
    }
  }

  Widget _entryCard(Map<String, dynamic> e, {bool isCombined = false}) {
    final branchName = e["branch"]?["name"] ?? "Unknown Branch";
    final dateFmt = DateFormat("MMM-d");
    final timeFmt = DateFormat("h:mm a");
    final entryDate = isCombined ? e["date"] : DateTime.tryParse(e["createdAt"] ?? "");
    final istOffset = Duration(hours: 5, minutes: 30);
    final istDate = entryDate != null ? entryDate.add(istOffset) : null;
    final dateStr = istDate != null ? dateFmt.format(istDate) : "";
    final timeStr = isCombined
        ? (e["lastUpdated"] != null ? timeFmt.format(e["lastUpdated"].add(istOffset)) : "")
        : (istDate != null ? timeFmt.format(istDate) : "");
    final count = isCombined ? e["count"] ?? 1 : 1;
    final branchHeader = isCombined ? "$branchName  #CLO-$count" : branchName;
    final productTotal = (e["stockOrders"] ?? 0).toDouble() - (e["returnTotal"] ?? 0).toDouble();
    final originalTotalPayments = (e["totalPayments"] ?? 0).toDouble(); // cash+upi+card only
    final totalPaymentsWithExpenses = (e["expenses"] ?? 0).toDouble() + originalTotalPayments;
    final productDif = originalTotalPayments - productTotal; // Total Sales (cash+upi+card) - Product Total
    final salesDif = totalPaymentsWithExpenses - (e["totalSales"] ?? 0).toDouble();

    final detailRows = [
      _infoRow("System Bills", e["systemSales"], 0),
      _infoRow("Manual Bills", e["manualSales"], 1),
      _infoRow("Online Bills", e["onlineSales"], 2),
      _infoRow("Total Bills", e["totalSales"], 3),
      _infoRow("Expenses", e["expenses"], 4),
      _infoRow("Cash", e["cash"], 5),
      _infoRow("UPI", e["upi"], 6),
      _infoRow("Card", e["creditCard"], 7),
      _infoRow("Total Sales", totalPaymentsWithExpenses, 8),
      _infoRow("Sales Dif", salesDif, 9),
      _infoRow("Stock Orders", e["stockOrders"], 10),
      _infoRow("Return Total", e["returnTotal"], 11),
      _infoRow("Product Total", productTotal, 12),
      _infoRow("Product Dif", productDif, 13),
      _infoRow("Net Amount", e["net"], 14, isBold: true),
    ];

    return GestureDetector(
      onTap: isCombined ? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ClosingEntryReportPage(
              initialBranchId: e["branch"]["id"],
              initialCombinedView: false,
              initialFromDate: fromDate,
              initialToDate: toDate,
            ),
          ),
        );
      } : null,
      child: Card(
        color: Colors.green.shade100,
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.green.shade800,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isCombined)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          branchHeader,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        Text(
                          timeStr,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70),
                        ),
                      ],
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          e["closingNumber"] ?? "",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                        Text(
                          "$dateStr $timeStr",
                          style: const TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      branchName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),
            Column(
              children: detailRows,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, dynamic value, int index, {bool isBold = false}) {
    final backgroundColor = index % 2 == 0 ? Colors.white : Colors.green.shade50;
    
    // Special styling for Total Bills, Total Sales, and Product Dif - centered and larger
    if (label == "Total Bills" || label == "Total Sales" || label == "Product Dif") {
      Icon? arrowIcon;
      
      if (label == "Product Dif" && value is double) {
        if (value > 0) {
          arrowIcon = const Icon(Icons.arrow_upward, color: Colors.green, size: 18);
        } else if (value < 0) {
          arrowIcon = const Icon(Icons.arrow_downward, color: Colors.red, size: 18);
        }
      }
      
      return Container(
        color: backgroundColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "$label: ",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (arrowIcon != null) ...[
                arrowIcon,
                const SizedBox(width: 4),
              ],
              Text(
                _formatAmount(value),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Special handling for Sales Dif (not Total Bills/Total Sales/Product Dif)
    Icon? arrowIcon;
    if (label == "Sales Dif") {
      if (value is double) {
        if (value > 0) {
          arrowIcon = const Icon(Icons.arrow_upward, color: Colors.green, size: 18);
        } else if (value < 0) {
          arrowIcon = const Icon(Icons.arrow_downward, color: Colors.red, size: 18);
        }
      }
      return Container(
        color: backgroundColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: 1,
                child: Text(label,
                    style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                flex: 1,
                child: Center(child: arrowIcon ?? const SizedBox.shrink()),
              ),
              Expanded(
                flex: 1,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "${_formatAmount(value)}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Regular rows
      return Container(
        color: backgroundColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 14),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold))),
              Text(
                "₹${_formatAmount(value)}",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _compactSummaryCard() {
    return Card(
      color: Colors.green.shade100,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Row 1: Total Bills & Total Sales
            Row(
              children: [
                Expanded(
                  child: _summaryItem("Total Bills", totalSales, isBoldValue: true, isLarge: true),
                ),
                Expanded(
                  child: _summaryItem("Total Sales", totalPayments, isBoldValue: true, isLarge: true),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Row 2: Expenses, Returns, Stock (all 3 in one row)
            Row(
              children: [
                Expanded(
                  child: _summaryItem("Expenses", totalExpenses, isBoldValue: true),
                ),
                Expanded(
                  child: _summaryItem("Returns", totalReturns, isBoldValue: true),
                ),
                Expanded(
                  child: _summaryItem("Stock", totalStockOrders, isBoldValue: true),
                ),
              ],
            ),
            const Divider(height: 16, thickness: 1.5, color: Colors.green),
            // Row 3: Net Amount (full width, bold, larger)
            _summaryItem("Net Amount", totalNet, isBold: true, isLarge: true),
            const Divider(height: 16, thickness: 1.5, color: Colors.green),
            // Row 4: Cash, UPI, Card (all 3 in one row) - Cash shows ₹ instead of $
            Row(
              children: [
                Expanded(
                  child: _summaryItem("₹ Cash", totalCash, isBoldValue: true),
                ),
                Expanded(
                  child: _summaryItem("UPI", totalUpi, icon: Icons.qr_code_scanner, isBoldValue: true),
                ),
                Expanded(
                  child: _summaryItem("Card", totalCard, icon: Icons.credit_card, isBoldValue: true),
                ),
              ],
            ),
            const Divider(height: 16, thickness: 1.5, color: Colors.green),
            // Row 5: Product Dif & Sales Dif
            Row(
              children: [
                Expanded(
                  child: _summaryItem(
                    "Product Dif",
                    totalProductDif,
                    showArrow: true,
                    isBoldValue: true,
                    isLarge: true,
                  ),
                ),
                Expanded(
                  child: _summaryItem(
                    "Sales Dif",
                    totalSalesDif,
                    showArrow: true,
                    isBoldValue: true,
                    isLarge: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, double value, {
    bool isBold = false,
    bool isLarge = false,
    bool isBoldValue = false,
    IconData? icon,
    bool showArrow = false,
  }) {
    Widget? arrowWidget;

    if (showArrow) {
      if (value > 0) {
        arrowWidget = const Icon(Icons.arrow_upward, color: Colors.green, size: 14);
      } else if (value < 0) {
        arrowWidget = const Icon(Icons.arrow_downward, color: Colors.red, size: 14);
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 4),
        ],
        Text(
          "$label:",
          style: TextStyle(
            fontSize: isLarge ? 15 : 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(width: 4),
        if (arrowWidget != null) ...[
          arrowWidget,
          const SizedBox(width: 2),
        ],
        Text(
          _formatAmount(value),
          style: TextStyle(
            fontSize: isLarge ? 18 : 13,
            fontWeight: (isBold || isBoldValue) ? FontWeight.bold : FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayedEntries = _getDisplayedEntries();
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;

    Widget mainContent = Column(
      children: [
        // Fixed Header: Calendar and Branch Filter
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _headerButton(),
                  _toggleIcon(),
                ],
              ),
              const SizedBox(height: 12),
              _branchFilter(),
            ],
          ),
        ),
        // Scrollable: Summary Card and Entries
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : displayedEntries.isEmpty
              ? const Center(child: Text("No closing entries"))
              : ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: displayedEntries.length + 1, // +1 for summary card
            itemBuilder: (_, i) {
              if (i == 0) {
                // First item is the summary card
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _compactSummaryCard(),
                );
              }
              // Rest are entry cards
              return _entryCard(
                displayedEntries[i - 1],
                isCombined: _combinedView,
              );
            },
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Closing Entries"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                selectedBranchId = "ALL";
                _combinedView = true;
                _branchFilterEnabled = true;
                fromDate = DateTime.now();
                toDate = DateTime.now();
              });
              _fetchEntries();
            },
          )
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