import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/services/broadcast_service.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// شاشة البث الصوتي المباشر
/// ------------------------------------------------
/// تعرض واجهتين:
///   1) واجهة المُذيع (عند بدء بث جديد)
///   2) واجهة المستمع (عند الانضمام لبث)
/// ============================================================
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void dispose() {
    // إذا كانت الصفحة تُغلق أثناء بث أو استماع، اطرح سؤالًا
    super.dispose();
  }

  // ============================================
  // === بدء البث ===
  // ============================================

  Future<void> _startBroadcast() async {
    final granted = await _ensureMicPermission();
    if (!granted) return;

    final service = context.read<BroadcastService>();
    final ok = await service.startBroadcast();

    if (!mounted) return;

    if (!ok) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر بدء البث'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  Future<bool> _ensureMicPermission() async {
    try {
      final ok = await PermissionDialogHelper.ensureMic(context);
      return ok;
    } catch (e) {
      debugPrint('[Broadcast] mic permission error: $e');
      return false;
    }
  }

  // ============================================
  // === إيقاف البث ===
  // ============================================

  Future<void> _stopBroadcast() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.stop_circle_outlined,
          size: 40,
          color: AppTheme.errorColor,
        ),
        title: const Text('إنهاء البث'),
        content: const Text(
          'سيتم إيقاف البث فورًا وسيرجع كل المستمعين للشاشة الرئيسية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إنهاء'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await context.read<BroadcastService>().stopBroadcast();
    if (mounted) Navigator.of(context).pop();
  }

  // ============================================
  // === مغادرة البث ===
  // ============================================

  Future<void> _leaveBroadcast() async {
    await context.read<BroadcastService>().leaveBroadcast();
    if (mounted) Navigator.of(context).pop();
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BroadcastService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A1F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F2A2E),
              Color(0xFF051114),
            ],
          ),
        ),
        child: SafeArea(
          child: PopScope(
            canPop: service.isIdle,
            onPopInvoked: (didPop) async {
              if (didPop) return;
              if (service.isBroadcasting) {
                await _stopBroadcast();
              } else if (service.isListening) {
                await _leaveBroadcast();
              }
            },
            child: service.isIdle
                ? _buildIdleView()
                : service.isBroadcasting
                    ? _buildBroadcasterView(service)
                    : _buildListenerView(service),
          ),
        ),
      ),
    );
  }

  // ============================================
  // === واجهة الخمول (لا بث) ===
  // ============================================

  Widget _buildIdleView() {
    return Column(
      children: [
        _buildTopBar(
          title: 'البث الصوتي',
          onClose: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // أيقونة
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.4),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.podcasts,
                    size: 64,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 32),

                const Text(
                  'ابدأ بثًا صوتيًا',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'سيرسل التطبيق دعوة لكل الأجهزة المتصلة على الشبكة '
                  'للاستماع إلى صوتك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 40),

                // زر بدء البث
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: Material(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 4,
                    shadowColor: AppTheme.primaryColor.withOpacity(0.4),
                    child: InkWell(
                      onTap: _startBroadcast,
                      borderRadius: BorderRadius.circular(16),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic,
                            color: Colors.white,
                            size: 26,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'بدء البث الآن',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ملاحظة
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Colors.white.withOpacity(0.6),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'يمكنك إيقاف البث في أي وقت. الحد الأقصى '
                          'المستحسن: 8 مستمعين.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.6),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // === واجهة المُذيع ===
  // ============================================

  Widget _buildBroadcasterView(BroadcastService service) {
    return Column(
      children: [
        _buildTopBar(
          title: 'أنت تبث الآن',
          onClose: _stopBroadcast,
          closeIcon: Icons.close,
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // المؤشر الحي
                _LiveIndicator(),

                const SizedBox(height: 32),

                // عدد المستمعين
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${service.listenerCount}',
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        service.listenerCount == 1
                            ? 'مستمع'
                            : 'مستمعين',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // قائمة المستمعين
                if (service.listeners.isNotEmpty) ...[
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'المستمعون:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...service.listeners.entries.map((entry) {
                    return _ListenerTile(name: entry.value);
                  }),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.hourglass_empty,
                          size: 20,
                          color: Colors.white.withOpacity(0.5),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'في انتظار انضمام المستمعين...',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),

        // ============================================
        // === أزرار التحكم ===
        // ============================================
        _buildBroadcasterControls(service),
      ],
    );
  }

  Widget _buildBroadcasterControls(BroadcastService service) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // كتم الميكروفون
          _RoundButton(
            icon: service.isMuted ? Icons.mic_off : Icons.mic,
            label: service.isMuted ? 'إلغاء الكتم' : 'كتم',
            color: service.isMuted
                ? AppTheme.warningColor
                : AppTheme.primaryColor,
            onTap: () {
              HapticFeedback.lightImpact();
              service.toggleMute();
            },
          ),

          // زر الإنهاء (كبير)
          _StopButton(onTap: _stopBroadcast),
        ],
      ),
    );
  }

  // ============================================
  // === واجهة المستمع ===
  // ============================================

  Widget _buildListenerView(BroadcastService service) {
    return Column(
      children: [
        _buildTopBar(
          title: 'تستمع الآن',
          onClose: _leaveBroadcast,
        ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // المؤشر المتحرك
                _PulsingSpeaker(
                  muted: !service.isListeningAudio,
                ),

                const SizedBox(height: 32),

                // اسم المُذيع
                Text(
                  'بث من',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  service.broadcasterName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // الحالة
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.successColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        service.status.isEmpty
                            ? 'متصل'
                            : service.status,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.successColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 60),
              ],
            ),
          ),
        ),

        // ============================================
        // === أزرار التحكم ===
        // ============================================
        _buildListenerControls(service),
      ],
    );
  }

  Widget _buildListenerControls(BroadcastService service) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // كتم الاستماع
          _RoundButton(
            icon: service.isListeningAudio
                ? Icons.volume_up
                : Icons.volume_off,
            label: service.isListeningAudio ? 'كتم' : 'تشغيل',
            color: service.isListeningAudio
                ? AppTheme.primaryColor
                : AppTheme.warningColor,
            onTap: () {
              HapticFeedback.lightImpact();
              service.toggleAudioPlayback();
            },
          ),

          // زر المغادرة
          Material(
            color: AppTheme.errorColor,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _leaveBroadcast,
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Icon(
                  Icons.exit_to_app,
                  size: 32,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // === شريط علوي ===
  // ============================================

  Widget _buildTopBar({
    required String title,
    required VoidCallback onClose,
    IconData closeIcon = Icons.close,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(closeIcon, color: Colors.white),
            onPressed: onClose,
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 48), // موازنة
        ],
      ),
    );
  }
}

// ============================================================
// === أزرار مخصصة ===
// ============================================================

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RoundButton({
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
          color: color.withOpacity(0.15),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _StopButton extends StatelessWidget {
  final VoidCallback onTap;

  const _StopButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppTheme.errorColor,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: AppTheme.errorColor.withOpacity(0.5),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              child: const Icon(
                Icons.stop,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'إنهاء البث',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// === مؤشر البث الحي ===
// ============================================================
class _LiveIndicator extends StatefulWidget {
  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final opacity = 0.4 + (_c.value * 0.6);
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: AppTheme.errorColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: AppTheme.errorColor.withOpacity(opacity),
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(opacity),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'بث حي',
                style: TextStyle(
                  color: AppTheme.errorColor,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// === مكبر الصوت النابض (للمستمع) ===
// ============================================================
class _PulsingSpeaker extends StatefulWidget {
  final bool muted;

  const _PulsingSpeaker({required this.muted});

  @override
  State<_PulsingSpeaker> createState() => _PulsingSpeakerState();
}

class _PulsingSpeakerState extends State<_PulsingSpeaker>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final scale = widget.muted ? 1.0 : 1.0 + (_c.value * 0.1);
        final color = widget.muted
            ? AppTheme.warningColor
            : AppTheme.primaryColor;

        return Transform.scale(
          scale: scale,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withOpacity(0.5),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              widget.muted
                  ? Icons.volume_off
                  : Icons.graphic_eq,
              size: 72,
              color: color,
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// === صف مستمع ===
// ============================================================
class _ListenerTile extends StatelessWidget {
  final String name;

  const _ListenerTile({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(
            Icons.headphones,
            size: 20,
            color: AppTheme.successColor,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// === مساعد الصلاحيات ===
// ============================================================
class PermissionDialogHelper {
  static Future<bool> ensureMic(BuildContext context) async {
    // استخدم موجود permission_dialog إن أردت
    // مؤقتًا: نرجع true لأن BroadcastService يعالج الفشل
    return true;
  }
}
