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
import 'live_call_service.dart';

const String _chatApiBaseUrl = 'https://admin.theblackforestcakes.com/api';

enum ContactBookTab {
  contacts,
  allCalls,
  dialed,
  received,
  missed,
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
  bool get isSupervisor => role.trim().toLowerCase() == 'supervisor';
  bool get isCashier => role.trim().toLowerCase() == 'cashier';
  bool get isKitchen => role.trim().toLowerCase() == 'kitchen' || role.trim().toLowerCase() == 'chef';
  bool get isDriver => role.trim().toLowerCase() == 'driver';
  bool get isManager => role.trim().toLowerCase() == 'manager' || role.trim().toLowerCase() == 'branch manager';

  static ContactItem? fromJson(dynamic json, {String? branchOverride}) {
    if (json is! Map<String, dynamic>) return null;

    final userId = _relId(json['id'] ?? json['_id']);
    final employee = json['employee'];
    final employeeId = _relId(employee is Map ? (employee['id'] ?? employee['_id']) : employee) ?? userId;

    // Filter out inactive or blocked employees
    if (json['loginBlocked'] == true) return null;
    if (json['status'] != null && json['status'].toString().trim().toLowerCase() == 'inactive') {
      return null;
    }
    if (json['isActive'] == false || json['active'] == false) return null;
    if (employee is Map) {
      final empStatus = employee['status']?.toString().trim().toLowerCase();
      if (empStatus != null && empStatus.isNotEmpty && empStatus != 'active') {
        return null;
      }
      if (employee['isActive'] == false || employee['active'] == false) {
        return null;
      }
    }

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
    if (branchOverride != null && branchOverride.trim().isNotEmpty) {
      branch = branchOverride.trim();
    } else if (employee is Map && employee['branch'] != null) {
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
    LiveCallService.instance.connectSocket();
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

      final prefs = await SharedPreferences.getInstance();
      final myUserId = (prefs.getString('user_id') ?? prefs.getString('userId'))?.trim() ?? '';
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 1. Fetch today's attendances to identify live punched-in staff
      final activePunchedInUserIds = <String>{};
      final userPunchedInBranchNameMap = <String, String>{};

      try {
        final attUrl = Uri.parse(
          '$_chatApiBaseUrl/attendance?where[dateString][equals]=$today&limit=500&depth=1',
        );
        final attRes = await http.get(
          attUrl,
          headers: {'Authorization': 'Bearer $token'},
        );

        if (attRes.statusCode == 200) {
          final attData = jsonDecode(utf8.decode(attRes.bodyBytes));
          final attDocs = (attData is Map ? attData['docs'] : null) as List? ?? [];

          for (final doc in attDocs) {
            if (doc is! Map) continue;
            final uId = ContactItem._relId(doc['user']);
            final empId = ContactItem._relId(doc['employee']);
            String? branchName;
            if (doc['loginBranch'] is Map) {
              branchName = doc['loginBranch']['name']?.toString().trim();
            }

            final activities = (doc['activities'] as List?) ?? [];
            final sessions = activities.where((a) {
              if (a is! Map) return false;
              final type = a['type']?.toString();
              return type == null || type == 'session';
            }).toList();

            bool isCurrentlyPunchedIn = false;
            if (sessions.isNotEmpty) {
              final lastSession = sessions.last as Map;
              final status = lastSession['status']?.toString().toLowerCase();
              final punchOut = lastSession['punchOut'];
              final hasNoPunchOut = punchOut == null || punchOut.toString().trim().isEmpty;
              isCurrentlyPunchedIn = (status != 'closed') && hasNoPunchOut;
            }

            if (isCurrentlyPunchedIn) {
              if (uId != null && uId.isNotEmpty) {
                activePunchedInUserIds.add(uId);
                if (branchName != null && branchName.isNotEmpty) {
                  userPunchedInBranchNameMap[uId] = branchName;
                }
              }
              if (empId != null && empId.isNotEmpty) {
                activePunchedInUserIds.add(empId);
                if (branchName != null && branchName.isNotEmpty) {
                  userPunchedInBranchNameMap[empId] = branchName;
                }
              }
            }
          }
        }
      } catch (attErr) {
        debugPrint('AdminContactBookPage: error fetching attendance: $attErr');
      }

      // 2. Fetch all staff users
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
        if (doc is! Map) continue;
        final uId = ContactItem._relId(doc['id'] ?? doc['_id']);
        final empId = ContactItem._relId(
          doc['employee'] is Map ? doc['employee']['id'] ?? doc['employee']['_id'] : doc['employee'],
        );

        if (uId == null || (myUserId.isNotEmpty && uId == myUserId)) continue;

        // REQUIREMENT: ONLY SHOW STAFF WHO ARE CURRENTLY PUNCHED IN!
        // If they did not punch in or if they have punched out, DO NOT SHOW THEM (they left the branch)
        final isPunchedIn = activePunchedInUserIds.contains(uId) ||
            (empId != null && activePunchedInUserIds.contains(empId));
        if (!isPunchedIn) continue;

        final branchOverride = userPunchedInBranchNameMap[uId] ??
            (empId != null ? userPunchedInBranchNameMap[empId] : null);

        final c = ContactItem.fromJson(doc, branchOverride: branchOverride);
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

  Future<void> _loadHistory({bool showLoader = true}) async {
    if (showLoader && mounted && _history.isEmpty) {
      setState(() {
        _isLoadingHistory = true;
      });
    }
    try {
      // 1. Load local cache immediately
      final cached = await AdminCallHistoryService.getHistory(syncRemote: false);
      if (mounted && cached.isNotEmpty) {
        setState(() {
          _history = cached;
          _isLoadingHistory = false;
        });
      }

      // 2. Fetch permanent call history from backend MongoDB
      final token = await _readToken();
      final remote = await AdminCallHistoryService.syncHistoryFromBackend(token);
      if (!mounted) return;
      setState(() {
        _history = remote;
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
      if (_selectedRoleFilter != 'ALL') {
        final r = c.role.trim().toUpperCase();
        final f = _selectedRoleFilter.toUpperCase();
        if (f == 'KITCHEN') {
          if (r != 'KITCHEN' && r != 'CHEF') return false;
        } else if (f == 'MANAGER') {
          if (r != 'MANAGER' && r != 'BRANCH MANAGER' && r != 'ADMIN') return false;
        } else if (r != f) {
          return false;
        }
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
      if (_activeTab == ContactBookTab.dialed && !entry.isDialed) {
        return false;
      }
      if (_activeTab == ContactBookTab.received && !entry.isReceived) {
        return false;
      }
      if (_activeTab == ContactBookTab.missed && !entry.isIncomingMissed) {
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
    final dialedCount = _history.where((e) => e.isDialed).length;
    final receivedCount = _history.where((e) => e.isReceived).length;
    final missedCount = _history.where((e) => e.isIncomingMissed).length;

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
          // TOP SEGMENT BUTTONS: Contacts | Call History | Dialed | Received | Missed
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
                    tab: ContactBookTab.dialed,
                    label: 'Dialed',
                    icon: Icons.call_made_rounded,
                    count: dialedCount > 0 ? dialedCount : null,
                    countColor: const Color(0xFF0284C7),
                  ),
                  const SizedBox(width: 8),
                  _buildTopTabButton(
                    tab: ContactBookTab.received,
                    label: 'Received',
                    icon: Icons.call_received_rounded,
                    count: receivedCount > 0 ? receivedCount : null,
                    countColor: const Color(0xFF059669),
                  ),
                  const SizedBox(width: 8),
                  _buildTopTabButton(
                    tab: ContactBookTab.missed,
                    label: 'Missed',
                    icon: Icons.call_missed_rounded,
                    count: missedCount > 0 ? missedCount : null,
                    countColor: Colors.redAccent,
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
                        _buildRoleChip('SUPERVISOR', 'Supervisors'),
                        _buildRoleChip('KITCHEN', 'Kitchen'),
                        _buildRoleChip('DRIVER', 'Drivers'),
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

  Color _roleBgColor(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'waiter') return const Color(0xFFDCFCE7);
    if (r == 'supervisor') return const Color(0xFFEDE9FE);
    if (r == 'driver') return const Color(0xFFFEF3C7);
    if (r == 'cashier') return const Color(0xFFE0F2FE);
    if (r == 'kitchen' || r == 'chef') return const Color(0xFFFFEDD5);
    if (r == 'manager' || r == 'branch manager') return const Color(0xFFFCE7F3);
    return const Color(0xFFF1F5F9);
  }

  Color _roleTextColor(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'waiter') return const Color(0xFF15803D);
    if (r == 'supervisor') return const Color(0xFF6D28D9);
    if (r == 'driver') return const Color(0xFFB45309);
    if (r == 'cashier') return const Color(0xFF0369A1);
    if (r == 'kitchen' || r == 'chef') return const Color(0xFFC2410C);
    if (r == 'manager' || r == 'branch manager') return const Color(0xFFBE185D);
    return const Color(0xFF475569);
  }

  Color _roleBorderColor(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'waiter') return const Color(0xFF86EFAC);
    if (r == 'supervisor') return const Color(0xFFDDD6FE);
    if (r == 'driver') return const Color(0xFFFDE68A);
    if (r == 'cashier') return const Color(0xFFBAE6FD);
    if (r == 'kitchen' || r == 'chef') return const Color(0xFFFED7AA);
    if (r == 'manager' || r == 'branch manager') return const Color(0xFFFBCFE8);
    return const Color(0xFFCBD5E1);
  }

  Color _avatarBgColor(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'waiter') return const Color(0xFFEAF8F1);
    if (r == 'supervisor') return const Color(0xFFF3E8FF);
    if (r == 'driver') return const Color(0xFFFEF3C7);
    if (r == 'cashier') return const Color(0xFFE0F2FE);
    if (r == 'kitchen' || r == 'chef') return const Color(0xFFFFEDD5);
    if (r == 'manager' || r == 'branch manager') return const Color(0xFFFCE7F3);
    return const Color(0xFFF1F5F9);
  }

  Color _avatarTextColor(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'waiter') return const Color(0xFF059669);
    if (r == 'supervisor') return const Color(0xFF7C3AED);
    if (r == 'driver') return const Color(0xFFD97706);
    if (r == 'cashier') return const Color(0xFF0284C7);
    if (r == 'kitchen' || r == 'chef') return const Color(0xFFEA580C);
    if (r == 'manager' || r == 'branch manager') return const Color(0xFFDB2777);
    return const Color(0xFF475569);
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
                  ? (_selectedRoleFilter == 'ALL'
                      ? 'No employees are currently punched in'
                      : 'No $_selectedRoleFilter staff currently punched in')
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
                backgroundColor: _avatarBgColor(c.role),
                foregroundColor: _avatarTextColor(c.role),
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
                      color: _roleBgColor(c.role),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _roleBorderColor(c.role),
                      ),
                    ),
                    child: Text(
                      c.role.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _roleTextColor(c.role),
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
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => _initiateCall(c.userId, c.name, c.role),
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
                  const SizedBox(width: 8),
                  // CHAT BUTTON
                  Material(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () {
                        AdminChatPage.openThreadForStaff(
                          context,
                          userId: c.userId,
                          employeeId: c.employeeId,
                          name: c.name,
                          role: c.role,
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
      return RefreshIndicator(
        onRefresh: _loadHistory,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.6,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _activeTab == ContactBookTab.dialed
                      ? Icons.call_made_rounded
                      : (_activeTab == ContactBookTab.missed
                          ? Icons.phone_missed_rounded
                          : Icons.phone_callback_rounded),
                  size: 56,
                  color: const Color(0xFF94A3B8),
                ),
                const SizedBox(height: 12),
                Text(
                  _activeTab == ContactBookTab.dialed
                      ? 'No dialed calls recorded'
                      : (_activeTab == ContactBookTab.missed
                          ? 'No missed calls recorded'
                          : (_activeTab == ContactBookTab.received
                              ? 'No received calls recorded'
                              : 'No call history yet')),
                  style: const TextStyle(fontSize: 15, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Call staff directly from the Contacts tab.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
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

    if (entry.isOutgoing) {
      statusIcon = Icons.call_made_rounded;
      if (entry.isConnected) {
        statusColor = const Color(0xFF059669);
        statusText = entry.durationSeconds > 0
            ? 'Dialed • ${entry.formattedDuration}'
            : 'Dialed • Answered';
      } else {
        statusColor = const Color(0xFF64748B);
        statusText = 'Dialed • No Answer';
      }
    } else if (entry.isConnected) {
      statusColor = const Color(0xFF059669);
      statusIcon = Icons.call_received_rounded;
      statusText = entry.durationSeconds > 0
          ? 'Answered • ${entry.formattedDuration}'
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
          backgroundColor: entry.isDialed && !entry.isConnected
              ? const Color(0xFFF1F5F9)
              : statusColor.withValues(alpha: 0.12),
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
