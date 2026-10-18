import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminCallLogEntry {
  final String callId;
  final String userId;
  final String name;
  final String role;
  final String? phone;
  final String direction; // 'outgoing' | 'incoming'
  final String status; // 'connected' | 'missed' | 'declined' | 'busy' | 'offline'
  final int durationSeconds;
  final String timestampIso;

  const AdminCallLogEntry({
    required this.callId,
    required this.userId,
    required this.name,
    required this.role,
    this.phone,
    required this.direction,
    required this.status,
    required this.durationSeconds,
    required this.timestampIso,
  });

  bool get isConnected => status.toLowerCase() == 'connected';
  bool get isMissed =>
      status.toLowerCase() == 'missed' ||
      status.toLowerCase() == 'offline' ||
      status.toLowerCase() == 'busy';
  bool get isDeclined => status.toLowerCase() == 'declined';
  bool get isOutgoing => direction.toLowerCase() == 'outgoing';
  bool get isIncoming => direction.toLowerCase() == 'incoming';

  DateTime? get callTime => DateTime.tryParse(timestampIso)?.toLocal();

  String get formattedDuration {
    if (durationSeconds <= 0) return '00:00';
    final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  AdminCallLogEntry copyWith({
    String? callId,
    String? userId,
    String? name,
    String? role,
    String? phone,
    String? direction,
    String? status,
    int? durationSeconds,
    String? timestampIso,
  }) {
    return AdminCallLogEntry(
      callId: callId ?? this.callId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      timestampIso: timestampIso ?? this.timestampIso,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'callId': callId,
      'userId': userId,
      'name': name,
      'role': role,
      'phone': phone,
      'direction': direction,
      'status': status,
      'durationSeconds': durationSeconds,
      'timestampIso': timestampIso,
    };
  }

  static AdminCallLogEntry? fromJson(Map<String, dynamic> raw) {
    final callId = raw['callId']?.toString().trim() ?? '';
    final userId = raw['userId']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final role = raw['role']?.toString().trim() ?? 'Staff';
    final phone = raw['phone']?.toString().trim();
    final direction = raw['direction']?.toString().trim() ?? 'outgoing';
    final status = raw['status']?.toString().trim() ?? 'connected';
    final durationSeconds = (raw['durationSeconds'] as num?)?.toInt() ?? 0;
    final timestampIso = raw['timestampIso']?.toString().trim() ?? '';

    if (callId.isEmpty || timestampIso.isEmpty) {
      return null;
    }

    return AdminCallLogEntry(
      callId: callId,
      userId: userId,
      name: name.isEmpty ? 'Staff' : name,
      role: role,
      phone: (phone == null || phone.isEmpty) ? null : phone,
      direction: direction,
      status: status,
      durationSeconds: durationSeconds,
      timestampIso: timestampIso,
    );
  }
}

class AdminCallHistoryService {
  AdminCallHistoryService._();

  static const String _storageKey = 'admin_call_history_v1';
  static const int _maxEntries = 500;

  static const String _apiBaseUrl = 'https://admin.theblackforestcakes.com/api';

  static Future<List<AdminCallLogEntry>> getHistory({bool syncRemote = false, String? token}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      List<AdminCallLogEntry> list = <AdminCallLogEntry>[];
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final entry = AdminCallLogEntry.fromJson(Map<String, dynamic>.from(item));
            if (entry != null) {
              list.add(entry);
            }
          }
        }
      }
      list.sort((a, b) {
        final aTime = a.callTime?.millisecondsSinceEpoch ?? 0;
        final bTime = b.callTime?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

      if (syncRemote) {
        unawaited(syncHistoryFromBackend(token));
      }
      return list;
    } catch (_) {
      return <AdminCallLogEntry>[];
    }
  }

  /// Syncs permanent call history from MongoDB backend so it is NEVER lost upon reinstall.
  static Future<List<AdminCallLogEntry>> syncHistoryFromBackend(String? token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final myUserId = (prefs.getString('user_id') ?? prefs.getString('userId'))?.trim() ?? '';

      final localList = await getHistory(syncRemote: false);
      final Map<String, AdminCallLogEntry> merged = {
        for (final e in localList) e.callId: e,
      };

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final uri = Uri.parse('$_apiBaseUrl/call-logs?limit=300&sort=-createdAt&depth=0');
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final docs = (decoded is Map ? decoded['docs'] : null) as List? ?? [];

        for (final item in docs) {
          if (item is! Map) continue;
          final doc = Map<String, dynamic>.from(item);
          final callId = (doc['callId'] ?? doc['id'] ?? doc['_id'])?.toString().trim() ?? '';
          if (callId.isEmpty) continue;

          final callerId = doc['callerUserId']?.toString() ??
              (doc['callerUser'] is Map
                  ? doc['callerUser']['id']?.toString()
                  : doc['callerUser']?.toString()) ??
              '';
          final receiverId = doc['receiverUserId']?.toString() ??
              (doc['receiverUser'] is Map
                  ? doc['receiverUser']['id']?.toString()
                  : doc['receiverUser']?.toString()) ??
              '';

          final isCaller = myUserId.isNotEmpty && callerId == myUserId;
          final targetUserId = isCaller ? receiverId : callerId;
          final name = isCaller
              ? (doc['receiverName']?.toString().trim().isNotEmpty == true
                  ? doc['receiverName'].toString().trim()
                  : 'Staff')
              : (doc['callerName']?.toString().trim().isNotEmpty == true
                  ? doc['callerName'].toString().trim()
                  : 'Staff');
          final role = isCaller
              ? (doc['receiverRole']?.toString() ?? 'Staff')
              : (doc['callerRole']?.toString() ?? 'Staff');
          final phone = isCaller ? doc['receiverPhone']?.toString() : doc['callerPhone']?.toString();
          final direction = isCaller ? 'outgoing' : 'incoming';

          final rawStatus = (doc['status']?.toString() ?? '').toLowerCase();
          final status = (rawStatus == 'connected' || rawStatus == 'ended') ? 'connected' : rawStatus;
          final durationSec = (doc['durationSeconds'] as num?)?.toInt() ?? 0;
          final timestamp = doc['startedAt']?.toString() ??
              doc['createdAt']?.toString() ??
              DateTime.now().toIso8601String();

          final entry = AdminCallLogEntry(
            callId: callId,
            userId: targetUserId.isNotEmpty ? targetUserId : (isCaller ? receiverId : callerId),
            name: name,
            role: role,
            phone: phone,
            direction: direction,
            status: status.isEmpty ? 'missed' : status,
            durationSeconds: durationSec,
            timestampIso: timestamp,
          );

          if (merged.containsKey(callId)) {
            final existing = merged[callId]!;
            final bestDuration =
                durationSec > existing.durationSeconds ? durationSec : existing.durationSeconds;
            merged[callId] = existing.copyWith(
              name: name.isNotEmpty ? name : existing.name,
              role: role.isNotEmpty ? role : existing.role,
              phone: phone ?? existing.phone,
              status: existing.isConnected ? 'connected' : entry.status,
              durationSeconds: bestDuration,
            );
          } else {
            merged[callId] = entry;
          }
        }
      }

      final result = merged.values.toList();
      await _save(result);
      return result;
    } catch (e) {
      debugPrint('AdminCallHistoryService: syncHistoryFromBackend error: $e');
      return getHistory(syncRemote: false);
    }
  }

  static Future<void> syncCallToBackend({
    required String callId,
    required String targetUserId,
    required String targetName,
    required String targetRole,
    String? targetPhone,
    String status = 'ringing',
    int durationSeconds = 0,
    String direction = 'outgoing',
    String? token,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final myUserId = (prefs.getString('user_id') ?? prefs.getString('userId'))?.trim() ?? '';
      final myName = prefs.getString('user_name') ?? prefs.getString('name') ?? 'Super Admin';
      final myRole = prefs.getString('role') ?? 'superadmin';

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final uri = Uri.parse('$_apiBaseUrl/call-logs');
      final payload = {
        'callId': callId,
        'callerUserId': direction == 'outgoing' ? myUserId : targetUserId,
        'callerName': direction == 'outgoing' ? myName : targetName,
        'callerRole': direction == 'outgoing' ? myRole : targetRole,
        'receiverUserId': direction == 'outgoing' ? targetUserId : myUserId,
        'receiverName': direction == 'outgoing' ? targetName : myName,
        'receiverRole': direction == 'outgoing' ? targetRole : myRole,
        'receiverPhone': targetPhone,
        'status': status,
        'durationSeconds': durationSeconds,
        'startedAt': DateTime.now().toIso8601String(),
      };

      await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  static Future<void> _save(List<AdminCallLogEntry> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      list.sort((a, b) {
        final aTime = a.callTime?.millisecondsSinceEpoch ?? 0;
        final bTime = b.callTime?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
      final trimmed = list.length > _maxEntries ? list.sublist(0, _maxEntries) : list;
      await prefs.setString(
        _storageKey,
        jsonEncode(trimmed.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<void> recordCallStarted({
    required String callId,
    required String userId,
    required String name,
    required String role,
    String? phone,
    String direction = 'outgoing',
  }) async {
    final list = await getHistory();
    final existingIndex = list.indexWhere((e) => e.callId == callId);
    if (existingIndex >= 0) return;

    list.insert(
      0,
      AdminCallLogEntry(
        callId: callId,
        userId: userId,
        name: name,
        role: role,
        phone: phone,
        direction: direction,
        status: 'ringing',
        durationSeconds: 0,
        timestampIso: DateTime.now().toIso8601String(),
      ),
    );
    await _save(list);

    unawaited(
      syncCallToBackend(
        callId: callId,
        targetUserId: userId,
        targetName: name,
        targetRole: role,
        targetPhone: phone,
        status: 'ringing',
        direction: direction,
      ),
    );
  }

  static Future<void> updateCallConnected({required String callId}) async {
    final list = await getHistory();
    final index = list.indexWhere((e) => e.callId == callId);
    if (index < 0) return;

    list[index] = list[index].copyWith(status: 'connected');
    await _save(list);
  }

  static Future<void> updateCallEnded({
    required String callId,
    int? durationSeconds,
    String? status,
  }) async {
    final list = await getHistory();
    final index = list.indexWhere((e) => e.callId == callId);
    if (index < 0) return;

    final current = list[index];
    final derivedDuration = durationSeconds ?? current.durationSeconds;
    String finalStatus = status ?? current.status;

    if (finalStatus == 'ringing') {
      finalStatus = derivedDuration > 0 ? 'connected' : 'missed';
    }

    list[index] = current.copyWith(
      durationSeconds: derivedDuration,
      status: finalStatus,
    );
    await _save(list);

    unawaited(
      syncCallToBackend(
        callId: callId,
        targetUserId: current.userId,
        targetName: current.name,
        targetRole: current.role,
        targetPhone: current.phone,
        status: finalStatus,
        durationSeconds: derivedDuration,
        direction: current.direction,
      ),
    );
  }

  static Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }

  static Future<void> deleteEntry(String callId) async {
    final list = await getHistory();
    list.removeWhere((e) => e.callId == callId);
    await _save(list);
  }
}
