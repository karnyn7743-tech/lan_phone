import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../theme/app_theme.dart';

/// ============================================================
/// شاشة إعداد الأذونات
/// تظهر مرة واحدة بعد التفعيل، قبل الدخول إلى التطبيق.
/// تتيح للمستخدم منح/رفض كل إذن على حدة.
/// ============================================================
class PermissionSetupScreen extends StatefulWidget {
  final Future<void> Function()? onComplete;

  const PermissionSetupScreen({super.key, this.onComplete});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen>
    with WidgetsBindingObserver {
  // ============================================
  // === حالة الأذونات ===
  // ============================================
  _PermState _mic = _PermState.unknown;
  _PermState _camera = _PermState.unknown;
  _PermState _notifications = _PermState.unknown;
  _PermState _location = _PermState.unknown;
  _PermState _nearbyWifi = _PermState.unknown;
  _PermState _photos = _PermState.unknown;
  _PermState _batteryOptimization = _PermState.unknown;
  bool _fullScreenIntentOk = true;

  bool _loading = true;

  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
    }
  }

  // ============================================
  // === قراءة الحالات ===
  // ============================================

  Future<void> _refreshAll() async {
    final results = await Future.wait<ph.PermissionStatus>([
      ph.Permission.microphone.status,
      ph.Permission.camera.status,
      ph.Permission.notification.status,
      ph.Permission.locationWhenInUse.status,
      ph.Permission.nearbyWifiDevices.status,
      ph.Permission.photos.status,
      ph.Permission.ignoreBatteryOptimizations.status,
    ]);

    if (!mounted) return;

    setState(() {
      _mic = _mapStatus(results[0]);
      _camera = _mapStatus(results[1]);
      _notifications = _mapStatus(results[2]);
      _location = _mapStatus(results[3]);
      _nearbyWifi = _mapStatus(results[4]);
      _photos = _mapStatus(results[5]);
      _batteryOptimization = _mapStatus(results[6]);
      _fullScreenIntentOk = Platform.isAndroid ? _checkFullScreenIntent() : true;
      _loading = false;
    });
  }

  _PermState _mapStatus(ph.PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isProvisional) {
      return _PermState.granted;
    }
    if (s.isPermanentlyDenied || s.isRestricted) {
      return _PermState.permanentlyDenied;
    }
    if (s.isDenied) return _PermState.denied;
    return _PermState.unknown;
  }

  // Full Screen Intent على Android 14+ له إعداد خاص في صفحة النظام.
  // لا يمكن قراءته برمجيًا مباشرة عبر permission_handler، لذا نعرض
  // الزر للمستخدم ليضبطه يدويًا (شفاف وواضح).
  bool _checkFullScreenIntent() {
    // نفترض دائمًا أنه يحتاج إعدادًا على Android 14+
    // (لا يمكن التحقق برمجيًا بسهولة)
    return false;
  }

  // ============================================
  // === طلب الأذونات (كل واحدة على حدة) ===
  // ============================================

  Future<void> _requestMicrophone() async {
    final s = await ph.Permission.microphone.request();
    if (mounted) setState(() => _mic = _mapStatus(s));
  }

  Future<void> _requestCamera() async {
    final s = await ph.Permission.camera.request();
    if (mounted) setState(() => _camera = _mapStatus(s));
  }

  Future<void> _requestNotification() async {
    final s = await ph.Permission.notification.request();
    if (mounted) setState(() => _notifications = _mapStatus(s));
  }

  Future<void> _requestLocation() async {
    final s = await ph.Permission.locationWhenInUse.request();
    if (mounted) setState(() => _location = _mapStatus(s));
  }

  Future<void> _requestNearbyWifi() async {
    final s = await ph.Permission.nearbyWifiDevices.request();
    if (mounted) setState(() => _nearbyWifi = _mapStatus(s));
  }

  Future<void> _requestPhotos() async {
    final s = await ph.Permission.photos.request();
    if (mounted) setState(() => _photos = _mapStatus(s));
  }

  Future<void> _requestBatteryOptimization() async {
    final s = await ph.Permission.ignoreBatteryOptimizations.request();
    if (mounted) setState(() => _batteryOptimization = _mapStatus(s));
  }

  Future<void> _openFullScreenIntentSettings() async {
    await ph.openAppSettings();
  }

  // ============================================
  // === متابعة ===
  // ============================================

  Future<void> _continue() async {
    // تحذير لو الأذونات الأساسية ناقصة
    final missing = <String>[];
    if (_mic != _PermState.granted) missing.add('الميكروفون');
    if (_camera != _PermState.granted) missing.add('الكاميرا');
    if (_notifications != _PermState.granted) missing.add('الإشعارات');

    if (missing.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.warningColor,
            size: 40,
          ),
          title: const Text('أذونات ناقصة'),
          content: Text(
            'الأذونات التالية ضرورية لعمل التطبيق:\n'
            '• ${missing.join("\n• ")}\n\n'
            'يمكنك المتابعة، لكن ميزات معينة لن تعمل حتى تمنحها من إعدادات التطبيق.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة على أي حال'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (widget.onComplete != null) {
      await widget.onComplete!();
    }
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('إعداد الأذونات'),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          : SafeArea(
              child: Column(
                children: [
                  // ============================================
                  // === ترويسة توضيحية ===
                  // ============================================
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.security,
                          color: AppTheme.primaryColor,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'لم يعمل LanPhone بكفاءة، نحتاج بعض الأذونات.\n'
                            'ستظهر نافذة النظام لكل إذن — وافق عليها.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: isDark
                                  ? AppTheme.darkTextPrimary
                                  : AppTheme.lightTextPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ============================================
                  // === قائمة الأذونات ===
                  // ============================================
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _sectionTitle('الأذونات الأساسية', isDark),
                        _PermissionRow(
                          icon: Icons.mic,
                          title: 'الميكروفون',
                          subtitle: 'لإجراء المكالمات الصوتية والرسائل الصوتية',
                          state: _mic,
                          isDark: isDark,
                          onRequest: _requestMicrophone,
                          onOpenSettings: ph.openAppSettings,
                          required: true,
                        ),
                        _PermissionRow(
                          icon: Icons.videocam,
                          title: 'الكاميرا',
                          subtitle: 'لمكالمات الفيديو والتقاط الصور',
                          state: _camera,
                          isDark: isDark,
                          onRequest: _requestCamera,
                          onOpenSettings: ph.openAppSettings,
                          required: true,
                        ),
                        _PermissionRow(
                          icon: Icons.notifications,
                          title: 'الإشعارات',
                          subtitle: 'لاستقبال المكالمات والرسائل أثناء الخلفية',
                          state: _notifications,
                          isDark: isDark,
                          onRequest: _requestNotification,
                          onOpenSettings: ph.openAppSettings,
                          required: true,
                        ),
                        _PermissionRow(
                          icon: Icons.location_on,
                          title: 'الموقع',
                          subtitle: 'لاكتشاف الأجهزة على شبكة WiFi المحلية',
                          state: _location,
                          isDark: isDark,
                          onRequest: _requestLocation,
                          onOpenSettings: ph.openAppSettings,
                          required: true,
                        ),
                        _PermissionRow(
                          icon: Icons.wifi,
                          title: 'أجهزة WiFi القريبة',
                          subtitle: 'لاكتشاف الأجهزة المجاورة (Android 13+)',
                          state: _nearbyWifi,
                          isDark: isDark,
                          onRequest: _requestNearbyWifi,
                          onOpenSettings: ph.openAppSettings,
                          required: true,
                        ),

                        const SizedBox(height: 16),
                        _sectionTitle('أذونات اختيارية', isDark),
                        _PermissionRow(
                          icon: Icons.photo_library,
                          title: 'الصور والوسائط',
                          subtitle: 'لإرسال الصور ومقاطع الفيديو',
                          state: _photos,
                          isDark: isDark,
                          onRequest: _requestPhotos,
                          onOpenSettings: ph.openAppSettings,
                          required: false,
                        ),

                        const SizedBox(height: 16),
                        _sectionTitle('إعدادات خاصة للنظام', isDark),
                        _PermissionRow(
                          icon: Icons.battery_saver,
                          title: 'تحسين البطارية',
                          subtitle: 'لإبقاء التطبيق نشطًا لاستقبال المكالمات',
                          state: _batteryOptimization,
                          isDark: isDark,
                          onRequest: _requestBatteryOptimization,
                          onOpenSettings: ph.openAppSettings,
                          required: false,
                          isSpecial: true,
                        ),
                        _PermissionRow(
                          icon: Icons.fullscreen,
                          title: 'الشاشة الكاملة عند القفل',
                          subtitle: 'لإظهار شاشة المكالمة على شاشة القفل',
                          state: _fullScreenIntentOk
                              ? _PermState.granted
                              : _PermState.unknown,
                          isDark: isDark,
                          onRequest: _openFullScreenIntentSettings,
                          onOpenSettings: ph.openAppSettings,
                          required: false,
                          isSpecial: true,
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),

                  // ============================================
                  // === زر المتابعة ===
                  // ============================================
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _continue,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text(
                          'متابعة إلى التطبيق',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ============================================================
// === حالة الإذن ===
// ============================================================
enum _PermState { unknown, granted, denied, permanentlyDenied }

// ============================================================
// === صف إذن واحد ===
// ============================================================
class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final _PermState state;
  final bool isDark;
  final Future<void> Function() onRequest;
  final Future<bool> Function() onOpenSettings;
  final bool required;
  final bool isSpecial;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.isDark,
    required this.onRequest,
    required this.onOpenSettings,
    this.required = false,
    this.isSpecial = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGranted = state == _PermState.granted;
    final isPermDenied = state == _PermState.permanentlyDenied;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGranted
              ? AppTheme.successColor.withOpacity(0.4)
              : (isDark ? AppTheme.darkDivider : AppTheme.lightDivider),
          width: isGranted ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // الأيقونة
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isGranted
                  ? AppTheme.successColor.withOpacity(0.12)
                  : AppTheme.primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isGranted ? Icons.check : icon,
              color: isGranted ? AppTheme.successColor : AppTheme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // النصوص
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.lightTextPrimary,
                        ),
                      ),
                    ),
                    if (required) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'مطلوب',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.errorColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // الزر
          _buildActionButton(context, isGranted, isPermDenied),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    bool isGranted,
    bool isPermDenied,
  ) {
    if (isGranted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.successColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '✓ مسموح',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.successColor,
          ),
        ),
      );
    }

    // مرفوض نهائيًا أو إذن خاص → فتح الإعدادات
    if (isPermDenied || isSpecial) {
      return OutlinedButton(
        onPressed: () async {
          await onRequest();
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          side: BorderSide(
            color: AppTheme.primaryColor.withOpacity(0.5),
          ),
        ),
        child: const Text(
          'فتح الإعدادات',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryColor,
          ),
        ),
      );
    }

    // حالة denied أو unknown → زر سماح
    return FilledButton(
      onPressed: () async {
        await onRequest();
      },
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: const Size(0, 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        backgroundColor: AppTheme.primaryColor,
      ),
      child: const Text(
        'سماح',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
