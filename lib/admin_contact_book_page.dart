import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_call_history_service.dart';
import 'admin_chat_page.dart';
import 'live_call_screen.dart';

const String _chatApiBaseUrl = 'https://admin.theblackforestcakes.com/api';

enum ContactBookTab {
  contacts,
  allCalls,
  missed,
  received,
}

class ContactItem {
  final String userId;
  final String employeeId;
  final String name;
  final String role;
  final String? phone;
  final String? email;
  final String? branchName;

  const ContactItem({
    required this.userId,
    required this.employeeId,
    required this.name,
    required this.role,
    this.phone,
    this.email,
    this.branchName,
  });

  bool get isWaiter => role.trim().toLowerCase() == 'waiter';

  static ContactItem? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final userId = _relId(json['id'] ?? json['_id']);
    final employee = json['employee'];
    final employeeId = _relId(employee is Map ? (employee['id'] ?? employee['_id']) : employee) ?? userId;

    String? name;
    if (employee is Map && employee['name'] != null && employee['name'].toString().trim().isNotEmpty) {
      name = employee['name'].toString().trim();
    } else if (json['name'] != null && json['name'].toString().trim().isNotEmpty) {
      name = json['name'].toString().trim();
    } else if (json['email'] != null && json['email'].toString().trim().isNotEmpty) {
      name = json['email'].toString().trim();
    }

    if (userId == null || name == null || name.isEmpty) return null;

    String? phone;
    if (employee is Map) {
      phone = employee['phone']?.toString().trim() ?? employee['mobile']?.toString().trim();
    }
    phone ??= json['phone']?.toString().trim() ?? json['mobile']?.toString().trim();

    String? branch;
    if (employee is Map && employee['branch'] != null) {
      final b = employee['branch'];
      branch = b is Map ? b['name']?.toString() : b.toString();
    } else if (json['branch'] != null) {
      final b = json['branch'];
      branch = b is Map ? b['name']?.toString() : b.toString();
    }

    return ContactItem(
      userId: userId,
      employeeId: employeeId ?? userId,
      name: name,
      role: json['role']?.toString().trim() ?? 'Staff',
      phone: (phone == null || phone.isEmpty) ? null : phone,
      email: json['email']?.toString().trim(),
      branchName: (branch == null || branch.isEmpty) ? null : branch,
    );
  }

  static String? _relId(dynamic val) {
    if (val == null) return null;
    if (val is String && val.trim().isNotEmpty) return val.trim();
    if (val is Map) {
      final id = val['id'] ?? val['_id'];
      if (id != null && id.toString().trim().isNotEmpty) return id.toString().trim();
    }
    return null;
  }
}

class AdminContactBookPage extends StatefulWidget {
  final ContactBookTab initialTab;
  const AdminContactBookPage({
    super.key,
    this.initialTab = ContactBookTab.contacts,
  });

  @override
  State<AdminContactBookPage> createState() => _AdminContactBookPageState();
}

class _AdminContactBookPageState extends State<AdminContactBookPage> {
  late ContactBookTab _activeTab;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoadingContacts = true;
  String? _contactLoadError;
  List<ContactItem> _contacts = [];

  bool _isLoadingHistory = true;
  List<AdminCallLogEntry> _history = [];

  String _selectedRoleFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _loadContacts();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _readToken() async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token != null && token.trim().isNotEmpty) return token.trim();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? prefs.getString('auth_token');
      if (token != null && token.trim().isNotEmpty) return token.trim();
    } catch (_) {}
    return null;
  }

  Future<void> _loadContacts({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoadingContacts = true;
        _contactLoadError = null;
      });
    }

    try {
      final token = await _readToken();
      if (token == null) {
        throw Exception('Session expired. Please log in again.');
      }

      final res = await http.get(
        Uri.parse('$_chatApiBaseUrl/users?limit=3000&depth=1&sort=name'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) {
        throw Exception('Failed to load contacts (${res.statusCode})');
      }

      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final docs = (decoded is Map ? decoded['docs'] : null) as List? ?? [];

      final list = <ContactItem>[];
      for (final doc in docs) {
        final c = ContactItem.fromJson(doc);
        if (c != null) {
          list.add(c);
        }
      }

      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _contacts = list;
        _isLoadingContacts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contactLoadError = e.toString().replaceFirst('Exception: ', '');
        _isLoadingContacts = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    try {
      final history = await AdminCallHistoryService.getHistory();
      if (!mounted) return;
      setState(() {
        _history = history;
        _isLoadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  List<ContactItem> get _filteredContacts {
    final q = _searchController.text.trim().toLowerCase();
    return _contacts.where((c) {
      if (_selectedRoleFilter != 'ALL' &&
          c.role.trim().toUpperCase() != _selectedRoleFilter.toUpperCase()) {
        return false;
      }
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.role.toLowerCase().contains(q) ||
          (c.phone ?? '').toLowerCase().contains(q) ||
          (c.branchName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  List<AdminCallLogEntry> get _filteredHistory {
    final q = _searchController.text.trim().toLowerCase();
    return _history.where((entry) {
      // Filter by tab
      if (_activeTab == ContactBookTab.missed && !entry.isMissed) {
        return false;
      }
      if (_activeTab == ContactBookTab.received && !entry.isConnected) {
        return false;
      }
      if (q.isEmpty) return true;
      return entry.name.toLowerCase().contains(q) ||
          entry.role.toLowerCase().contains(q) ||
          (entry.phone ?? '').toLowerCase().contains(q);
    }).toList();
  }

  void _initiateCall(String userId, String name, String role) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LiveCallScreen(
          waiterUserId: userId,
          waiterName: name,
          waiterRole: role,
        ),
      ),
    ).then((_) => _loadHistory());
  }

  String _formatDateGroup(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('dd MMM yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final missedCount = _history.where((e) => e.isMissed).length;
    final receivedCount = _history.where((e) => e.isConnected).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF07213A),
        foregroundColor: Colors.white,
        title: const Text(
          'Contact Book & Calls',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _loadContacts();
              _loadHistory();
            },
          ),
          if (_activeTab != ContactBookTab.contacts && _history.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (val) async {
                if (val == 'clear') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear Call History?'),
                      content: const Text('All local call records will be cleared permanently.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Clear', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await AdminCallHistoryService.clearHistory();
                    await _loadHistory();
                  }
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Clear call history', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // TOP SEGMENT BUTTONS: Contacts | Call History | Missed | Received
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTopTabButton(
                    tab: ContactBookTab.contacts,
                    label: 'Contacts',
                    icon: Icons.contacts_rounded,
                    count: _contacts.isNotEmpty ? _contacts.length : null,
                  ),
                  const SizedBox(width: 8),
                  _buildTopTabButton(
                    tab: ContactBookTab.allCalls,
                    label: 'Call History',
                    icon: Icons.history_rounded,
                    count: _history.isNotEmpty ? _history.length : null,
                  ),
                  const SizedBox(width: 8),
                  _buildTopTabButton(
                    tab: ContactBookTab.missed,
                    label: 'Missed',
                    icon: Icons.call_missed_rounded,
                    count: missedCount > 0 ? missedCount : null,
                    countColor: Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  _buildTopTabButton(
                    tab: ContactBookTab.received,
                    label: 'Received',
                    icon: Icons.call_received_rounded,
                    count: receivedCount > 0 ? receivedCount : null,
                    countColor: const Color(0xFF059669),
                  ),
                ],
              ),
            ),
          ),

          // SEARCH BAR & ROLE CHIPS
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _activeTab == ContactBookTab.contacts
                        ? 'Search contacts by name, role, phone...'
                        : 'Search call records...',
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 22),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                if (_activeTab == ContactBookTab.contacts) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildRoleChip('ALL', 'All'),
                        _buildRoleChip('WAITER', 'Waiters'),
                        _buildRoleChip('CASHIER', 'Cashiers'),
                        _buildRoleChip('KITCHEN', 'Kitchen'),
                        _buildRoleChip('MANAGER', 'Managers'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // MAIN BODY
          Expanded(
            child: _activeTab == ContactBookTab.contacts
                ? _buildContactsList()
                : _buildHistoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabButton({
    required ContactBookTab tab,
    required String label,
    required IconData icon,
    int? count,
    Color? countColor,
  }) {
    final isSelected = _activeTab == tab;

    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = tab;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF07213A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF07213A) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF07213A).withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFF475569),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF1E293B),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : (countColor ?? const Color(0xFF64748B)).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : (countColor ?? const Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoleChip(String roleKey, String label) {
    final isSelected = _selectedRoleFilter == roleKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _selectedRoleFilter = roleKey;
          });
        },
        backgroundColor: const Color(0xFFF8FAFC),
        selectedColor: const Color(0xFF0F766E).withValues(alpha: 0.15),
        labelStyle: TextStyle(
          color: isSelected ? const Color(0xFF0F766E) : const Color(0xFF64748B),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        side: BorderSide(
          color: isSelected ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
        ),
      ),
    );
  }

  // CONTACTS LIST
  Widget _buildContactsList() {
    if (_isLoadingContacts) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF07213A)));
    }

    if (_contactLoadError != null && _contacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                _contactLoadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadContacts(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF07213A),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final contacts = _filteredContacts;
    if (contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_rounded, size: 56, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              _searchController.text.isEmpty
                  ? 'No contacts found'
                  : 'No contacts match "${_searchController.text}"',
              style: const TextStyle(fontSize: 15, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadContacts(showLoader: false),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        itemCount: contacts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final c = contacts[index];
          final isWaiter = c.isWaiter;

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: isWaiter
                    ? const Color(0xFFEAF8F1)
                    : const Color(0xFFE0F2FE),
                foregroundColor: isWaiter
                    ? const Color(0xFF059669)
                    : const Color(0xFF0284C7),
                child: Text(
                  c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isWaiter
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isWaiter
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Text(
                      c.role.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isWaiter
                            ? const Color(0xFF15803D)
                            : const Color(0xFF475569),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (c.phone != null && c.phone!.isNotEmpty) ...[
                      const Icon(Icons.phone_iphone_rounded, size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(
                        c.phone!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (c.branchName != null && c.branchName!.isNotEmpty) ...[
                      const Icon(Icons.storefront_rounded, size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          c.branchName!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // DIRECT CALL BUTTON
                  Material(
                    color: isWaiter
                        ? const Color(0xFF10B981)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () {
                        if (isWaiter) {
                          _initiateCall(c.userId, c.name, c.role);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Live calling is active for Waiters. (${c.name} is ${c.role})'),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Icon(
                          Icons.call_rounded,
                          size: 19,
                          color: isWaiter ? Colors.white : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // CHAT BUTTON
                  Material(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AdminChatPage(),
                          ),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(9),
                        child: Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 19,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // CALL HISTORY LIST (All Calls / Missed / Received)
  Widget _buildHistoryList() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF07213A)));
    }

    final history = _filteredHistory;
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _activeTab == ContactBookTab.missed
                  ? Icons.phone_missed_rounded
                  : Icons.phone_callback_rounded,
              size: 56,
              color: const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            Text(
              _activeTab == ContactBookTab.missed
                  ? 'No missed calls recorded'
                  : (_activeTab == ContactBookTab.received
                      ? 'No received calls recorded'
                      : 'No call history yet'),
              style: const TextStyle(fontSize: 15, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Call staff directly from the Contacts tab.',
              style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    // Group history entries by Date
    final widgets = <Widget>[];
    String? lastGroup;

    for (final entry in history) {
      final callTime = entry.callTime ?? DateTime.now();
      final group = _formatDateGroup(callTime);

      if (group != lastGroup) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              group,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        );
        lastGroup = group;
      }

      widgets.add(_buildHistoryTile(entry, callTime));
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: widgets,
      ),
    );
  }

  Widget _buildHistoryTile(AdminCallLogEntry entry, DateTime callTime) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (entry.isConnected) {
      statusColor = const Color(0xFF059669);
      statusIcon = entry.isOutgoing
          ? Icons.call_made_rounded
          : Icons.call_received_rounded;
      statusText = entry.durationSeconds > 0
          ? 'Connected • ${entry.formattedDuration}'
          : 'Answered';
    } else if (entry.isDeclined) {
      statusColor = Colors.red.shade700;
      statusIcon = Icons.call_end_rounded;
      statusText = 'Declined';
    } else {
      statusColor = Colors.redAccent;
      statusIcon = Icons.call_missed_rounded;
      statusText = entry.status.toLowerCase() == 'offline'
          ? 'Offline'
          : (entry.status.toLowerCase() == 'busy' ? 'Busy' : 'Missed');
    }

    final timeStr = DateFormat('h:mm a').format(callTime);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                entry.role.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 6),
              const Text('•', style: TextStyle(color: Color(0xFF94A3B8))),
              const SizedBox(width: 6),
              Text(
                timeStr,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        trailing: Material(
          color: const Color(0xFF10B981),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () {
              _initiateCall(entry.userId, entry.name, entry.role);
            },
            child: const Padding(
              padding: EdgeInsets.all(9),
              child: Icon(
                Icons.call_rounded,
                size: 19,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
