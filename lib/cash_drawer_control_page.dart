import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import 'widgets/app_drawer.dart';

class CashDrawerControlPage extends StatefulWidget {
  const CashDrawerControlPage({super.key});

  @override
  State<CashDrawerControlPage> createState() => _CashDrawerControlPageState();
}

class _CashDrawerControlPageState extends State<CashDrawerControlPage> {
  List<dynamic> _branches = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedCompanyFilter = 'ALL';
  List<String> _companies = [];
  String? _updatingBranchId;
  String? _token;
  bool _isAccountantDrawerEnabled = false;
  bool _isUpdatingAccountantDrawer = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<String?> _getToken() async {
    if (_token != null) return _token;
    const storage = FlutterSecureStorage();
    _token = await storage.read(key: 'token');
    return _token;
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      final res = await ApiService.get('/branches?limit=1000&depth=1&sort=name', token: token);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = (data['docs'] as List?) ?? [];
        
        final Set<String> companyNames = {};
        for (var b in docs) {
          final comp = b['company'];
          final compName = comp is Map ? (comp['name'] ?? comp['title'] ?? '') : '';
          if (compName.toString().trim().isNotEmpty) {
            companyNames.add(compName.toString().trim());
          }
        }

        if (mounted) {
          setState(() {
            _branches = docs;
            _companies = companyNames.toList()..sort();
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load branches (HTTP ${res.statusCode})')),
          );
        }
      }

      // Fetch Accountant drawer access state
      try {
        final accRes = await ApiService.get('/branches/toggle-cashdrawer-access?branchId=accountant', token: token);
        if (accRes.statusCode == 200) {
          final accData = jsonDecode(accRes.body);
          if (mounted) {
            setState(() {
              _isAccountantDrawerEnabled = accData['isCashDrawerEnabled'] == true;
            });
          }
        }
      } catch (e) {
        debugPrint('Error fetching accountant drawer status: $e');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading branches: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleCashDrawerAccess(String branchId, bool newValue) async {
    final int idx = _branches.indexWhere((b) => (b['id'] ?? b['_id']).toString() == branchId);
    if (idx == -1) return;

    final oldStatus = _branches[idx]['isCashDrawerEnabled'] == true;

    // Optimistic UI update
    setState(() {
      _updatingBranchId = branchId;
      _branches[idx]['isCashDrawerEnabled'] = newValue;
    });

    try {
      final token = await _getToken();
      
      // 1. Try dedicated endpoint first
      var res = await ApiService.post(
        '/branches/toggle-cashdrawer-access',
        token: token,
        body: {
          'branchId': branchId,
          'enabled': newValue,
        },
      );

      // 2. Fallback to PATCH /branches/:id if not 200
      if (res.statusCode == 404 || res.statusCode != 200) {
        res = await ApiService.patch(
          '/branches/$branchId',
          token: token,
          body: {
            'isCashDrawerEnabled': newValue,
          },
        );
      }

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newValue ? 'Cash drawer access enabled' : 'Cash drawer access locked'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
              backgroundColor: newValue ? const Color(0xFF059669) : const Color(0xFF334155),
            ),
          );
        }
      } else {
        throw Exception('Status code: ${res.statusCode}');
      }
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          _branches[idx]['isCashDrawerEnabled'] = oldStatus;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update cash drawer: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingBranchId = null);
      }
    }
  }

  Future<void> _toggleAccountantDrawer(bool newValue) async {
    setState(() {
      _isUpdatingAccountantDrawer = true;
      _isAccountantDrawerEnabled = newValue;
    });

    try {
      final token = await _getToken();
      final res = await ApiService.post(
        '/branches/toggle-cashdrawer-access',
        token: token,
        body: {
          'branchId': 'accountant',
          'enabled': newValue,
        },
      );

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newValue
                  ? 'Accountant cash drawer access enabled'
                  : 'Accountant cash drawer access locked'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: newValue ? const Color(0xFF059669) : const Color(0xFF334155),
            ),
          );
        }
      } else {
        throw Exception('Status ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAccountantDrawerEnabled = !newValue;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update accountant cash drawer: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAccountantDrawer = false);
      }
    }
  }

  List<dynamic> get _filteredBranches {
    return _branches.where((b) {
      final String name = (b['name'] ?? '').toString().toLowerCase();
      final comp = b['company'];
      final String compName = (comp is Map ? (comp['name'] ?? comp['title'] ?? '') : '').toString().toLowerCase();

      final matchesSearch = _searchQuery.isEmpty ||
          name.contains(_searchQuery.toLowerCase()) ||
          compName.contains(_searchQuery.toLowerCase());

      final matchesCompany = _selectedCompanyFilter == 'ALL' ||
          (comp is Map && (comp['name'] ?? comp['title'] ?? '') == _selectedCompanyFilter);

      return matchesSearch && matchesCompany;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: isDesktop ? null : const Drawer(child: SafeArea(child: AppDrawer())),
      body: isDesktop
          ? Row(
              children: [
                const SizedBox(
                  width: 260,
                  child: AppDrawer(),
                ),
                VerticalDivider(width: 1, color: Colors.grey[200]),
                Expanded(
                  child: _buildBody(context, isDesktop),
                ),
              ],
            )
          : _buildBody(context, isDesktop),
    );
  }

  Widget _buildBody(BuildContext context, bool isDesktop) {
    final filtered = _filteredBranches;
    final int totalCount = _branches.length;
    final int enabledCount = _branches.where((b) => b['isCashDrawerEnabled'] == true).length;
    final int lockedCount = totalCount - enabledCount;

    return RefreshIndicator(
      onRefresh: _loadBranches,
      color: const Color(0xFF0B355B),
      child: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, isDesktop, totalCount, enabledCount, lockedCount),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: _buildAccountantDrawerCard(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _buildFilterSection(),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF0B355B)),
              ),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off_rounded, size: 54, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      _searchQuery.isEmpty ? 'No branches found' : 'No matching branches for "$_searchQuery"',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final branch = filtered[index];
                    return _buildBranchTile(branch);
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    bool isDesktop,
    int totalCount,
    int enabledCount,
    int lockedCount,
  ) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 160,
      backgroundColor: const Color(0xFF07213A),
      leading: isDesktop
          ? null
          : Builder(
              builder: (btnContext) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                onPressed: () => Scaffold.of(btnContext).openDrawer(),
              ),
            ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          tooltip: 'Refresh',
          onPressed: _loadBranches,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF07213A), Color(0xFF0B355B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cash Drawer Control',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            'Branch-wise Cash Drawer Access Management',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _buildHeaderStatBadge('Total', totalCount.toString(), Colors.blueGrey[100]!),
                      const SizedBox(width: 8),
                      _buildHeaderStatBadge('Active', enabledCount.toString(), const Color(0xFF34D399)),
                      const SizedBox(width: 8),
                      _buildHeaderStatBadge('Locked', lockedCount.toString(), const Color(0xFFF87171)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderStatBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountantDrawerCard() {
    final bool isEnabled = _isAccountantDrawerEnabled;
    final bool isUpdating = _isUpdatingAccountantDrawer;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isEnabled
              ? [const Color(0xFF064E3B), const Color(0xFF047857)]
              : [const Color(0xFF1E293B), const Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isEnabled ? const Color(0xFF059669) : Colors.black).withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isEnabled ? Icons.lock_open_rounded : Icons.lock_rounded,
                size: 24,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Accountant Cash Drawer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ACCOUNT ROLE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isEnabled
                        ? 'Accountant in Tracker App is permitted to trigger drawer opening'
                        : 'Accountant cash drawer access is locked by Owner',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (isUpdating)
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            else
              Transform.scale(
                scale: 1.1,
                child: Switch(
                  value: isEnabled,
                  onChanged: _toggleAccountantDrawer,
                  activeColor: Colors.white,
                  activeTrackColor: const Color(0xFF34D399),
                  inactiveThumbColor: Colors.grey[400],
                  inactiveTrackColor: Colors.white.withOpacity(0.2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Column(
      children: [
        // Search bar
        TextField(
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          decoration: InputDecoration(
            hintText: 'Search by branch name or company...',
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => setState(() => _searchQuery = ''),
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0B355B), width: 1.5),
            ),
          ),
        ),
        if (_companies.isNotEmpty) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _companyFilterChip('ALL', 'All Companies'),
                ..._companies.map((c) => _companyFilterChip(c, c)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _companyFilterChip(String key, String label) {
    final bool isSelected = _selectedCompanyFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) setState(() => _selectedCompanyFilter = key);
        },
        selectedColor: const Color(0xFF0B355B),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF334155),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isSelected ? const Color(0xFF0B355B) : Colors.grey[300]!),
        ),
      ),
    );
  }

  Widget _buildBranchTile(dynamic branch) {
    final String id = (branch['id'] ?? branch['_id'] ?? '').toString();
    final String name = (branch['name'] ?? 'Unnamed Branch').toString();
    final comp = branch['company'];
    final String compName = (comp is Map ? (comp['name'] ?? comp['title'] ?? '') : '').toString();
    final bool isEnabled = branch['isCashDrawerEnabled'] == true;
    final bool isThisUpdating = _updatingBranchId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEnabled ? const Color(0xFF10B981).withOpacity(0.3) : Colors.grey[200]!,
          width: isEnabled ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isEnabled ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isEnabled ? Icons.lock_open_rounded : Icons.lock_rounded,
                size: 20,
                color: isEnabled ? const Color(0xFF059669) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (compName.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            compName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isEnabled
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isEnabled ? 'ENABLED' : 'LOCKED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: isEnabled ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isThisUpdating)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF059669)),
              )
            else
              Switch(
                value: isEnabled,
                onChanged: (val) => _toggleCashDrawerAccess(id, val),
                activeColor: const Color(0xFF059669),
                activeTrackColor: const Color(0xFFA7F3D0),
                inactiveThumbColor: Colors.grey[400],
                inactiveTrackColor: Colors.grey[200],
              ),
          ],
        ),
      ),
    );
  }
}
