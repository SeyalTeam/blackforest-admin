import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_call_history_service.dart';
import 'live_call_screen.dart';

enum CallStatus {
  idle,
  connecting,
  ringing,
  connected,
  ended,
  declined,
  busy,
  offline,
  error,
}

class LiveCallService extends ChangeNotifier {
  static final LiveCallService instance = LiveCallService._internal();
  LiveCallService._internal();

  static const List<String> _wsHosts = [
    'admin.theblackforestcakes.com',
  ];
  static const String _wsPath = '/ws/v1';

  GlobalKey<NavigatorState>? _navigatorKey;
  void init(GlobalKey<NavigatorState> navKey) {
    _navigatorKey = navKey;
    connectSocket();
  }

  final AudioPlayer _ringtonePlayer = AudioPlayer();
  Timer? _reconnectTimer;

  bool _isIncoming = false;
  bool get isIncoming => _isIncoming;
  dynamic _pendingOfferSdp;

  String? _activeWsHost;
  String? get activeWsHost => _activeWsHost;

  io.WebSocket? _socket;
  StreamSubscription? _socketSub;
  Timer? _pingTimer;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  CallStatus _status = CallStatus.idle;
  CallStatus get status => _status;

  String? _currentCallId;
  String? get currentCallId => _currentCallId;

  String? _targetUserId;
  String? get targetUserId => _targetUserId;

  String? _targetUserName;
  String? get targetUserName => _targetUserName;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  Timer? _durationTimer;
  int _durationSeconds = 0;
  int get durationSeconds => _durationSeconds;

  String get formattedDuration {
    final minutes = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  Future<void> _startRingtone() async {
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(AssetSource('sounds/table.mp3'));
    } catch (e) {
      debugPrint('LiveCallService: error playing ringtone: $e');
    }
  }

  Future<void> _stopRingtone() async {
    try {
      await _ringtonePlayer.stop();
      await _ringtonePlayer.release();
    } catch (_) {}
  }

  void _showIncomingCallScreen({
    required String waiterUserId,
    required String waiterName,
  }) {
    void push() {
      final context = _navigatorKey?.currentContext;
      if (context == null) {
        debugPrint('LiveCallService: context is null, retrying incoming screen in 250ms...');
        Future.delayed(const Duration(milliseconds: 250), () {
          if (_status == CallStatus.ringing && _isIncoming) {
            _showIncomingCallScreen(
              waiterUserId: waiterUserId,
              waiterName: waiterName,
            );
          }
        });
        return;
      }

      bool isAlreadyOnScreen = false;
      Navigator.of(context).popUntil((route) {
        if (route.settings.name == 'admin_live_call_screen') {
          isAlreadyOnScreen = true;
        }
        return true;
      });

      if (!isAlreadyOnScreen) {
        _navigatorKey?.currentState?.push(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'admin_live_call_screen'),
            builder: (ctx) => LiveCallScreen(
              waiterUserId: waiterUserId,
              waiterName: waiterName,
              isIncoming: true,
            ),
          ),
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => push());
  }

  Future<String?> _readToken() async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token != null && token.trim().isNotEmpty) {
        return token.trim();
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? prefs.getString('auth_token') ?? prefs.getString('jwt');
      if (token != null && token.trim().isNotEmpty) {
        return token.trim();
      }
    } catch (_) {}
    return null;
  }

  String? _extractUserIdFromJwt(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decodedJson = jsonDecode(utf8.decode(base64Url.decode(payload)));
      return (decodedJson['id'] ?? decodedJson['_id'] ?? decodedJson['sub'] ?? decodedJson['userId'])?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('user_id') ?? prefs.getString('userId');
      if (id != null && id.trim().isNotEmpty) return id.trim();
    } catch (_) {}
    try {
      const storage = FlutterSecureStorage();
      final id = await storage.read(key: 'user_id');
      if (id != null && id.trim().isNotEmpty) return id.trim();
    } catch (_) {}
    try {
      final token = await _readToken();
      final id = _extractUserIdFromJwt(token);
      if (id != null && id.trim().isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', id.trim());
        return id.trim();
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _readUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('user_name') ?? prefs.getString('userName');
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    try {
      const storage = FlutterSecureStorage();
      final name = await storage.read(key: 'user_name');
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    return 'Super Admin';
  }

  Future<bool> connectSocket() async {
    if (_socket != null && _socket!.readyState == io.WebSocket.open) return true;
    try {
      final token = await _readToken();
      if (token == null || token.isEmpty) {
        debugPrint('LiveCallService: cannot connect socket, token is missing');
        return false;
      }

      for (final host in _wsHosts) {
        try {
          final uri = Uri(scheme: 'wss', host: host, path: _wsPath);
          debugPrint('LiveCallService: connecting to $uri ...');
          final socket = await io.WebSocket.connect(
            uri.toString(),
            headers: {'Authorization': 'Bearer $token'},
          ).timeout(const Duration(seconds: 6));

          _socket = socket;
          _activeWsHost = host;
          debugPrint('LiveCallService: connected successfully to $host');

          _socketSub?.cancel();
          _socketSub = _socket!.listen(
            _handleIncomingSocketFrame,
            onError: (err) {
              debugPrint('LiveCallService: socket error: $err');
              _closeSocket();
            },
            onDone: () {
              debugPrint('LiveCallService: socket closed');
              _closeSocket();
            },
          );

          _pingTimer?.cancel();
          _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
            _sendSocketMessage({'action': 'ping'});
          });

          return true;
        } catch (e) {
          debugPrint('LiveCallService: failed connecting to $host: $e');
        }
      }
    } catch (e) {
      debugPrint('LiveCallService: failed to connect socket: $e');
    }
    return false;
  }

  void _closeSocket() {
    _pingTimer?.cancel();
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () async {
      final token = await _readToken();
      if (token != null && token.isNotEmpty && (_socket == null || _socket!.readyState != io.WebSocket.open)) {
        debugPrint('LiveCallService: auto-reconnecting socket in background...');
        connectSocket();
      }
    });
  }

  void _sendSocketMessage(Map<String, dynamic> msg) {
    if (_socket != null && _socket!.readyState == io.WebSocket.open) {
      try {
        debugPrint('LiveCallService: sending socket message: ${msg['signalType'] ?? msg['action']}');
        _socket!.add(jsonEncode(msg));
      } catch (e) {
        debugPrint('LiveCallService: error sending message: $e');
      }
    } else {
      debugPrint('LiveCallService: cannot send message, socket is closed or null');
    }
  }

  Future<void> startCall({
    required String waiterUserId,
    required String waiterName,
  }) async {
    await _stopRingtone();
    _isIncoming = false;
    _status = CallStatus.connecting;
    _errorMessage = null;
    _targetUserId = waiterUserId;
    _targetUserName = waiterName;
    _currentCallId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    _durationSeconds = 0;
    _isMuted = false;
    _isSpeakerOn = false;
    notifyListeners();

    debugPrint('LiveCallService: startCall to $waiterName ($waiterUserId), callId: $_currentCallId');

    AdminCallHistoryService.recordCallStarted(
      callId: _currentCallId!,
      userId: waiterUserId,
      name: waiterName,
      role: 'Waiter',
      direction: 'outgoing',
    );

    final connected = await connectSocket();
    if (!connected || _socket == null || _socket!.readyState != io.WebSocket.open) {
      _status = CallStatus.error;
      _errorMessage = 'Could not connect to live call server. Please check internet connection.';
      notifyListeners();
      return;
    }

    try {
      _peerConnection = await createPeerConnection(_iceConfig);

      final constraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      for (final track in _localStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && _targetUserId != null) {
          _sendSocketMessage({
            'action': 'call_signal',
            'callId': _currentCallId,
            'signalType': 'ice_candidate',
            'targetUserId': _targetUserId,
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          });
        }
      };

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _applyAudioRouting();
          notifyListeners();
        }
      };

      _peerConnection!.onConnectionState = (state) {
        debugPrint('LiveCallService: connection state changed: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _onConnected();
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          if (_status == CallStatus.connected) {
            endCall();
          }
        }
      };

      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(offer);

      final adminUserId = (await _readUserId()) ?? '';
      final adminUserName = (await _readUserName()) ?? 'Super Admin';

      _sendSocketMessage({
        'action': 'call_signal',
        'callId': _currentCallId,
        'signalType': 'offer',
        'targetUserId': _targetUserId,
        'senderId': adminUserId,
        'callerUserId': adminUserId,
        'callerName': adminUserName,
        'callerRole': 'Super Admin',
        'sdp': offer.toMap(),
      });
    } catch (e) {
      debugPrint('LiveCallService: error starting call: $e');
      _status = CallStatus.error;
      _errorMessage = 'Could not start call: ${e.toString()}';
      notifyListeners();
      await _cleanupWebrtc();
    }
  }

  Future<void> acceptIncomingCall() async {
    await _stopRingtone();
    _status = CallStatus.connecting;
    _isSpeakerOn = false;
    notifyListeners();

    try {
      _peerConnection = await createPeerConnection(_iceConfig);

      final constraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      for (final track in _localStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && _targetUserId != null) {
          _sendSocketMessage({
            'action': 'call_signal',
            'callId': _currentCallId,
            'signalType': 'ice_candidate',
            'targetUserId': _targetUserId,
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          });
        }
      };

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _applyAudioRouting();
          notifyListeners();
        }
      };

      _peerConnection!.onConnectionState = (state) {
        debugPrint('LiveCallService: incoming peer connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _onConnected();
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          if (_status == CallStatus.connected) {
            endCall();
          }
        }
      };

      if (_pendingOfferSdp != null) {
        final sdpMap = _pendingOfferSdp is Map
            ? Map<String, dynamic>.from(_pendingOfferSdp)
            : jsonDecode(_pendingOfferSdp.toString());
        final description = RTCSessionDescription(
          sdpMap['sdp']?.toString() ?? '',
          sdpMap['type']?.toString() ?? 'offer',
        );
        await _peerConnection!.setRemoteDescription(description);

        final answer = await _peerConnection!.createAnswer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': 0,
        });
        await _peerConnection!.setLocalDescription(answer);

        _sendSocketMessage({
          'action': 'call_signal',
          'callId': _currentCallId,
          'signalType': 'answer',
          'targetUserId': _targetUserId,
          'sdp': answer.toMap(),
        });

        _onConnected();
      }
    } catch (e) {
      debugPrint('LiveCallService: error answering call: $e');
      _status = CallStatus.error;
      _errorMessage = 'Could not answer call: $e';
      notifyListeners();
      await _cleanupWebrtc();
    }
  }

  Future<void> declineIncomingCall() async {
    await _stopRingtone();
    if (_targetUserId != null && _currentCallId != null) {
      _sendSocketMessage({
        'action': 'call_signal',
        'callId': _currentCallId,
        'signalType': 'reject',
        'targetUserId': _targetUserId,
        'reason': 'Declined by Admin',
      });
    }
    if (_currentCallId != null) {
      AdminCallHistoryService.updateCallEnded(
        callId: _currentCallId!,
        status: 'declined',
        durationSeconds: 0,
      );
    }
    _status = CallStatus.declined;
    notifyListeners();
    _scheduleAutoCleanup();
  }

  void _handleIncomingSocketFrame(dynamic frame) {
    try {
      Map<String, dynamic>? data;
      if (frame is String) {
        data = jsonDecode(frame);
      } else if (frame is List<int>) {
        data = jsonDecode(utf8.decode(frame));
      }
      if (data == null) return;

      final eventType = data['eventType']?.toString();
      final action = data['action']?.toString();
      if (eventType != 'call_signal' && action != 'call_signal') return;

      final signalType = data['signalType']?.toString();
      final callId = data['callId']?.toString();
      final senderId = data['senderId']?.toString() ?? data['userId']?.toString();
      final senderName = data['senderName']?.toString() ?? data['callerName']?.toString() ?? 'Waiter';

      if (signalType == 'offer') {
        if (_status != CallStatus.idle) {
          if (senderId != null) {
            _sendSocketMessage({
              'action': 'call_signal',
              'callId': callId,
              'signalType': 'busy',
              'targetUserId': senderId,
            });
          }
          return;
        }

        _isIncoming = true;
        _currentCallId = callId ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
        _targetUserId = senderId;
        _targetUserName = senderName;
        _pendingOfferSdp = data['sdp'];
        _status = CallStatus.ringing;
        _durationSeconds = 0;
        _isMuted = false;
        _isSpeakerOn = false;
        notifyListeners();

        if (senderId != null) {
          _sendSocketMessage({
            'action': 'call_signal',
            'callId': _currentCallId,
            'signalType': 'ringing',
            'targetUserId': senderId,
          });
        }

        _startRingtone();

        AdminCallHistoryService.recordCallStarted(
          callId: _currentCallId!,
          userId: senderId ?? 'unknown',
          name: senderName,
          role: 'Waiter',
          direction: 'incoming',
        );

        _showIncomingCallScreen(
          waiterUserId: senderId ?? '',
          waiterName: senderName,
        );
        return;
      }

      if (_currentCallId != null && callId != null && _currentCallId != callId) {
        return;
      }

      switch (signalType) {
        case 'ringing':
          if (_status == CallStatus.connecting && !_isIncoming) {
            _status = CallStatus.ringing;
            notifyListeners();
          }
          break;

        case 'answer':
          _handleAnswer(data['sdp']);
          break;

        case 'ice_candidate':
          _handleIceCandidate(data['candidate']);
          break;

        case 'reject':
          _stopRingtone();
          _status = CallStatus.declined;
          _errorMessage = data['reason']?.toString() ?? 'Call declined';
          notifyListeners();
          if (_currentCallId != null) {
            AdminCallHistoryService.updateCallEnded(
              callId: _currentCallId!,
              status: 'declined',
              durationSeconds: _durationSeconds,
            );
          }
          _scheduleAutoCleanup();
          break;

        case 'user_offline':
          _stopRingtone();
          _status = CallStatus.offline;
          _errorMessage = data['message']?.toString() ?? 'Waiter is offline';
          notifyListeners();
          if (_currentCallId != null) {
            AdminCallHistoryService.updateCallEnded(
              callId: _currentCallId!,
              status: 'offline',
              durationSeconds: 0,
            );
          }
          _scheduleAutoCleanup();
          break;

        case 'busy':
          _stopRingtone();
          _status = CallStatus.busy;
          _errorMessage = 'Waiter is on another call';
          notifyListeners();
          if (_currentCallId != null) {
            AdminCallHistoryService.updateCallEnded(
              callId: _currentCallId!,
              status: 'busy',
              durationSeconds: 0,
            );
          }
          _scheduleAutoCleanup();
          break;

        case 'end':
          _stopRingtone();
          final wasRinging = _status == CallStatus.ringing;
          _status = CallStatus.ended;
          notifyListeners();
          if (_currentCallId != null) {
            AdminCallHistoryService.updateCallEnded(
              callId: _currentCallId!,
              status: _durationSeconds > 0
                  ? 'connected'
                  : (wasRinging ? 'missed' : 'ended'),
              durationSeconds: _durationSeconds,
            );
          }
          _scheduleAutoCleanup();
          break;
      }
    } catch (e) {
      debugPrint('LiveCallService: error parsing frame: $e');
    }
  }

  Future<void> _handleAnswer(dynamic sdpData) async {
    if (_peerConnection == null || sdpData == null) return;
    try {
      final sdpMap = sdpData is Map
          ? Map<String, dynamic>.from(sdpData)
          : jsonDecode(sdpData.toString());
      final description = RTCSessionDescription(
        sdpMap['sdp']?.toString() ?? '',
        sdpMap['type']?.toString() ?? 'answer',
      );
      await _peerConnection!.setRemoteDescription(description);
      _onConnected();
    } catch (e) {
      debugPrint('LiveCallService: error setting remote description: $e');
    }
  }

  Future<void> _handleIceCandidate(dynamic candidateData) async {
    if (_peerConnection == null || candidateData == null) return;
    try {
      final cMap = candidateData is Map
          ? Map<String, dynamic>.from(candidateData)
          : jsonDecode(candidateData.toString());
      final candidate = RTCIceCandidate(
        cMap['candidate']?.toString(),
        cMap['sdpMid']?.toString(),
        cMap['sdpMLineIndex'] as int?,
      );
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      debugPrint('LiveCallService: error adding ice candidate: $e');
    }
  }

  void _onConnected() {
    if (_status == CallStatus.connected) return;
    _status = CallStatus.connected;
    _isSpeakerOn = false;
    _durationSeconds = 0;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds++;
      notifyListeners();
    });

    if (_currentCallId != null) {
      AdminCallHistoryService.updateCallConnected(callId: _currentCallId!);
    }

    _applyAudioRouting();
    notifyListeners();
  }

  Future<void> _applyAudioRouting() async {
    try {
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
      Future.delayed(const Duration(milliseconds: 300), () async {
        try {
          await Helper.setSpeakerphoneOn(_isSpeakerOn);
        } catch (_) {}
      });
      Future.delayed(const Duration(milliseconds: 800), () async {
        try {
          await Helper.setSpeakerphoneOn(_isSpeakerOn);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('LiveCallService: _applyAudioRouting error: $e');
    }
  }

  Future<void> toggleMute() async {
    if (_localStream == null) return;
    _isMuted = !_isMuted;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    try {
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
      debugPrint('LiveCallService: speakerphone toggled to $_isSpeakerOn');
    } catch (e) {
      debugPrint('LiveCallService: setSpeakerphoneOn error: $e');
    }
    notifyListeners();
  }

  Future<void> endCall() async {
    await _stopRingtone();
    if (_targetUserId != null && _currentCallId != null) {
      _sendSocketMessage({
        'action': 'call_signal',
        'callId': _currentCallId,
        'signalType': 'end',
        'targetUserId': _targetUserId,
      });
    }
    if (_currentCallId != null) {
      AdminCallHistoryService.updateCallEnded(
        callId: _currentCallId!,
        status: _durationSeconds > 0 ? 'connected' : 'missed',
        durationSeconds: _durationSeconds,
      );
    }
    _status = CallStatus.ended;
    notifyListeners();
    await _cleanupWebrtc();
  }

  void _scheduleAutoCleanup() {
    Timer(const Duration(seconds: 2), () {
      _cleanupWebrtc();
    });
  }

  Future<void> _cleanupWebrtc() async {
    await _stopRingtone();
    _durationTimer?.cancel();
    _durationTimer = null;
    _pendingOfferSdp = null;
    _isIncoming = false;

    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}

    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      _remoteStream?.getTracks().forEach((track) => track.stop());
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;

    try {
      await _peerConnection?.close();
      await _peerConnection?.dispose();
    } catch (_) {}
    _peerConnection = null;

    _currentCallId = null;
    _targetUserId = null;
    notifyListeners();
  }
}
