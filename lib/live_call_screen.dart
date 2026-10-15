import 'dart:async';
import 'package:flutter/material.dart';
import 'live_call_service.dart';

class LiveCallScreen extends StatefulWidget {
  final String waiterUserId;
  final String waiterName;
  final String waiterRole;

  const LiveCallScreen({
    super.key,
    required this.waiterUserId,
    required this.waiterName,
    this.waiterRole = 'Waiter',
  });

  @override
  State<LiveCallScreen> createState() => _LiveCallScreenState();
}

class _LiveCallScreenState extends State<LiveCallScreen>
    with SingleTickerProviderStateMixin {
  late final LiveCallService _callService;
  late final AnimationController _pulseController;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _callService = LiveCallService.instance;
    _callService.addListener(_handleCallStateChanged);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _callService.startCall(
        waiterUserId: widget.waiterUserId,
        waiterName: widget.waiterName,
      );
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _pulseController.dispose();
    _callService.removeListener(_handleCallStateChanged);
    super.dispose();
  }

  void _handleCallStateChanged() {
    if (!mounted) return;
    setState(() {});

    final status = _callService.status;
    if (status == CallStatus.ended ||
        status == CallStatus.declined ||
        status == CallStatus.offline ||
        status == CallStatus.busy ||
        status == CallStatus.error) {
      _autoCloseTimer?.cancel();
      _autoCloseTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  String _getStatusText() {
    switch (_callService.status) {
      case CallStatus.idle:
      case CallStatus.connecting:
        return 'Calling...';
      case CallStatus.ringing:
        return 'Ringing...';
      case CallStatus.connected:
        return _callService.formattedDuration;
      case CallStatus.ended:
        return 'Call ended';
      case CallStatus.declined:
        return 'Call declined';
      case CallStatus.busy:
        return 'Busy on another call';
      case CallStatus.offline:
        return 'Waiter is offline';
      case CallStatus.error:
        return _callService.errorMessage ?? 'Call failed';
    }
  }

  Color _getStatusColor() {
    switch (_callService.status) {
      case CallStatus.connected:
        return const Color(0xFF25D366);
      case CallStatus.ended:
      case CallStatus.declined:
      case CallStatus.error:
      case CallStatus.offline:
      case CallStatus.busy:
        return Colors.redAccent;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _callService.status;
    final isConnected = status == CallStatus.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1A20),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Security badge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.lock_outline, size: 14, color: Colors.white54),
                SizedBox(width: 6),
                Text(
                  'Live Audio Call • Blackforest Staff',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Waiter Name & Role
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                widget.waiterName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.waiterRole.toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF25D366),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),

            // Call Status / Duration
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _getStatusText(),
                key: ValueKey(_getStatusText()),
                style: TextStyle(
                  fontSize: isConnected ? 20 : 16,
                  fontWeight: isConnected ? FontWeight.w600 : FontWeight.normal,
                  color: _getStatusColor(),
                  letterSpacing: 0.4,
                ),
              ),
            ),

            const Spacer(),

            // Center Avatar with Pulse Effect
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = isConnected
                    ? 1.0
                    : 1.0 + (_pulseController.value * 0.08);
                final glow = isConnected ? 0.0 : _pulseController.value * 12.0;

                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A34), Color(0xFF122320)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF25D366).withOpacity(0.3),
                          blurRadius: glow + 10,
                          spreadRadius: glow * 0.5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        widget.waiterName.isNotEmpty
                            ? widget.waiterName.characters.first.toUpperCase()
                            : 'W',
                        style: const TextStyle(
                          fontSize: 54,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const Spacer(),

            // Audio waveform or live indicator when connected
            if (isConnected)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF25D366),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Live Audio Streaming',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Call Controls Row
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF182229),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Speakerphone Toggle
                  _ControlCircleButton(
                    icon: _callService.isSpeakerOn
                        ? Icons.volume_up
                        : Icons.volume_down_outlined,
                    label: 'Speaker',
                    isActive: _callService.isSpeakerOn,
                    onTap: _callService.status == CallStatus.connected
                        ? _callService.toggleSpeaker
                        : null,
                  ),

                  // Mic Mute Toggle
                  _ControlCircleButton(
                    icon: _callService.isMuted ? Icons.mic_off : Icons.mic,
                    label: _callService.isMuted ? 'Muted' : 'Mute',
                    isActive: _callService.isMuted,
                    activeColor: Colors.amber,
                    onTap: _callService.status == CallStatus.connected
                        ? _callService.toggleMute
                        : null,
                  ),

                  // End Call Button
                  GestureDetector(
                    onTap: () {
                      _callService.endCall();
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.redAccent,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.redAccent,
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'End',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ControlCircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ControlCircleButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.activeColor = const Color(0xFF25D366),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? activeColor.withOpacity(0.2)
                  : (enabled ? Colors.white.withOpacity(0.08) : Colors.white10),
              border: Border.all(
                color: isActive
                    ? activeColor
                    : (enabled ? Colors.white24 : Colors.transparent),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: isActive
                  ? activeColor
                  : (enabled ? Colors.white : Colors.white30),
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: enabled ? Colors.white70 : Colors.white30,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
