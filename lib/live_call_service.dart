import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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

  static const String _wsHost = 'blackforest.vseyal.com';
  static const String _wsPath = '/ws/v1';

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

  Future<String?> _readToken() async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token != null && token.trim().isNotEmpty) {
        return token.trim();
      }
    } catch (_) {}
    return null;
  }

  Future<void> connectSocket() async {
    if (_socket != null && _socket!.readyState == io.WebSocket.open) return;
    try {
      final token = await _readToken();
      if (token == null || token.isEmpty) return;

      final uri = Uri(scheme: 'wss', host: _wsHost, path: _wsPath);
      _socket = await io.WebSocket.connect(
        uri.toString(),
        headers: {'Authorization': 'Bearer $token'},
      );

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
    } catch (e) {
      debugPrint('LiveCallService: failed to connect socket: $e');
    }
  }

  void _closeSocket() {
    _pingTimer?.cancel();
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  void _sendSocketMessage(Map<String, dynamic> msg) {
    if (_socket != null && _socket!.readyState == io.WebSocket.open) {
      try {
        _socket!.add(jsonEncode(msg));
      } catch (e) {
        debugPrint('LiveCallService: error sending message: $e');
      }
    }
  }

  Future<void> startCall({
    required String waiterUserId,
    required String waiterName,
  }) async {
    _status = CallStatus.connecting;
    _errorMessage = null;
    _targetUserId = waiterUserId;
    _targetUserName = waiterName;
    _currentCallId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    _durationSeconds = 0;
    _isMuted = false;
    _isSpeakerOn = false;
    notifyListeners();

    await connectSocket();

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

      _sendSocketMessage({
        'action': 'call_signal',
        'callId': _currentCallId,
        'signalType': 'offer',
        'targetUserId': _targetUserId,
        'sdp': offer.toMap(),
        'callerName': 'Admin',
        'callerRole': 'admin',
      });
    } catch (e) {
      debugPrint('LiveCallService: error starting call: $e');
      _status = CallStatus.error;
      _errorMessage = 'Could not start call: ${e.toString()}';
      notifyListeners();
      await _cleanupWebrtc();
    }
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
      if (eventType != 'call_signal') return;

      final signalType = data['signalType']?.toString();
      final callId = data['callId']?.toString();

      if (_currentCallId != null && callId != null && _currentCallId != callId) {
        return;
      }

      switch (signalType) {
        case 'ringing':
          if (_status == CallStatus.connecting) {
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
          _status = CallStatus.declined;
          _errorMessage = data['reason']?.toString() ?? 'Call declined';
          notifyListeners();
          _scheduleAutoCleanup();
          break;

        case 'user_offline':
          _status = CallStatus.offline;
          _errorMessage = data['message']?.toString() ?? 'Waiter is offline';
          notifyListeners();
          _scheduleAutoCleanup();
          break;

        case 'busy':
          _status = CallStatus.busy;
          _errorMessage = 'Waiter is on another call';
          notifyListeners();
          _scheduleAutoCleanup();
          break;

        case 'end':
          _status = CallStatus.ended;
          notifyListeners();
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
    _durationSeconds = 0;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds++;
      notifyListeners();
    });
    notifyListeners();
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
    } catch (e) {
      debugPrint('LiveCallService: setSpeakerphoneOn error: $e');
    }
    notifyListeners();
  }

  Future<void> endCall() async {
    if (_targetUserId != null && _currentCallId != null) {
      _sendSocketMessage({
        'action': 'call_signal',
        'callId': _currentCallId,
        'signalType': 'end',
        'targetUserId': _targetUserId,
      });
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
    _durationTimer?.cancel();
    _durationTimer = null;

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
