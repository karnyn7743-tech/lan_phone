import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/services/lock_service.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// شاشة قفل التطبيق
/// ============================================================
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ✅ منع البدء المتكرر
  bool _autoAttempted = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // ✅ محاولة تلقائية واحدة فقط، بعد مهلة كافية
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        if (_autoAttempted) return;
        _autoAttempted = true;
        _attemptUnlock();
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ============================================
  // === المصادقة ===
  // ============================================

  Future<void> _attemptUnlock() async {
    final lockService = context.read<LockService>();

    // ✅ لا تُحاول إذا كانت المصادقة جارية
    if (lockService.isAuthenticating) {
      debugPrint('[LockScreen] Already authenticating');
      return;
    }

    HapticFeedback.lightImpact();

    final ok = await lockService.authenticate();

    if (!mounted) return;

    if (!ok) {
      HapticFeedback.heavyImpact();
    }
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    final lockService = context.watch<LockService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A1F),
      body: PopScope(
        canPop: false,
        child: Container(
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
            child: Column(
              children: [
                const Spacer(flex: 2),

                // الشعار
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 120,
                    height: 120,
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
                      Icons.lock_outline,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                const Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  lockService.isAuthenticating
                      ? 'جارٍ التحقق...'
                      : 'التطبيق مقفل',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),

                const SizedBox(height: 12),

                if (lockService.available)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _biometricIcon(lockService),
                          size: 14,
                          color: Colors.white.withOpacity(0.85),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          lockService.biometricDescription,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 40),

                // رسالة الخطأ
                if (lockService.lastError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.errorColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppTheme.errorColor,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              lockService.lastError!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.errorColor,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // رسالة "البصمة غير متوفرة"
                if (!lockService.available)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.warningColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.warningColor.withOpacity(0.3),
                        ),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: AppTheme.warningColor,
                            size: 28,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'البصمة غير متوفرة',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.warningColor,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'يجب تسجيل بصمة على الجهاز لاستخدام هذه الميزة.\n'
                            'افتح الإعدادات ← الأمان ← البصمة.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const Spacer(flex: 1),

                // زر الفتح
                if (lockService.available)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Material(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(16),
                      elevation: 4,
                      shadowColor: AppTheme.primaryColor.withOpacity(0.4),
                      child: InkWell(
                        onTap: lockService.isAuthenticating
                            ? null
                            : _attemptUnlock,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (lockService.isAuthenticating)
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.fingerprint,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              const SizedBox(width: 12),
                              Text(
                                lockService.isAuthenticating
                                    ? 'جارٍ التحقق...'
                                    : 'افتح التطبيق',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                const Spacer(flex: 1),

                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    'LanPhone محمي ببصمة جهازك',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.35),
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

  IconData _biometricIcon(LockService service) {
    if (service.biometricTypes.contains(BiometricType.face)) {
      return Icons.face;
    }
    if (service.biometricTypes.contains(BiometricType.iris)) {
      return Icons.remove_red_eye_outlined;
    }
    return Icons.fingerprint;
  }
}
