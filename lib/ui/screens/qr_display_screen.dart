import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/services/qr_service.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// شاشة عرض QR الخاص بالجهاز
/// يُمسح من قِبل جهاز آخر للاقتران السريع
/// ============================================================
class QrDisplayScreen extends StatelessWidget {
  const QrDisplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final discovery = context.watch<DeviceDiscovery>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // إذا كانت البيانات غير جاهزة
    if (discovery.deviceId.isEmpty ||
        discovery.deviceNumber.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('رمز QR')),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    // أنشئ نص QR
    final qrData = QrService.encode(
      deviceId: discovery.deviceId,
      number: discovery.deviceNumber,
      name: discovery.deviceName,
      ip: discovery.localIp,
      port: AppConstants.signalingPort,
    );

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('رمز QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'نسخ البيانات',
            onPressed: () => _copyData(context, qrData),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),

              // ============================================
              // === الرقم البارز ===
              // ============================================
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      Color(0xFF25D366),
                    ],
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

              // ============================================
              // === بطاقة QR ===
              // ============================================
              Container(
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
                    // اسم الجهاز
                    Text(
                      discovery.deviceName,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'امسح الرمز للاقتران',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // رمز QR
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
                        embeddedImageStyle: null,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ============================================
              // === معلومات إضافية ===
              // ============================================
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.darkDivider
                        : AppTheme.lightDivider,
                  ),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.tag,
                      label: 'الرقم',
                      value: '#${discovery.deviceNumber}',
                      isDark: isDark,
                    ),
                    Divider(
                      height: 20,
                      color: isDark
                          ? AppTheme.darkDivider
                          : AppTheme.lightDivider,
                    ),
                    _InfoRow(
                      icon: Icons.wifi,
                      label: 'عنوان IP',
                      value: discovery.localIp.isEmpty
                          ? 'غير متصل'
                          : discovery.localIp,
                      isDark: isDark,
                    ),
                    Divider(
                      height: 20,
                      color: isDark
                          ? AppTheme.darkDivider
                          : AppTheme.lightDivider,
                    ),
                    _InfoRow(
                      icon: Icons.devices,
                      label: 'المعرّف',
                      value: discovery.deviceId.length > 12
                          ? '${discovery.deviceId.substring(0, 12)}...'
                          : discovery.deviceId,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ============================================
              // === نصيحة ===
              // ============================================
              Container(
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
                        'افتح التطبيق على الجهاز الآخر واضغط على "ماسح QR" من الأعلى',
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
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyData(BuildContext context, String data) async {
    await Clipboard.setData(ClipboardData(text: data));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ بيانات الجهاز'),
        backgroundColor: AppTheme.successColor,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ============================================================
// === صف معلومات ===
// ============================================================
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
