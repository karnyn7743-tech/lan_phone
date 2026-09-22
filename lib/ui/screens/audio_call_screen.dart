import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/rtc/rtc_service.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// شاشة المكالمة الصوتية (مُصلحة ومحمية)
/// ============================================================
class AudioCallScreen extends StatefulWidget {
  final DiscoveredDevice peer;
  final bool isCaller;

  const AudioCallScreen({
    super.key,
    required this.peer,
    required this.isCaller,
  });

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  RtcService? _rtc;
  StreamSubscription<RtcEvent>? _rtcEventSub;
  Timer? _durationTimer;

  Duration _elapsed = Duration.zero;
  bool _isEndingCall = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _rtc = context.read<RtcService>();

      // الاستماع لأحداث RTC وتغيرات الحالة
      _rtcEventSub = _rtc!.events.listen(_onRtcEvent);
      _rtc!.addListener(_onRtcChanged);

      // إذا كنا المتصلين، ابدأ المكالمة
      if (widget.isCaller) {
        final ok = await _rtc!.startCall(
          peerDeviceId: widget.peer.deviceId,
          peerName: widget.peer.name,
          callType: AppConstants.callTypeAudio,
        );

        if (!ok && mounted) {
          _showErrorAndClose('تعذّر بدء المكالمة الصوتية');
          return;
        }
      }

      // مؤقت حساب المدة
      _durationTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tickDuration(),
      );
    });
  }

  @override
  void dispose() {
    _rtcEventSub?.cancel();
    _rtc?.removeListener(_onRtcChanged);
    _durationTimer?.cancel();
    super.dispose();
  }

  void _onRtcChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _tickDuration() {
    final start = _rtc?.callStartedAt;
    if (start == null) return;

    final elapsed = DateTime.now().difference(start);
    if (elapsed.inSeconds != _elapsed.inSeconds && mounted) {
      setState(() => _elapsed = elapsed);
    }
  }

  void _onRtcEvent(RtcEvent event) {
    if (event.peerDeviceId != widget.peer.deviceId) return;

    switch (event.type) {
      case RtcEventType.callEnded:
        _handleCloseScreen();
        break;

      case RtcEventType.error:
        if (mounted) {
          _showErrorAndClose('حدث خطأ أثناء المكالمة');
        }
        break;

      default:
        break;
    }
  }

  void _handleCloseScreen() {
    if (_isEndingCall || !mounted) return;
    _isEndingCall = true;
    Navigator.of(context).pop();
  }

  Future<void> _endCall() async {
    if (_isEndingCall) return;
    _isEndingCall = true;
    await _rtc?.endCall();
    if (mounted) Navigator.of(context).pop();
  }

  void _showErrorAndClose(String message) {
    if (_isEndingCall) return;
    _isEndingCall = true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorColor,
      ),
    );

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  String _getStatusText(RtcService rtc) {
    switch (rtc.callState) {
      case AppConstants.callStateCalling:
        return 'جارٍ الاتصال...';
      case AppConstants.callStateRinging:
        return 'يرن...';
      case AppConstants.callStateConnecting:
        return 'جارٍ التوصيل...';
      case AppConstants.callStateConnected:
        return _formatDuration(_elapsed);
      case AppConstants.callStateDeclined:
        return 'تم رفض المكالمة';
      case AppConstants.callStateEnded:
        return 'انتهت المكالمة';
      default:
        return '';
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final rtc = context.watch<RtcService>();

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _endCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1A1F),
        body: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0F2A2E),
                  Color(0xFF0A1A1F),
                ],
              ),
            ),
            child: Column(
              children: [
                // معلومات الطرف الآخر
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.25),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.primaryColor.withOpacity(0.5),
                            width: 3,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          widget.peer.name.isNotEmpty
                              ? widget.peer.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 60,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        widget.peer.name,
                        style: const TextStyle(
                          fontSize: 28,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _getStatusText(rtc),
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.75),
                          letterSpacing: 0.5,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (rtc.callState == AppConstants.callStateCalling ||
                          rtc.callState == AppConstants.callStateRinging ||
                          rtc.callState == AppConstants.callStateConnecting)
                        const _PulsingDot(),
                    ],
                  ),
                ),

                // أزرار التحكم
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ControlButton(
                              icon: rtc.isMuted
                                  ? Icons.mic_off
                                  : Icons.mic,
                              label: rtc.isMuted ? 'إلغاء الكتم' : 'كتم',
                              active: rtc.isMuted,
                              onTap: () => rtc.toggleMute(),
                            ),
                            _ControlButton(
                              icon: rtc.isSpeakerOn
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              label: rtc.isSpeakerOn ? 'المكبر مفعل' : 'مكبر الصوت',
                              active: rtc.isSpeakerOn,
                              onTap: () => rtc.toggleSpeaker(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        _HangupButton(onTap: _endCall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active
              ? Colors.white
              : Colors.white.withOpacity(0.15),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(
                icon,
                size: 28,
                color: active
                    ? const Color(0xFF0A1A1F)
                    : Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
    );
  }
}

class _HangupButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HangupButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.errorColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Icon(
            Icons.call_end,
            size: 34,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final offset = (i * 0.2);
            final opacity = ((_controller.value - offset) % 1.0).clamp(0.3, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
