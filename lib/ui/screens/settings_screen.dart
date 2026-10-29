import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/services/lock_service.dart';
import '../../core/services/ringtone_service.dart';
import '../../data/database/database_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/permission_dialog.dart';
import 'qr_display_screen.dart';

/// ============================================================
/// شاشة الإعدادات
/// ============================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;

  String _deviceName = '';
  String _deviceId = '';
  String _deviceNumber = '';
  String _localIp = '';
  bool _vibrationEnabled = true;
  bool _soundEnabled = true;
  bool _batteryOptimizationDisabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    try {
      final discovery = context.read<DeviceDiscovery>();

      final batteryStatus =
          await ph.Permission.ignoreBatteryOptimizations.status;

      if (!mounted) return;
      setState(() {
        _deviceName = discovery.deviceName;
        _deviceId = discovery.deviceId;
        _deviceNumber = discovery.deviceNumber;
        _localIp = discovery.localIp;
        _batteryOptimizationDisabled = batteryStatus.isGranted;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[Settings] loadSettings error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ============================================
  // === تعديل اسم الجهاز ===
  // ============================================

  Future<void> _editDeviceName() async {
    final controller = TextEditingController(text: _deviceName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم الجهاز'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: 'مثال: هاتف أحمد',
            prefixIcon: Icon(Icons.devices_outlined),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newName == null || newName.isEmpty || newName == _deviceName) return;

    final discovery = context.read<DeviceDiscovery>();
    await discovery.updateDeviceName(newName);

    if (!mounted) return;
    setState(() => _deviceName = newName);
    _showSnack('تم تحديث اسم الجهاز', isSuccess: true);
  }

  // ============================================
  // === تعديل رقم الاتصال ===
  // ============================================

  Future<void> _editDeviceNumber() async {
    final controller = TextEditingController(text: _deviceNumber);

    final newNumber = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رقم الاتصال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'اختر رقمًا من 1000 إلى 9999.\n'
              'يجب أن يكون فريدًا على الشبكة.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 32,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                hintText: '----',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newNumber == null ||
        newNumber.isEmpty ||
        newNumber == _deviceNumber) {
      return;
    }

    if (newNumber.length != 4) {
      _showSnack('الرقم يجب أن يكون 4 أرقام');
      return;
    }

    final parsed = int.tryParse(newNumber);
    if (parsed == null ||
        parsed < AppConstants.numberMin ||
        parsed > AppConstants.numberMax) {
      _showSnack(
        'الرقم يجب أن يكون بين ${AppConstants.numberMin} و${AppConstants.numberMax}',
      );
      return;
    }

    final discovery = context.read<DeviceDiscovery>();
    final ok = await discovery.updateDeviceNumber(newNumber);

    if (!mounted) return;

    if (ok) {
      setState(() => _deviceNumber = newNumber);
      _showSnack('تم تحديث رقم الاتصال', isSuccess: true);
    } else {
      _showSnack('الرقم مستخدم من قِبل جهاز آخر');
    }
  }

  // ============================================
  // === QR ===
  // ============================================

  void _openQrDisplay() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrDisplayScreen()),
    );
  }

  // ============================================
  // === المظهر ===
  // ============================================

  Future<void> _setThemeMode(String mode) async {
    final themeProvider = context.read<ThemeProvider>();
    await themeProvider.setThemeMode(mode);
  }

  // ============================================
  // === الرنين والاهتزاز ===
  // ============================================

  Future<void> _toggleVibration(bool value) async {
    setState(() => _vibrationEnabled = value);
  }

  Future<void> _toggleSound(bool value) async {
    setState(() => _soundEnabled = value);
  }

  // ============================================
  // === قفل التطبيق (جديد) ===
  // ============================================

  Future<void> _toggleLock(bool value) async {
    final lockService = context.read<LockService>();

    // إذا لم تكن البصمة متوفرة → أظهر تنبيهًا
    if (value && !lockService.available) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.fingerprint,
            size: 40,
            color: AppTheme.warningColor,
          ),
          title: const Text('البصمة غير متوفرة'),
          content: const Text(
            'لتستخدم قفل التطبيق، يجب أولًا:\n\n'
            '1. تسجيل بصمة على جهازك\n'
            '2. من الإعدادات ← الأمان ← البصمة\n\n'
            'بعدها عُد وفعّل الخيار.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
      return;
    }

    final ok = await lockService.setEnabled(value);

    if (!mounted) return;

    if (ok) {
      _showSnack(
        value ? 'تم تفعيل قفل التطبيق' : 'تم إلغاء قفل التطبيق',
        isSuccess: true,
      );
    } else if (value) {
      _showSnack('لم يتم التحقق. لم يُفعَّل القفل.');
    }
  }

  Future<void> _selectLockDelay(LockDelay current) async {
    final lockService = context.read<LockService>();

    final selected = await showModalBottomSheet<LockDelay>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LockDelaySheet(currentDelay: current),
    );

    if (selected == null || selected == current) return;

    await lockService.setDelay(selected);

    if (!mounted) return;
    _showSnack('تم تحديث تأخير القفل', isSuccess: true);
  }

  // ============================================
  // === الإشعارات ===
  // ============================================

  Future<void> _manageNotifications() async {
    final granted = await PermissionDialog.ensure(
      context,
      permissions: <ph.Permission>[ph.Permission.notification],
      title: 'الإشعارات',
      message: 'نحتاج الإذن لعرض إشعارات المكالمات والرسائل',
      icon: Icons.notifications_outlined,
    );
    if (!mounted) return;
    if (granted) _showSnack('الإشعارات مفعّلة', isSuccess: true);
  }

  // ============================================
  // === تعطيل تحسين البطارية ===
  // ============================================

  Future<void> _requestIgnoreBatteryOptimizations() async {
    try {
      final status = await ph.Permission.ignoreBatteryOptimizations.status;

      if (status.isGranted) {
        if (!mounted) return;
        setState(() => _batteryOptimizationDisabled = true);
        _showSnack('الاستثناء مفعّل بالفعل', isSuccess: true);
        return;
      }

      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.battery_charging_full_outlined,
            size: 40,
            color: AppTheme.primaryColor,
          ),
          title: const Text('تعطيل تحسين البطارية'),
          content: const Text(
            'لتتمكن من استقبال المكالمات والرسائل عندما يكون '
            'التطبيق مغلقًا أو الشاشة مقفلة، يجب السماح له بالعمل '
            'في الخلفية دون قيود.\n\n'
            'سيُفتح الآن إعداد النظام لتفعيل هذا الاستثناء.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لاحقًا'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );

      if (proceed != true || !mounted) return;

      final result = await ph.Permission.ignoreBatteryOptimizations.request();

      if (!mounted) return;

      if (result.isGranted) {
        setState(() => _batteryOptimizationDisabled = true);
        _showSnack('تم تعطيل تحسين البطارية', isSuccess: true);
      } else {
        _showSnack('لم يتم تفعيل الاستثناء');
      }
    } catch (e) {
      debugPrint('[Settings] battery optimization error: $e');
      if (!mounted) return;
      _showSnack('تعذّر طلب الإذن');
    }
  }

  // ============================================
  // === دليل الأجهزة الصينية ===
  // ============================================

  Future<void> _showChineseDeviceHelp() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: AppTheme.primaryColor),
            SizedBox(width: 8),
            Expanded(child: Text('إعدادات موثوقية إضافية')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'على بعض الأجهزة (خاصة الصينية منها مثل Xiaomi، '
                'Huawei، Oppo، Vivo)، قد تحتاج لتمكين بعض الإعدادات '
                'يدويًا لضمان عمل المكالمات في الخلفية.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 16),
              _deviceHelpItem(
                title: 'Xiaomi / Redmi / POCO (MIUI)',
                steps: [
                  'الإعدادات ← التطبيقات ← إدارة التطبيقات ← LanPhone',
                  'تمكين "التشغيل التلقائي"',
                  'من "الأذونات الأخرى": تمكين "العرض على شاشة القفل"',
                  'من "البطارية": اختيار "بدون قيود"',
                ],
              ),
              _deviceHelpItem(
                title: 'Huawei / Honor (EMUI)',
                steps: [
                  'الإعدادات ← البطارية ← تشغيل التطبيق',
                  'اختيار LanPhone ← "إدارة يدوية"',
                  'تمكين: التشغيل التلقائي، التشغيل الثانوي، '
                      'العمل في الخلفية',
                ],
              ),
              _deviceHelpItem(
                title: 'Oppo / Realme (ColorOS)',
                steps: [
                  'الإعدادات ← البطارية ← استهلاك الطاقة في الخلفية',
                  'اختيار LanPhone ← "السماح بالعمل في الخلفية"',
                  'تفعيل "التشغيل التلقائي" في مدير بدء التشغيل',
                ],
              ),
              _deviceHelpItem(
                title: 'Vivo / iQOO (Funtouch OS)',
                steps: [
                  'الإعدادات ← البطارية ← استهلاك الطاقة في الخلفية',
                  'اختيار LanPhone ← "السماح"',
                  'تفعيل "التشغيل التلقائي" من iManager',
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'بعد تمكين هذه الإعدادات، أعد تشغيل التطبيق.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('فهمت'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ph.openAppSettings();
            },
            child: const Text('فتح إعدادات التطبيق'),
          ),
        ],
      ),
    );
  }

  Widget _deviceHelpItem({
    required String title,
    required List<String> steps,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 6),
          ...steps.map(
            (s) => Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Text(
                      s,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // === نسخ ===
  // ============================================

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showSnack('تم نسخ $label');
  }

  // ============================================
  // === إعادة تعيين ===
  // ============================================

  Future<void> _clearAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          size: 40,
          color: AppTheme.errorColor,
        ),
        title: const Text('إعادة تعيين التطبيق'),
        content: const Text(
          'سيتم حذف:\n'
          '• كل المحادثات والرسائل\n'
          '• سجل المكالمات\n'
          '• الأجهزة المحفوظة\n\n'
          'لا يمكن التراجع عن هذه العملية.',
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
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DatabaseHelper.instance.wipeAll();
      if (!mounted) return;
      _showSnack('تم حذف جميع البيانات', isSuccess: true);
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      await _loadSettings();
    } catch (e) {
      debugPrint('[Settings] clearAllData error: $e');
      if (!mounted) return;
      _showSnack('فشل حذف البيانات: $e');
    }
  }

  void _showSnack(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? AppTheme.successColor : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildDeviceHeader(),
                const _SectionTitle(title: 'رقم الاتصال والاقتران'),
                _buildNumberSection(),
                const _SectionTitle(title: 'الأمان'),
                _buildLockSection(),
                const _SectionTitle(title: 'المظهر'),
                _buildThemeSection(),
                const _SectionTitle(title: 'الرنين والأصوات'),
                _buildRingtoneSection(),
                const _SectionTitle(title: 'الإشعارات'),
                _buildNotificationsSection(),
                const _SectionTitle(title: 'الموثوقية في الخلفية'),
                _buildReliabilitySection(),
                const _SectionTitle(title: 'معلومات الشبكة'),
                _buildNetworkSection(),
                const _SectionTitle(title: 'البيانات'),
                _buildDataSection(),
                const _SectionTitle(title: 'عن التطبيق'),
                _buildAboutSection(),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ============================================
  // === قسم قفل التطبيق (جديد) ===
  // ============================================

  Widget _buildLockSection() {
    final lockService = context.watch<LockService>();

    return _SettingsCard(
      children: [
        // التفعيل
        SwitchListTile(
          value: lockService.enabled,
          onChanged: _toggleLock,
          title: const Text('قفل التطبيق بالبصمة'),
          subtitle: Text(
            lockService.available
                ? lockService.biometricDescription
                : 'البصمة غير متوفرة على هذا الجهاز',
            style: TextStyle(
              color: lockService.available
                  ? null
                  : AppTheme.warningColor,
            ),
          ),
          secondary: Icon(
            lockService.enabled ? Icons.lock : Icons.lock_open_outlined,
            color: lockService.enabled
                ? AppTheme.primaryColor
                : null,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),

        // تأخير القفل (يظهر فقط عند التفعيل)
        if (lockService.enabled)
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('وقت القفل التلقائي'),
            subtitle: Text(
              lockService.delay.label,
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => _selectLockDelay(lockService.delay),
          ),

        // زر قفل الآن (يدوي)
        if (lockService.enabled)
          ListTile(
            leading: const Icon(
              Icons.lock_clock,
              color: AppTheme.primaryColor,
            ),
            title: const Text('اقفل التطبيق الآن'),
            subtitle: const Text('يقفل فورًا ويطلب البصمة عند العودة'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () {
              lockService.lock();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),

        // تلميح عندما لا تتوفر البصمة
        if (!lockService.available)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppTheme.warningColor,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لتستخدم هذه الميزة، سجّل بصمة من إعدادات جهازك أولًا.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ============================================
  // === رأس الجهاز ===
  // ============================================

  Widget _buildDeviceHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withOpacity(0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.4),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.phone_android,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'هذا الجهاز',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _deviceName.isEmpty ? 'جارٍ التحميل...' : _deviceName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: Colors.greenAccent),
                    SizedBox(width: 6),
                    Text(
                      'يعمل',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white.withOpacity(0.15),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _editDeviceName,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.edit_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // === الرقم + QR ===
  // ============================================

  Widget _buildNumberSection() {
    return _SettingsCard(
      children: [
        ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              _deviceNumber.isEmpty ? '----' : _deviceNumber,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
                letterSpacing: 1.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          title: const Text('رقم الاتصال'),
          subtitle: Text(
            _deviceNumber.isEmpty
                ? 'جارٍ التوليد...'
                : 'رقمك على الشبكة: $_deviceNumber',
          ),
          trailing: const Icon(Icons.chevron_left),
          onTap: _editDeviceNumber,
        ),
        ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.qr_code_2,
              color: Color(0xFF25D366),
              size: 26,
            ),
          ),
          title: const Text('رمز QR للمشاركة'),
          subtitle: const Text('اعرض رمزك ليقترن الآخرون بك'),
          trailing: const Icon(Icons.chevron_left),
          onTap: _openQrDisplay,
        ),
      ],
    );
  }

  // ============================================
  // === المظهر ===
  // ============================================

  Widget _buildThemeSection() {
    final currentMode = context.watch<ThemeProvider>().themeModeString;

    return _SettingsCard(
      children: [
        RadioListTile<String>(
          value: 'light',
          groupValue: currentMode,
          onChanged: (v) {
            if (v != null) _setThemeMode(v);
          },
          title: const Text('فاتح'),
          secondary: const Icon(Icons.light_mode_outlined),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        RadioListTile<String>(
          value: 'dark',
          groupValue: currentMode,
          onChanged: (v) {
            if (v != null) _setThemeMode(v);
          },
          title: const Text('داكن'),
          secondary: const Icon(Icons.dark_mode_outlined),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        RadioListTile<String>(
          value: 'system',
          groupValue: currentMode,
          onChanged: (v) {
            if (v != null) _setThemeMode(v);
          },
          title: const Text('حسب النظام'),
          secondary: const Icon(Icons.brightness_auto_outlined),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ],
    );
  }

  // ============================================
  // === الرنين ===
  // ============================================

  Widget _buildRingtoneSection() {
    final ringtoneService = context.watch<RingtoneService>();

    return _SettingsCard(
      children: RingtoneType.values.map((type) {
        final isSelected = ringtoneService.type == type;
        return _RingtoneOption(
          type: type,
          isSelected: isSelected,
          onSelect: () async {
            await ringtoneService.setType(type);
            if (type != RingtoneType.silent) {
              await ringtoneService.preview(type);
            }
          },
          onPreview: type == RingtoneType.silent
              ? null
              : () => ringtoneService.preview(type),
        );
      }).toList(),
    );
  }

  // ============================================
  // === الإشعارات ===
  // ============================================

  Widget _buildNotificationsSection() {
    return _SettingsCard(
      children: [
        SwitchListTile(
          value: _soundEnabled,
          onChanged: _toggleSound,
          title: const Text('تشغيل الأصوات'),
          subtitle: const Text('تفعيل أصوات التطبيق'),
          secondary: const Icon(Icons.volume_up_outlined),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        SwitchListTile(
          value: _vibrationEnabled,
          onChanged: _toggleVibration,
          title: const Text('الاهتزاز'),
          subtitle: const Text('اهتزاز عند وصول مكالمة أو رسالة'),
          secondary: const Icon(Icons.vibration_outlined),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('إدارة الإشعارات'),
          trailing: const Icon(Icons.chevron_left),
          onTap: _manageNotifications,
        ),
      ],
    );
  }

  // ============================================
  // === الموثوقية ===
  // ============================================

  Widget _buildReliabilitySection() {
    return _SettingsCard(
      children: [
        ListTile(
          leading: Icon(
            _batteryOptimizationDisabled
                ? Icons.battery_full
                : Icons.battery_alert_outlined,
            color: _batteryOptimizationDisabled
                ? AppTheme.successColor
                : AppTheme.warningColor,
          ),
          title: const Text('تعطيل تحسين البطارية'),
          subtitle: Text(
            _batteryOptimizationDisabled
                ? '✅ مفعّل — التطبيق يعمل بدون قيود'
                : '⚠️ مطلوب لاستقبال المكالمات في الخلفية',
            style: TextStyle(
              color: _batteryOptimizationDisabled
                  ? AppTheme.successColor
                  : AppTheme.warningColor,
            ),
          ),
          trailing: const Icon(Icons.chevron_left),
          onTap: _requestIgnoreBatteryOptimizations,
        ),
        ListTile(
          leading: const Icon(
            Icons.phone_android_outlined,
            color: AppTheme.primaryColor,
          ),
          title: const Text('إعدادات موثوقية إضافية'),
          subtitle: const Text(
            'دليل خاص بأجهزة Xiaomi، Huawei، Oppo، Vivo',
          ),
          trailing: const Icon(Icons.chevron_left),
          onTap: _showChineseDeviceHelp,
        ),
      ],
    );
  }

  // ============================================
  // === الشبكة ===
  // ============================================

  Widget _buildNetworkSection() {
    return _SettingsCard(
      children: [
        _InfoTile(
          icon: Icons.tag,
          title: 'معرّف الجهاز',
          value: _deviceId.isEmpty
              ? 'غير متوفر'
              : '${_deviceId.substring(0, _min(8, _deviceId.length))}...',
          onCopy: _deviceId.isEmpty
              ? null
              : () => _copyToClipboard(_deviceId, 'المعرّف'),
        ),
        _InfoTile(
          icon: Icons.wifi,
          title: 'عنوان IP',
          value: _localIp.isEmpty ? 'غير متصل' : _localIp,
          onCopy: _localIp.isEmpty
              ? null
              : () => _copyToClipboard(_localIp, 'عنوان IP'),
        ),
        _InfoTile(
          icon: Icons.settings_ethernet,
          title: 'منفذ التحكم',
          value: '${AppConstants.signalingPort}',
        ),
        _InfoTile(
          icon: Icons.sync_alt,
          title: 'منفذ الاكتشاف',
          value: '${AppConstants.discoveryPort}',
        ),
      ],
    );
  }

  int _min(int a, int b) => a < b ? a : b;

  // ============================================
  // === البيانات ===
  // ============================================

  Widget _buildDataSection() {
    return _SettingsCard(
      children: [
        ListTile(
          leading: const Icon(
            Icons.delete_forever_outlined,
            color: AppTheme.errorColor,
          ),
          title: const Text(
            'إعادة تعيين التطبيق',
            style: TextStyle(color: AppTheme.errorColor),
          ),
          subtitle: const Text('حذف كل المحادثات والبيانات'),
          onTap: _clearAllData,
        ),
      ],
    );
  }

  // ============================================
  // === عن التطبيق ===
  // ============================================

  Widget _buildAboutSection() {
    return _SettingsCard(
      children: [
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text(AppConstants.appName),
          subtitle: Text('الإصدار ${AppConstants.appVersion}'),
        ),
        const ListTile(
          leading: Icon(Icons.wifi_tethering),
          title: Text('شبكة محلية فقط'),
          subtitle: Text('لا يستخدم الإنترنت أو شبكات الاتصالات'),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('مفتوح المصدر'),
          subtitle: const Text('مرخّص تحت MIT License'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => _showSnack('سيفتح رابط GitHub قريبًا'),
        ),
      ],
    );
  }
}

// ============================================================
// === قائمة تأخير القفل ===
// ============================================================
class _LockDelaySheet extends StatelessWidget {
  final LockDelay currentDelay;

  const _LockDelaySheet({required this.currentDelay});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: AppTheme.primaryColor,
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'متى يُقفل التطبيق؟',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ...LockDelay.values.map((delay) {
              final isSelected = delay == currentDelay;
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : (isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary),
                ),
                title: Text(
                  delay.label,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? AppTheme.primaryColor : null,
                  ),
                ),
                subtitle: Text(
                  delay.description,
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(context, delay),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// === عناصر مساعدة ===
// ============================================================

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
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

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onCopy;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
        ),
      ),
      trailing: onCopy != null
          ? IconButton(
              icon: const Icon(Icons.copy_outlined, size: 20),
              tooltip: 'نسخ',
              onPressed: onCopy,
            )
          : null,
    );
  }
}

class _RingtoneOption extends StatelessWidget {
  final RingtoneType type;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback? onPreview;

  const _RingtoneOption({
    required this.type,
    required this.isSelected,
    required this.onSelect,
    this.onPreview,
  });

  IconData get _icon {
    switch (type) {
      case RingtoneType.ringtone:
        return Icons.phone_in_talk_outlined;
      case RingtoneType.alarm:
        return Icons.alarm;
      case RingtoneType.notification:
        return Icons.notifications_active_outlined;
      case RingtoneType.silent:
        return Icons.volume_off_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withOpacity(0.08)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? AppTheme.darkDivider
                    : AppTheme.lightDivider,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected
                    ? AppTheme.primaryColor
                    : (isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary),
                size: 22,
              ),
              const SizedBox(width: 12),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor.withOpacity(0.15)
                      : (isDark
                          ? AppTheme.darkDivider
                          : const Color(0xFFF1F3F5)),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _icon,
                  size: 20,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : (isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      type.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.primaryColor
                            : (isDark
                                ? AppTheme.darkTextPrimary
                                : AppTheme.lightTextPrimary),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      type.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onPreview != null)
                Material(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onPreview,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
