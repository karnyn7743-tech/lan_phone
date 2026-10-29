import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/services/activation_service.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// شاشة تنشيط التطبيق
/// ============================================================
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _busy = false;
  bool _showDeviceId = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoPasteFromClipboard();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ============================================
  // === اللصق التلقائي (ذكي) ===
  // ============================================

  Future<void> _autoPasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) return;

      // ✅ يستخرج أي نص يشبه المفتاح (16 hex + شرطات اختيارية)
      final match = RegExp(
        r'[A-Fa-f0-9]{4}-?[A-Fa-f0-9]{4}-?[A-Fa-f0-9]{4}-?[A-Fa-f0-9]{4}',
      ).firstMatch(text);

      if (match != null && mounted) {
        _controller.text = match.group(0)!;
        setState(() {});
        debugPrint('[Activation] Auto-pasted key: ${match.group(0)}');
      }
    } catch (e) {
      debugPrint('[Activation] autoPaste error: $e');
    }
  }

  // ============================================
  // === لصق يدوي من الزر ===
  // ============================================

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        _showSnack('الحافظة فارغة');
        return;
      }

      // استخرج المفتاح من النص
      final match = RegExp(
        r'[A-Fa-f0-9]{4}-?[A-Fa-f0-9]{4}-?[A-Fa-f0-9]{4}-?[A-Fa-f0-9]{4}',
      ).firstMatch(text);

      if (match == null) {
        _showSnack('لم يُعثر على مفتاح صالح في الحافظة');
        return;
      }

      if (!mounted) return;
      setState(() {
        _controller.text = match.group(0)!;
      });
      HapticFeedback.lightImpact();
      _showSnack('تم لصق المفتاح');
    } catch (e) {
      debugPrint('[Activation] paste error: $e');
      _showSnack('تعذّر اللصق');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // === التنشيط ===
  // ============================================

  Future<void> _activate() async {
    if (_busy) return;
    setState(() => _busy = true);

    final ok = await context.read<ActivationService>().activate(
          _controller.text,
        );

    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  // ============================================
  // === نسخ معرّف الجهاز ===
  // ============================================

  Future<void> _copyDeviceId() async {
    final service = context.read<ActivationService>();
    await Clipboard.setData(ClipboardData(text: service.deviceId));
    if (!mounted) return;
    HapticFeedback.lightImpact();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ معرّف الجهاز — أرسله للمطوّر'),
        backgroundColor: AppTheme.successColor,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ActivationService>();

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 32,
            ),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // الشعار
                Container(
                  width: 96,
                  height: 96,
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
                    Icons.verified_user_outlined,
                    size: 46,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 24),

                // العنوان
                const Text(
                  'تنشيط التطبيق',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'لتفعيل ${AppConstants.appName} على هذا الجهاز، '
                  'أدخل مفتاح التنشيط',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 32),

                // ============================================
                // === بطاقة معرّف الجهاز ===
                // ============================================
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primaryColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.fingerprint,
                              color: AppTheme.primaryColor,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'معرّف هذا الجهاز',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _showDeviceId
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.white70,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(
                                () => _showDeviceId = !_showDeviceId,
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                _showDeviceId
                                    ? service.deviceId
                                    : '••••••••••••••••••••••••••••',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: _showDeviceId ? 11 : 13,
                                  color: Colors.white.withOpacity(0.85),
                                  letterSpacing:
                                      _showDeviceId ? 0.3 : 1.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Material(
                              color: AppTheme.primaryColor
                                  .withOpacity(0.2),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _copyDeviceId,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.copy_outlined,
                                    color: AppTheme.primaryColor,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'هذا المعرّف ثابت لهذا الجهاز ولا يتغير حتى عند '
                        'إعادة تثبيت التطبيق.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.5),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ============================================
                // === حقل المفتاح (مُصحَّح — يقبل اللصق) ===
                // ============================================
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: service.error != null
                          ? AppTheme.errorColor.withOpacity(0.5)
                          : Colors.white.withOpacity(0.15),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.vpn_key_outlined,
                              size: 16,
                              color: Colors.white.withOpacity(0.7),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'مفتاح التنشيط',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                            const Spacer(),
                            // ✅ زر لصق يدوي
                            Material(
                              color: AppTheme.primaryColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: _pasteFromClipboard,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.content_paste,
                                        color: AppTheme.primaryColor,
                                        size: 16,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'لصق',
                                        style: TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextField(
                        controller: _controller,
                        focusNode: _focus,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        // ✅ لا inputFormatters — يقبل أي نص
                        // ✅ لا maxLength — بلا حد
                        // ✅ enableInteractiveSelection يسمح باللصق
                        enableInteractiveSelection: true,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        cursorColor: AppTheme.primaryColor,
                        decoration: const InputDecoration(
                          hintText: 'XXXX-XXXX-XXXX-XXXX',
                          hintStyle: TextStyle(
                            color: Colors.white24,
                            letterSpacing: 3,
                            fontSize: 20,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          counterText: '',
                        ),
                        onSubmitted: (_) => _activate(),
                      ),
                    ],
                  ),
                ),

                // رسالة الخطأ
                if (service.error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.errorColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppTheme.errorColor,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            service.error!,
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
                ],

                const SizedBox(height: 20),

                // زر التنشيط
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 4,
                    shadowColor:
                        AppTheme.primaryColor.withOpacity(0.4),
                    child: InkWell(
                      onTap: _busy ? null : _activate,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_busy)
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
                                Icons.check_circle_outline,
                                color: Colors.white,
                                size: 24,
                              ),
                            const SizedBox(width: 10),
                            Text(
                              _busy ? 'جارٍ التحقق...' : 'تنشيط التطبيق',
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

                const SizedBox(height: 24),

                // معلومات إضافية
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'المفتاح مرتبط بهذا الجهاز ولا يعمل على أي جهاز '
                          'آخر. يمكنك استخدام نفس المفتاح لاحقًا حتى بعد '
                          'إعادة تثبيت التطبيق.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.75),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'الإصدار ${AppConstants.appVersion}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
