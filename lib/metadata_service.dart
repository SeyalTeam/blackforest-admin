import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class MetadataService {
  static final MetadataService _instance = MetadataService._internal();
  factory MetadataService() => _instance;
  MetadataService._internal();

  Map<String, String> _branches = {};
  Map<String, String> _companies = {};
  Map<String, String> _users = {};
  Map<String, String> _departments = {};
  Map<String, String> _categories = {};

  bool _isLoaded = false;

  Map<String, String> get branches => _branches;
  Map<String, String> get companies => _companies;
  Map<String, String> get users => _users;
  Map<String, String> get departments => _departments;
  Map<String, String> get categories => _categories;

  /// Fetch all metadata with depth=0 and cache in memory
  Future<void> ensureLoaded(String token) async {
    if (_isLoaded && _branches.isNotEmpty) return;

    try {
      await Future.wait([
        fetchBranches(token),
        fetchCompanies(token),
        fetchUsers(token),
        fetchDepartments(token),
      ]);
      _isLoaded = true;
    } catch (e) {
      debugPrint('MetadataService preload error: $e');
    }
  }

  Future<Map<String, String>> fetchBranches(String token) async {
    if (_branches.isNotEmpty) return _branches;
    try {
      final res = await ApiService.get('/branches?limit=1000&depth=0', token: token);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];
        final Map<String, String> temp = {};
        for (var b in docs) {
          final id = b['id'] ?? b['_id'];
          final name = b['name'] ?? 'Unnamed Branch';
          if (id != null) temp[id.toString()] = name.toString();
        }
        _branches = temp;
      }
    } catch (e) {
      debugPrint('Error fetching branches: $e');
    }
    return _branches;
  }

  Future<Map<String, String>> fetchCompanies(String token) async {
    if (_companies.isNotEmpty) return _companies;
    try {
      final res = await ApiService.get('/companies?limit=1000&depth=0', token: token);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];
        final Map<String, String> temp = {};
        for (var c in docs) {
          final id = c['id'] ?? c['_id'];
          final name = c['name'] ?? 'Unnamed Company';
          if (id != null) temp[id.toString()] = name.toString();
        }
        _companies = temp;
      }
    } catch (e) {
      debugPrint('Error fetching companies: $e');
    }
    return _companies;
  }

  Future<Map<String, String>> fetchUsers(String token) async {
    if (_users.isNotEmpty) return _users;
    try {
      final res = await ApiService.get('/users?limit=2000&depth=0', token: token);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];
        final Map<String, String> temp = {};
        for (var u in docs) {
          final id = u['id'] ?? u['_id'];
          final name = u['name'] ?? u['email'] ?? 'Unnamed User';
          if (id != null) temp[id.toString()] = name.toString();
        }
        _users = temp;
      }
    } catch (e) {
      debugPrint('Error fetching users: $e');
    }
    return _users;
  }

  Future<Map<String, String>> fetchDepartments(String token) async {
    if (_departments.isNotEmpty) return _departments;
    try {
      final res = await ApiService.get('/departments?limit=1000&depth=0', token: token);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List docs = data['docs'] ?? [];
        final Map<String, String> temp = {};
        for (var d in docs) {
          final id = d['id'] ?? d['_id'];
          final name = d['name'] ?? 'Unnamed Department';
          if (id != null) temp[id.toString()] = name.toString();
        }
        _departments = temp;
      }
    } catch (e) {
      debugPrint('Error fetching departments: $e');
    }
    return _departments;
  }

  void clearCache() {
    _branches.clear();
    _companies.clear();
    _users.clear();
    _departments.clear();
    _categories.clear();
    _isLoaded = false;
  }
}
