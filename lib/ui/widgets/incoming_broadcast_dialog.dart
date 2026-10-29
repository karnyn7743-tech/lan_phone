import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/broadcast_service.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// حوار استقبال دعوة بث
/// ------------------------------------------------
/// يُعرض للمستمع عند وصول دعوة من مُذيع
/// ============================================================
class IncomingBroadcastDialog extends StatefulWidget {
  final BroadcastEvent event;
  final Function(bool accept) onResult;

  const IncomingBroadcastDialog({
    super.key,
    required this.event,
    required this.onResult,
  });

  @override
  State<IncomingBroadcastDialog> createState() =>
      _IncomingBroadcastDialogState();
}

class _IncomingBroadcastDialogState extends State<IncomingBroadcastDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _handled = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // اهتزاز
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _accept() {
    if (_handled) return;
    _handled = true;
    HapticFeedback.lightImpact();
    widget.onResult(true);
    Navigator.of(context).pop();
  }

  void _reject() {
    if (_handled) return;
    _handled = true;
    HapticFeedback.lightImpact();
    widget.onResult(false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _reject();
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F2A2E),
                Color(0xFF051114),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.primaryColor.withOpacity(0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ============================================
              // === أيقونة نابضة ===
              // ============================================
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, child) {
                  final scale = 1.0 + (_pulseController.value * 0.1);
                  return Transform.scale(scale: scale, child: child);
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.5),
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.podcasts,
                    size: 48,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ============================================
              // === عنوان ===
              // ============================================
              const Text(
                'بث صوتي مباشر',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 8),

              // ============================================
              // === اسم المُذيع ===
              // ============================================
              Text(
                widget.event.peerName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'يدعوك للاستماع إلى بثه الصوتي',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.6),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 28),

              // ============================================
              // === أزرار ===
              // ============================================
              Row(
                children: [
                  // رفض
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _reject,
                      icon: const Icon(Icons.close),
                      label: const Text('رفض'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withOpacity(0.3),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // قبول
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _accept,
                      icon: const Icon(Icons.headphones),
                      label: const Text('استماع'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
