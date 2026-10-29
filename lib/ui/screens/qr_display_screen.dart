import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/services/mac_utils.dart';
import '../../core/services/qr_service.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// نمط عرض QR
/// ============================================================
enum QrDisplayMode {
  /// ربط بجهاز آخر يستخدم LanPhone
  peerLink,

  /// تسجيل في شبكة WiFi (يُقرأ من تطبيق إدارة المشتركين)
  networkRegistration,
}

/// ============================================================
/// شاشة عرض QR الخاص بالجهاز
/// تدعم وضعين:
///   1) ربط بجهاز آخر
///   2) تسجيل في شبكة الواي فاي
/// ============================================================
class QrDisplayScreen extends StatefulWidget {
  const QrDisplayScreen({super.key});

  @override
  State<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends State<QrDisplayScreen> {
  // ============================================
  // === الحالة ===
  // ============================================
  QrDisplayMode _mode = QrDisplayMode.peerLink;

  String _fullName = '';
  String _phone = '';
  String _mac = '';
  bool _loadingMac = true;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _macCtrl = TextEditingController();

  Timer? _saveDebounce;

  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _macCtrl.dispose();
    super.dispose();
  }

  // ============================================
  // === تحميل وحفظ البيانات ===
  // ============================================

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(AppConstants.keyFullName) ?? '';
    final savedPhone = prefs.getString(AppConstants.keyPhone) ?? '';
    final savedMac = await MacUtils.getSavedMac() ?? '';

    if (!mounted) return;

    setState(() {
      _fullName = savedName;
      _phone = savedPhone;
      _mac = savedMac;
      _loadingMac = false;

      _nameCtrl.text = savedName;
      _phoneCtrl.text = savedPhone;
      _macCtrl.text = savedMac;
    });
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 600),
      _saveUserInfo,
    );
  }

  Future<void> _saveUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyFullName, _fullName);
    await prefs.setString(AppConstants.keyPhone, _phone);

    // حفظ MAC عبر MacUtils (يتحقق من الصيغة قبل الحفظ)
    if (_mac.isNotEmpty && MacUtils.validate(_mac)) {
      await MacUtils.saveMac(_mac);
    }
  }

  // ============================================
  // === تغييرات الحقول ===
  // ============================================

  void _onNameChanged(String value) {
    setState(() => _fullName = value);
    _scheduleSave();
  }

  void _onPhoneChanged(String value) {
    setState(() => _phone = value);
    _scheduleSave();
  }

  void _onMacChanged(String value) {
    setState(() => _mac = value.toUpperCase());
    _scheduleSave();
  }

  // ============================================
  // === نسخ البيانات ===
  // ============================================

  Future<void> _copyCurrentQrData() async {
    final data = _buildCurrentQrData();
    if (data == null) return;

    await Clipboard.setData(ClipboardData(text: data));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ البيانات'),
        backgroundColor: AppTheme.successColor,
        duration: Duration(seconds: 2),
      ),
    );
  }

  String? _buildCurrentQrData() {
    if (_mode == QrDisplayMode.peerLink) {
      final discovery = context.read<DeviceDiscovery>();
      if (discovery.deviceId.isEmpty) return null;
      return QrService.encode(
        deviceId: discovery.deviceId,
        number: discovery.deviceNumber,
        name: discovery.deviceName,
        ip: discovery.localIp,
        port: AppConstants.signalingPort,
      );
    } else {
      if (!_isNetworkFormValid) return null;
      return QrService.encodeNetworkRegistration(
        fullName: _fullName,
        deviceId: context.read<DeviceDiscovery>().deviceId,
        macAddress: _mac,
        phone: _phone,
      );
    }
  }

  // ============================================
  // === التحقق من صحة النموذج ===
  // ============================================

  bool get _isNetworkFormValid {
    if (_fullName.trim().isEmpty) return false;
    if (_mac.trim().isEmpty) return false;
    if (!MacUtils.validate(_mac)) return false;
    return true;
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
        title: const Text('رمز QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'نسخ البيانات',
            onPressed: _copyCurrentQrData,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ============================================
            // === مبدّل النمط ===
            // ============================================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SegmentedButton<QrDisplayMode>(
                segments: const [
                  ButtonSegment<QrDisplayMode>(
                    value: QrDisplayMode.peerLink,
                    label: Text('ربط جهاز'),
                    icon: Icon(Icons.devices_other),
                  ),
                  ButtonSegment<QrDisplayMode>(
                    value: QrDisplayMode.networkRegistration,
                    label: Text('تسجيل شبكة'),
                    icon: Icon(Icons.wifi_tethering),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  setState(() => _mode = s.first);
                },
                showSelectedIcon: false,
              ),
            ),

            // ============================================
            // === محتوى الوضع الحالي ===
            // ============================================
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _mode == QrDisplayMode.peerLink
                    ? _buildPeerView(context, isDark)
                    : _buildNetworkView(context, isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // === وضع 1: ربط بجهاز آخر ===
  // ============================================

  Widget _buildPeerView(BuildContext context, bool isDark) {
    final discovery = context.watch<DeviceDiscovery>();

    if (discovery.deviceId.isEmpty || discovery.deviceNumber.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    final qrData = QrService.encode(
      deviceId: discovery.deviceId,
      number: discovery.deviceNumber,
      name: discovery.deviceName,
      ip: discovery.localIp,
      port: AppConstants.signalingPort,
    );

    return SingleChildScrollView(
      key: const ValueKey('peer-view'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // رقمك البارز
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryColor, Color(0xFF25D366)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'رقمك',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  discovery.deviceNumber,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _buildQrCard(
            qrData: qrData,
            title: discovery.deviceName,
            subtitle: 'امسح الرمز للاقتران',
          ),

          const SizedBox(height: 24),

          _buildInfoCard(
            isDark: isDark,
            rows: [
              _InfoRowData(
                icon: Icons.tag,
                label: 'الرقم',
                value: '#${discovery.deviceNumber}',
              ),
              _InfoRowData(
                icon: Icons.wifi,
                label: 'عنوان IP',
                value: discovery.localIp.isEmpty
                    ? 'غير متصل'
                    : discovery.localIp,
              ),
              _InfoRowData(
                icon: Icons.devices,
                label: 'المعرّف',
                value: discovery.deviceId.length > 12
                    ? '${discovery.deviceId.substring(0, 12)}...'
                    : discovery.deviceId,
              ),
            ],
          ),

          const SizedBox(height: 20),
          _buildTip(
            isDark: isDark,
            text: 'افتح التطبيق على الجهاز الآخر واضغط على "ماسح QR" من الأعلى',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ============================================
  // === وضع 2: تسجيل في الشبكة ===
  // ============================================

  Widget _buildNetworkView(BuildContext context, bool isDark) {
    if (_loadingMac) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    final qrData = _isNetworkFormValid ? _buildCurrentQrData() : null;

    return SingleChildScrollView(
      key: const ValueKey('network-view'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // ============================================
          // === بطاقة QR ===
          // ============================================
          if (qrData != null)
            _buildQrCard(
              qrData: qrData,
              title: 'تسجيل في شبكة WiFi',
              subtitle: 'اعرض هذا الرمز على مشرف الشبكة',
            )
          else
            _buildIncompleteQrCard(isDark),

          const SizedBox(height: 24),

          // ============================================
          // === نموذج البيانات ===
          // ============================================
          _buildFormCard(isDark),

          const SizedBox(height: 20),

          // ============================================
          // === نصيحة ===
          // ============================================
          _buildTip(
            isDark: isDark,
            text: 'أدخل عنوان MAC الخاص بالواي فاي.\n'
                'تجده في: الإعدادات ← حول الهاتف ← الحالة',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildIncompleteQrCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.warningColor.withOpacity(0.4),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.info_outline,
            size: 56,
            color: AppTheme.warningColor.withOpacity(0.8),
          ),
          const SizedBox(height: 16),
          const Text(
            'أكمل البيانات لعرض الرمز',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'املأ حقول الاسم والهاتف وعنوان MAC أدناه',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان البطاقة
          Row(
            children: [
              const Icon(
                Icons.edit_note,
                color: AppTheme.primaryColor,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'بيانات التسجيل',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // حقل الاسم
          _buildField(
            label: 'الاسم الكامل',
            hint: 'مثال: أحمد صالح',
            controller: _nameCtrl,
            icon: Icons.person_outline,
            isDark: isDark,
            onChanged: _onNameChanged,
          ),
          const SizedBox(height: 14),

          // حقل الهاتف
          _buildField(
            label: 'رقم الهاتف (اختياري)',
            hint: 'مثال: 777000111',
            controller: _phoneCtrl,
            icon: Icons.phone_outlined,
            isDark: isDark,
            keyboardType: TextInputType.phone,
            onChanged: _onPhoneChanged,
          ),
          const SizedBox(height: 14),

          // حقل MAC
          _buildMacField(isDark),
        ],
      ),
    );
  }

  Widget _buildMacField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'عنوان MAC للواي فاي',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _macCtrl,
          onChanged: _onMacChanged,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 15,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'BC:D1:D3:44:55:66',
            hintStyle: TextStyle(
              fontFamily: 'monospace',
              letterSpacing: 1.5,
              color: isDark
                  ? AppTheme.darkTextSecondary.withOpacity(0.5)
                  : AppTheme.lightTextSecondary.withOpacity(0.5),
            ),
            prefixIcon: const Icon(Icons.router_outlined, size: 20),
            suffixIcon: _mac.isNotEmpty && MacUtils.validate(_mac)
                ? const Icon(
                    Icons.check_circle,
                    color: AppTheme.successColor,
                    size: 20,
                  )
                : null,
            filled: true,
            fillColor: isDark
                ? AppTheme.darkBackground
                : const Color(0xFFF5F7FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),
        if (_mac.isNotEmpty && !MacUtils.validate(_mac))
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Text(
              'صيغة غير صحيحة — استخدم XX:XX:XX:XX:XX:XX',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.errorColor.withOpacity(0.9),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    required bool isDark,
    required void Function(String) onChanged,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            filled: true,
            fillColor: isDark
                ? AppTheme.darkBackground
                : const Color(0xFFF5F7FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // === عناصر مشتركة ===
  // ============================================

  Widget _buildQrCard({
    required String qrData,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.primaryColor.withOpacity(0.3),
                width: 3,
              ),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 240,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppTheme.primaryColor,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0F2A2E),
              ),
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              gapless: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required bool isDark,
    required List<_InfoRowData> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 20,
                color: isDark
                    ? AppTheme.darkDivider
                    : AppTheme.lightDivider,
              ),
            _InfoRow(
              icon: rows[i].icon,
              label: rows[i].label,
              value: rows[i].value,
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTip({required bool isDark, required String text}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lightbulb_outline,
            color: AppTheme.primaryColor,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// === صف معلومات ===
// ============================================================
class _InfoRowData {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRowData({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.lightTextPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
