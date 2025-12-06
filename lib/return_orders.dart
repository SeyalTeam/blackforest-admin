import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/app_drawer.dart';

class ReturnOrdersPage extends StatefulWidget {
  final String? initialBranchId;
  final bool? initialCombinedView;
  final DateTime? initialFromDate;
  final DateTime? initialToDate;

  const ReturnOrdersPage({
    super.key,
    this.initialBranchId,
    this.initialCombinedView,
    this.initialFromDate,
    this.initialToDate,
  });

  @override
  State<ReturnOrdersPage> createState() => _ReturnOrdersPageState();
}

class _ReturnOrdersPageState extends State<ReturnOrdersPage> {
  bool _loading = true;
  bool _loadingBranches = true;
  DateTime? fromDate;
  DateTime? toDate;
  List<Map<String, String>> branches = [];
  String selectedBranchId = 'ALL';
  bool _combinedView = true;

  // All return orders
  List<Map<String, dynamic>> allReturnOrders = [];

  // Grand totals
  double grandTotal = 0.0;
  int grandCount = 0;

  @override
  void initState() {
    super.initState();
    fromDate = widget.initialFromDate ?? DateTime.now();
    toDate = widget.initialToDate;
    if (widget.initialBranchId != null) {
      selectedBranchId = widget.initialBranchId!;
    }
    if (widget.initialCombinedView != null) {
      _combinedView = widget.initialCombinedView!;
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _fetchBranches();
    await _fetchReturnOrders();
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

  Future<void> _fetchReturnOrders() async {
    if (fromDate == null) return;
    setState(() => _loading = true);
    try {
      final token = await _getToken();
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);
      
      var url = 'https://admin.theblackforestcakes.com/api/return-orders?limit=1000&depth=1'
          '&where[createdAt][greater_than]=${start.toUtc().toIso8601String()}'
          '&where[createdAt][less_than]=${end.toUtc().toIso8601String()}';
      
      if (selectedBranchId != 'ALL') {
        url += '&where[branch][equals]=$selectedBranchId';
      }

      final res = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];

        double total = 0.0;
        int count = 0;

        for (var order in docs) {
          total += (order['totalAmount'] ?? 0).toDouble();
          count += (order['items'] as List?)?.length ?? 0;
        }

        setState(() {
          allReturnOrders = docs.cast<Map<String, dynamic>>();
          allReturnOrders.sort((a, b) {
            final dateA = DateTime.tryParse(a['createdAt'] is Map ? a['createdAt']['\$date'] : a['createdAt']);
            final dateB = DateTime.tryParse(b['createdAt'] is Map ? b['createdAt']['\$date'] : b['createdAt']);
            if (dateA == null && dateB == null) return 0;
            if (dateA == null) return 1;
            if (dateB == null) return -1;
            return dateB.compareTo(dateA);
          });
          grandTotal = total;
          grandCount = count;
        });
      }
    } catch (e) {
      debugPrint('fetchReturnOrders error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _getDisplayedReturns() {
    if (!_combinedView) {
      return allReturnOrders;
    }

    // Combined view: group by branch + date
    final Map<String, Map<String, dynamic>> combined = {};
    
    for (var order in allReturnOrders) {
      // Get branch ID
      String branchId = 'unknown';
      String branchName = 'Unknown';
      final branch = order['branch'];
      if (branch != null) {
        if (branch is Map) {
          branchId = (branch['id'] ?? branch['_id'] ?? 'unknown').toString();
          branchName = (branch['name'] ?? 'Unknown').toString();
        } else if (branch is String) {
          branchId = branch;
          final match = branches.firstWhere(
            (b) => b['id'] == branch,
            orElse: () => {'id': branchId, 'name': 'Unknown'},
          );
          branchName = match['name']!;
        }
      }

      // Get date
      final createdAt = DateTime.tryParse(
        order['createdAt'] is Map ? order['createdAt']['\$date'] : order['createdAt']
      );
      if (createdAt == null) continue;

      final dateKey = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
      final key = '${branchId}_$dateKey';

      if (!combined.containsKey(key)) {
        combined[key] = {
          'branch': {'id': branchId, 'name': branchName},
          'date': createdAt,
          'totalAmount': 0.0,
          'itemCount': 0,
          'returnCount': 0,
          'lastUpdated': null,
          'allItems': <Map<String, dynamic>>[],
          'orderIds': <String>[],
          'statuses': <String>[], // Track all individual statuses
        };
      }

      combined[key]!['totalAmount'] += (order['totalAmount'] ?? 0).toDouble();
      combined[key]!['itemCount'] += (order['items'] as List?)?.length ?? 0;
      combined[key]!['returnCount'] += 1;
      
      // Track order IDs for bulk status update
      String? orderIdStr;
      if (order.containsKey('_id')) {
        final idField = order['_id'];
        if (idField is Map && idField.containsKey('\$oid')) {
          orderIdStr = idField['\$oid'].toString();
        } else if (idField is String) {
          orderIdStr = idField;
        }
      }
      // Fallback to 'id'
      if ((orderIdStr == null || orderIdStr.isEmpty) && order.containsKey('id')) {
        orderIdStr = order['id'].toString();
      }

      if (orderIdStr != null && orderIdStr.isNotEmpty) {
        combined[key]!['orderIds'].add(orderIdStr);
      }
      
      // Track all statuses
      final currentStatus = order['status'] ?? 'pending';
      combined[key]!['statuses'].add(currentStatus);
      
      // Track last updated time
      if (combined[key]!['lastUpdated'] == null || createdAt.isAfter(combined[key]!['lastUpdated'])) {
        combined[key]!['lastUpdated'] = createdAt;
      }

      // Collect all items
      final items = (order['items'] as List?) ?? [];
      for (var item in items) {
        final itemMap = Map<String, dynamic>.from(item as Map);
        itemMap['returnNumber'] = order['returnNumber'];
        combined[key]!['allItems'].add(itemMap);
      }
    }

    // Calculate combined status for each group
    for (var entry in combined.entries) {
      final statuses = entry.value['statuses'] as List<String>;
      String combinedStatus;
      
      if (statuses.isEmpty) {
        combinedStatus = 'pending';
      } else if (statuses.every((s) => s == statuses.first)) {
        // All statuses are the same
        combinedStatus = statuses.first;
      } else if (statuses.any((s) => s == 'pending')) {
        // If any is pending, show pending
        combinedStatus = 'pending';
      } else if (statuses.any((s) => s == 'cancelled')) {
        // If any is cancelled, show cancelled
        combinedStatus = 'cancelled';
      } else if (statuses.every((s) => s == 'accepted' || s == 'returned')) {
        // Mix of accepted and returned, show returned
        combinedStatus = 'returned';
      } else {
        // Default to pending
        combinedStatus = 'pending';
      }
      
      entry.value['status'] = combinedStatus;
    }

    var combinedList = combined.values.toList();
    combinedList.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    return combinedList;
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'returned':
        return Colors.red;
      case 'accepted':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  Widget _buildStatusChip(String status, {VoidCallback? onTap}) {
    final color = _getStatusColor(status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              status.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.edit, color: Colors.white, size: 14),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _updateReturnStatus(List<String> orderIds, String newStatus) async {
    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Updating status...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );
    }

    try {
      final token = await _getToken();
      debugPrint('Updating ${orderIds.length} order(s) to status: $newStatus');
      
      int successCount = 0;
      int failCount = 0;
      
      // Update all orders in the group
      for (var orderId in orderIds) {
        debugPrint('Updating order: $orderId');
        final url = 'https://admin.theblackforestcakes.com/api/return-orders/$orderId';
        debugPrint('PATCH URL: $url');
        
        final res = await http.patch(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'status': newStatus}),
        );
        
        debugPrint('Response status: ${res.statusCode}');
        debugPrint('Response body: ${res.body}');
        
        if (res.statusCode == 200 || res.statusCode == 201) {
          successCount++;
          debugPrint('Successfully updated order $orderId');
        } else {
          failCount++;
          debugPrint('Failed to update order $orderId: ${res.statusCode} - ${res.body}');
        }
      }
      
      // Update local state instead of refetching
      if (successCount > 0 && mounted) {
        setState(() {
          for (var order in allReturnOrders) {
            // Robust ID extraction
            String? orderIdStr;
            if (order.containsKey('_id')) {
              final idField = order['_id'];
              if (idField is Map && idField.containsKey('\$oid')) {
                orderIdStr = idField['\$oid'].toString();
              } else if (idField is String) {
                orderIdStr = idField;
              }
            }
            if ((orderIdStr == null || orderIdStr.isEmpty) && order.containsKey('id')) {
              orderIdStr = order['id'].toString();
            }
            
            if (orderIdStr != null && orderIds.contains(orderIdStr)) {
              order['status'] = newStatus;
            }
          }
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Status updated to ${newStatus.toUpperCase()} for $successCount return(s)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        if (failCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update $failCount return(s)'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showStatusDialog(List<String> orderIds, String currentStatus) {
    final statuses = ['returned', 'pending', 'accepted', 'cancelled'];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: statuses.map((status) {
            final isSelected = status == currentStatus;
            return ListTile(
              leading: Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: _getStatusColor(status),
              ),
              title: Text(
                status.toUpperCase(),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _updateReturnStatus(orderIds, status);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
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
      await _fetchReturnOrders();
    }
  }

  Future<void> _onRefreshPressed() async {
    setState(() {
      fromDate = DateTime.now();
      toDate = null;
      selectedBranchId = 'ALL';
    });
    await _fetchReturnOrders();
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
            items: branches.map((b) {
              return DropdownMenuItem<String>(
                value: b['id'],
                child: Text(b['name']!, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) async {
              if (v == null) return;
              setState(() => selectedBranchId = v);
              await _fetchReturnOrders();
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

  void _showProofPhoto(dynamic proofPhotoData) async {
    try {
      final token = await _getToken();
      
      // Extract the actual photo identifier
      String? photoIdentifier;
      
      if (proofPhotoData is Map) {
        // Check if it's a populated media object with filename
        if (proofPhotoData.containsKey('filename')) {
          photoIdentifier = proofPhotoData['filename'];
        } else if (proofPhotoData.containsKey('url')) {
          photoIdentifier = proofPhotoData['url'];
        } else if (proofPhotoData.containsKey('\$oid')) {
          photoIdentifier = proofPhotoData['\$oid'];
        } else if (proofPhotoData.containsKey('id')) {
          photoIdentifier = proofPhotoData['id'];
        }
      } else if (proofPhotoData is String) {
        photoIdentifier = proofPhotoData;
      }
      
      if (photoIdentifier == null) {
        debugPrint('No photo identifier found in: $proofPhotoData');
        return;
      }
      
      final imageUrl = 'https://admin.theblackforestcakes.com/api/media/file/$photoIdentifier';
      debugPrint('Loading image from: $imageUrl');
      
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.black,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text(
                  'Proof Photo',
                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.black,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Flexible(
                child: Container(
                  color: Colors.black,
                  child: Image.network(
                    imageUrl,
                    headers: {'Authorization': 'Bearer $token'},
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                              : null,
                          color: Colors.white,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('Image load error: $error');
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error, color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'Failed to load image',
                              style: TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              photoIdentifier!,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error showing photo: $e');
    }
  }

  Widget _buildReturnCard(Map<String, dynamic> returnData, {bool isCombined = false}) {
    if (isCombined) {
      return _buildCombinedCard(returnData);
    } else {
      return _buildDetailCard(returnData);
    }
  }

  Widget _buildCombinedCard(Map<String, dynamic> returnData) {
    final branch = returnData['branch'] as Map<String, dynamic>;
    final branchName = branch['name'] as String;
    final branchId = branch['id'] as String;
    final returnCount = returnData['returnCount'] as int;
    final itemCount = returnData['itemCount'] as int;
    final totalAmount = returnData['totalAmount'] as double;
    final lastUpdated = returnData['lastUpdated'] as DateTime;
    final date = returnData['date'] as DateTime;
    final allItems = returnData['allItems'] as List<Map<String, dynamic>>;
    final status = returnData['status'] as String;
    final orderIds = returnData['orderIds'] as List<String>;

    final istDate = lastUpdated.add(const Duration(hours: 5, minutes: 30));
    final dateFmt = DateFormat('MMM-d');
    final timeFmt = DateFormat('h:mm a');
    final dateStr = dateFmt.format(istDate);
    final timeStr = timeFmt.format(istDate);

    // Aggregate items by product name
    final Map<String, Map<String, dynamic>> aggregatedItems = {};
    for (var item in allItems) {
      final name = item['name'] ?? 'Unknown';
      final qty = (item['quantity'] ?? 0).toDouble();
      final unitPrice = (item['unitPrice'] ?? 0).toDouble();
      final subtotal = (item['subtotal'] ?? 0).toDouble();
      final proofPhoto = item['proofPhoto'];

      if (aggregatedItems.containsKey(name)) {
        aggregatedItems[name]!['quantity'] += qty;
        aggregatedItems[name]!['subtotal'] += subtotal;
      } else {
        aggregatedItems[name] = {
          'name': name,
          'quantity': qty,
          'unitPrice': unitPrice,
          'subtotal': subtotal,
          'proofPhoto': proofPhoto,
        };
      }
    }

    final productList = aggregatedItems.values.toList();

    return GestureDetector(
      onTap: () {
        // Navigate to detail view
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReturnOrdersPage(
              initialBranchId: branchId,
              initialFromDate: date,
              initialToDate: date,
              initialCombinedView: false,
            ),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: Colors.red.shade50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$branchName  #RET-$returnCount',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    '$dateStr $timeStr',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
            // Products header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: const [
                  Expanded(flex: 3, child: Text('Product', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(flex: 1, child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text('Price', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                  Expanded(flex: 1, child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                ],
              ),
            ),
            const Divider(height: 1),
            // Products list
            ...productList.asMap().entries.map((entry) {
              int idx = entry.key;
              var item = entry.value;
              final bgColor = idx % 2 == 0 ? Colors.white : Colors.red.shade50;
              final name = item['name'] ?? 'Unknown';
              final qty = (item['quantity'] ?? 0).toDouble();
              final unitPrice = (item['unitPrice'] ?? 0).toDouble();
              final subtotal = (item['subtotal'] ?? 0).toDouble();
              final proofPhoto = item['proofPhoto'];
              final photoId = proofPhoto is Map ? proofPhoto['\$oid'] : proofPhoto;

              return InkWell(
                onTap: () {
                  if (proofPhoto != null) {
                    _showProofPhoto(proofPhoto);
                  }
                },
                child: Container(
                  color: bgColor,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            if (photoId != null)
                              const Icon(Icons.image, size: 16, color: Colors.blue),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: photoId != null ? Colors.blue : Colors.black87,
                                  decoration: photoId != null ? TextDecoration.underline : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          _formatAmount(qty),
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          _formatAmount(unitPrice),
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          _formatAmount(subtotal),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            // Status and Total row
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                border: Border(top: BorderSide(color: Colors.red.shade300, width: 2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatusChip(
                    status,
                    onTap: () => _showStatusDialog(orderIds, status),
                  ),
                  Text(
                    '₹${_formatAmount(totalAmount)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(Map<String, dynamic> order) {
    final returnNumber = order['returnNumber'] ?? 'Unknown';
    final createdAt = DateTime.tryParse(
      order['createdAt'] is Map ? order['createdAt']['\$date'] : order['createdAt']
    );
    final istDate = createdAt?.add(const Duration(hours: 5, minutes: 30));
    final formattedDate = istDate != null ? DateFormat('MMM d, yyyy h:mm a').format(istDate) : 'Unknown';
    final items = (order['items'] as List?) ?? [];
    final totalAmount = (order['totalAmount'] ?? 0).toDouble();
    final status = order['status'] ?? 'pending';
    
    // Get order ID - try multiple fields
    String? orderIdStr;
    if (order.containsKey('_id')) {
      final idField = order['_id'];
      if (idField is Map && idField.containsKey('\$oid')) {
        orderIdStr = idField['\$oid'].toString();
      } else if (idField is String) {
        orderIdStr = idField;
      }
    }
    
    // Fallback to 'id' field if _id not found
    if ((orderIdStr == null || orderIdStr.isEmpty) && order.containsKey('id')) {
      orderIdStr = order['id'].toString();
    }
    
    debugPrint('Order ID for $returnNumber: $orderIdStr');
    debugPrint('Order keys: ${order.keys.toList()}');

    // Get branch name
    String branchName = 'Unknown';
    final branch = order['branch'];
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.red.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        returnNumber,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        branchName,
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Text(
                  formattedDate,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          // Items header
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: const [
                Expanded(flex: 3, child: Text('Product', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 1, child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                Expanded(flex: 1, child: Text('Price', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                Expanded(flex: 1, child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Items
          ...items.asMap().entries.map((entry) {
            int idx = entry.key;
            var item = entry.value;
            final bgColor = idx % 2 == 0 ? Colors.white : Colors.red.shade50;
            final name = item['name'] ?? 'Unknown';
            final qty = (item['quantity'] ?? 0).toDouble();
            final unitPrice = (item['unitPrice'] ?? 0).toDouble();
            final subtotal = (item['subtotal'] ?? 0).toDouble();
            final proofPhoto = item['proofPhoto'];
            final photoId = proofPhoto is Map ? proofPhoto['\$oid'] : proofPhoto;

            return InkWell(
              onTap: () {
                if (proofPhoto != null) {
                  _showProofPhoto(proofPhoto);
                }
              },
              child: Container(
                color: bgColor,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          if (photoId != null)
                            const Icon(Icons.image, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: photoId != null ? Colors.blue : Colors.black87,
                                decoration: photoId != null ? TextDecoration.underline : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        _formatAmount(qty),
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        _formatAmount(unitPrice),
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        _formatAmount(subtotal),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          // Status and Total row
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              border: Border(top: BorderSide(color: Colors.red.shade300, width: 2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatusChip(
                  status,
                  onTap: (orderIdStr != null && orderIdStr.isNotEmpty)
                      ? () => _showStatusDialog([orderIdStr!], status)
                      : null,
                ),
                Text(
                  '₹${_formatAmount(totalAmount)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Text('Total Items: $grandCount', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        const Spacer(),
        Text(
          _formatAmount(grandTotal),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 20),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If we have selected a filtering branch, or just showing all
    // We compute displayed list
    final displayedReturns = _getDisplayedReturns();
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;

    Widget mainContent = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDateSelector(),
                  _toggleIcon(),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _buildBranchFilter(),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : displayedReturns.isEmpty
              ? const Center(child: Text('No return orders found'))
              : ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: displayedReturns.length,
            itemBuilder: (context, index) {
              final item = displayedReturns[index];
              return _buildReturnCard(item, isCombined: _combinedView);
            },
          ),
        ),
        // Footer (optional, grand total)
        if (grandCount > 0)
          Container(
            color: Colors.black,
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Returns: $grandCount',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  '₹${_formatAmount(grandTotal)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          )
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Return Orders'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // reset filters to default if needed or just refresh data
              if (widget.initialBranchId == null) {
                setState(() {
                  selectedBranchId = 'ALL';
                  _combinedView = true;
                });
              }
              _fetchReturnOrders();
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