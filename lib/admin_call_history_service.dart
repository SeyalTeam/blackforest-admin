import 'dart:convert';
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

  static Future<List<AdminCallLogEntry>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.trim().isEmpty) {
        return <AdminCallLogEntry>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <AdminCallLogEntry>[];
      }
      final list = <AdminCallLogEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final entry = AdminCallLogEntry.fromJson(Map<String, dynamic>.from(item));
        if (entry != null) {
          list.add(entry);
        }
      }
      list.sort((a, b) {
        final aTime = a.callTime?.millisecondsSinceEpoch ?? 0;
        final bTime = b.callTime?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
      return list;
    } catch (_) {
      return <AdminCallLogEntry>[];
    }
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
