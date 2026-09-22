import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/rtc/rtc_service.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// شاشة مكالمة الفيديو (مُصلحة ومحسنة)
/// ============================================================
class VideoCallScreen extends StatefulWidget {
  final DiscoveredDevice peer;
  final bool isCaller;

  const VideoCallScreen({
    super.key,
    required this.peer,
    required this.isCaller,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  RtcService? _rtc;
  StreamSubscription<RtcEvent>? _rtcEventSub;
  Timer? _durationTimer;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  Duration _elapsed = Duration.zero;
  bool _isEndingCall = false;

  // موضع النافذة المصغرة (PIP)
  Offset _pipPosition = const Offset(20, 80);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 1. تهيئة العارضين
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      if (!mounted) return;

      _rtc = context.read<RtcService>();

      // 2. ربط الـ streams
      _bindStreams();

      // 3. الاستماع لأحداث RTC
      _rtcEventSub = _rtc!.events.listen(_onRtcEvent);
      _rtc!.addListener(_onRtcChanged);

      // 4. إذا كنا المتصلين، ابدأ المكالمة
      if (widget.isCaller) {
        final ok = await _rtc!.startCall(
          peerDeviceId: widget.peer.deviceId,
          peerName: widget.peer.name,
          callType: AppConstants.callTypeVideo,
        );

        if (!ok && mounted) {
          _showErrorAndClose('تعذّر بدء مكالمة الفيديو');
          return;
        }

        _bindStreams();
      }

      // 5. مؤقت المدة
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
    
    // تنظيف الموارد بنظافة لمنع تسريب الذاكرة
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();

    super.dispose();
  }

  void _bindStreams() {
    final rtc = _rtc;
    if (rtc == null) return;

    if (rtc.localStream != null &&
        _localRenderer.srcObject != rtc.localStream) {
      setState(() {
        _localRenderer.srcObject = rtc.localStream;
      });
    }

    if (rtc.remoteStream != null &&
        _remoteRenderer.srcObject != rtc.remoteStream) {
      setState(() {
        _remoteRenderer.srcObject = rtc.remoteStream;
      });
    }
  }

  void _onRtcChanged() {
    _bindStreams();
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
      case RtcEventType.remoteStream:
        _bindStreams();
        break;

      case RtcEventType.callEnded:
        _handleCloseScreen();
        break;

      case RtcEventType.error:
        if (mounted) _showErrorAndClose('حدث خطأ في مكالمة الفيديو');
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
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // 1. الفيديو البعيد (ملء الشاشة)
              Positioned.fill(
                child: _buildRemoteVideo(rtc),
              ),

              // 2. الشريط العلوي للمعلومات
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopInfoBar(rtc),
              ),

              // 3. الفيديو المحلي (PIP - القابل للسحب)
              if (rtc.isVideoEnabled && _localRenderer.srcObject != null)
                Positioned(
                  left: _pipPosition.dx,
                  top: _pipPosition.dy,
                  child: _buildLocalVideo(size),
                ),

              // 4. أزرار التحكم السفلية
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildControls(rtc),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteVideo(RtcService rtc) {
    // الاعتماد المباشر على وجود srcObject لضمان عدم حجب العرض
    if (_remoteRenderer.srcObject == null) {
      return Container(
        color: const Color(0xFF0A1A1F),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 130,
                height: 130,
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
                    fontSize: 55,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.peer.name,
                style: const TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RTCVideoView(
      _remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      mirror: false,
    );
  }

  Widget _buildLocalVideo(Size screenSize) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          double newX = _pipPosition.dx + details.delta.dx;
          double newY = _pipPosition.dy + details.delta.dy;

          // تقييد حركة النافذة داخل أبعاد الشاشة
          newX = newX.clamp(10.0, screenSize.width - 120.0);
          newY = newY.clamp(60.0, screenSize.height - 240.0);

          _pipPosition = Offset(newX, newY);
        });
      },
      child: Container(
        width: 110,
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.6),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: RTCVideoView(
          _localRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          mirror: _rtc?.isFrontCamera ?? true,
        ),
      ),
    );
  }

  Widget _buildTopInfoBar(RtcService rtc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.75),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            iconSize: 20,
            onPressed: _endCall,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.peer.name,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _getStatusText(rtc),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(RtcService rtc) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: rtc.isMuted ? Icons.mic_off : Icons.mic,
                label: rtc.isMuted ? 'إلغاء الكتم' : 'كتم',
                active: rtc.isMuted,
                onTap: () => rtc.toggleMute(),
              ),
              _ControlButton(
                icon: rtc.isVideoEnabled
                    ? Icons.videocam
                    : Icons.videocam_off,
                label: rtc.isVideoEnabled ? 'إيقاف الفيديو' : 'تشغيل',
                active: !rtc.isVideoEnabled,
                onTap: () => rtc.toggleVideo(),
              ),
              _ControlButton(
                icon: Icons.cameraswitch,
                label: 'تبديل',
                active: false,
                onTap: () => rtc.switchCamera(),
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
          const SizedBox(height: 24),
          _HangupButton(onTap: _endCall),
        ],
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
          color: active ? Colors.white : Colors.white.withOpacity(0.18),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(
                icon,
                size: 26,
                color: active ? const Color(0xFF0A1A1F) : Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.85),
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
          padding: EdgeInsets.all(18),
          child: Icon(
            Icons.call_end,
            size: 32,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
