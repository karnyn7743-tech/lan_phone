import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/services/ringtone_service.dart';
import '../theme/app_theme.dart';
import 'audio_call_screen.dart';
import 'video_call_screen.dart';

/// ============================================================
/// شاشة المكالمة الواردة (Fallback)
/// --------------------------------------------------------
/// ملاحظة: مع flutter_callkit_incoming، واجهة المكالمة
/// الواردة تُعرض عبر النظام مباشرة. هذه الشاشة احتياطية.
/// ============================================================
class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String peerDeviceId;
  final String peerName;
  final String callType;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.peerDeviceId,
    required this.peerName,
    required this.callType,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  // ============================================
  // === المراجع ===
  // ============================================
  RingtoneService? _ringtoneService; // ✅ جديد

  late AnimationController _pulseController;
  bool _isHandling = false;

  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // ✅ احفظ المرجع قبل postFrameCallback
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _ringtoneService = context.read<RingtoneService>();
      await _ringtoneService!.startRinging();
    });
  }

  @override
  void dispose() {
    // ✅ استخدم المرجع المحفوظ بدل context
    _ringtoneService?.stopRinging();
    _pulseController.dispose();
    super.dispose();
  }

  // ============================================
  // === القبول ===
  // ============================================

  Future<void> _accept() async {
    if (_isHandling) return;
    _isHandling = true;

    _ringtoneService?.stopRinging();

    final rtc = context.read<RtcService>();
    final ok = await rtc.acceptCall();

    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر قبول المكالمة'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    final discovery = context.read<DeviceDiscovery>();
    final peer = discovery.getDevice(widget.peerDeviceId);

    if (peer == null) {
      Navigator.of(context).pop();
      return;
    }

    final Widget screen = widget.callType == AppConstants.callTypeVideo
        ? VideoCallScreen(peer: peer, isCaller: false)
        : AudioCallScreen(peer: peer, isCaller: false);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  // ============================================
  // === الرفض ===
  // ============================================

  Future<void> _reject() async {
    if (_isHandling) return;
    _isHandling = true;

    _ringtoneService?.stopRinging();

    await context.read<RtcService>().rejectCall();

    if (mounted) Navigator.of(context).pop();
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == AppConstants.callTypeVideo;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop && !_isHandling) _reject();
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
                // ============================================
                // === معلومات المتصل ===
                // ============================================
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isVideo
                                  ? Icons.videocam
                                  : Icons.call_outlined,
                              size: 16,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isVideo
                                  ? 'مكالمة فيديو واردة'
                                  : 'مكالمة صوتية واردة',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale =
                              1.0 + (_pulseController.value * 0.08);
                          return Transform.scale(
                            scale: scale,
                            child: child,
                          );
                        },
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color:
                                AppTheme.primaryColor.withOpacity(0.25),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  AppTheme.primaryColor.withOpacity(0.5),
                              width: 3,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            widget.peerName.isNotEmpty
                                ? widget.peerName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 60,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      Text(
                        widget.peerName,
                        style: const TextStyle(
                          fontSize: 28,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'يتصل بك...',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withOpacity(0.7),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // ============================================
                // === أزرار القبول والرفض ===
                // ============================================
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ActionButton(
                              icon: Icons.call_end,
                              label: 'رفض',
                              color: AppTheme.errorColor,
                              onTap: _reject,
                            ),
                            _ActionButton(
                              icon: isVideo
                                  ? Icons.videocam
                                  : Icons.call,
                              label: 'قبول',
                              color: AppTheme.successColor,
                              onTap: _accept,
                            ),
                          ],
                        ),
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

// ============================================================
// === زر إجراء ===
// ============================================================
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, size: 34, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
