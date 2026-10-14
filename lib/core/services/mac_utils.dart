import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// أدوات قراءة عنوان MAC الخاص بالواي فاي
///
/// الحل: محاولة تلقائية أولًا، وإذا فشلت (أندرويد 10+)
/// نرجع إلى القيمة المحفوظة يدويًا من المستخدم.
/// ============================================================
class MacUtils {
  MacUtils._();

  static const String _prefsKeyManualMac = 'manual_wifi_mac';

  /// مؤشر يفيد بأن MAC غير متاح (أندرويد 10+)
  static const String _unavailableMac = '02:00:00:00:00:00';

  // ============================================
  // === القراءة التلقائية ===
  // ============================================

  /// محاولة قراءة MAC من واجهات الشبكة
  ///
  /// ⚠️ على أندرويد 10+: غالبًا سترجع 02:00:00:00:00:00 أو فاضية
  /// ⚠️ على أندرويد 9-: قد تعمل
  /// ⚠️ على iOS: لا يمكن الوصول إلى MAC على الإطلاق
  static Future<String?> tryReadMacAutomatically() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();

        // نبحث عن واجهة WiFi فقط
        if (name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('en0') ||
            name.contains('ap')) {
          final mac = iface.macAddress;

          if (mac.isEmpty) continue;
          if (mac == _unavailableMac) continue;
          if (mac == '00:00:00:00:00:00') continue;

          // تطبيع الصيغة (نرفع الأحرف الإنجليزية إلى كبيرة)
          final normalized = mac.toUpperCase();
          debugPrint('[MacUtils] ✅ Found WiFi MAC: $normalized');
          return normalized;
        }
      }

      debugPrint('[MacUtils] ⚠️ No WiFi MAC found');
      return null;
    } catch (e) {
      debugPrint('[MacUtils] tryReadMacAutomatically error: $e');
      return null;
    }
  }

  // ============================================
  // === القراءة مع الاحتياطي اليدوي ===
  // ============================================

  /// الحصول على MAC بترتيب الأولويات:
  ///   1) محاولة القراءة التلقائية
  ///   2) القيمة اليدوية المحفوظة
  ///   3) null (يجب على المستخدم إدخالها)
  static Future<String?> getMac({bool forceRefresh = false}) async {
    // 1) جرّب القراءة التلقائية (مع كاش قصير)
    if (!forceRefresh) {
      final auto = await tryReadMacAutomatically();
      if (auto != null && _isValidMac(auto)) {
        return auto;
      }
    }

    // 2) ابحث عن قيمة يدوية محفوظة
    final prefs = await SharedPreferences.getInstance();
    final manual = prefs.getString(_prefsKeyManualMac);
    if (manual != null && _isValidMac(manual)) {
      debugPrint('[MacUtils] ℹ️ Using manual MAC: $manual');
      return manual;
    }

    // 3) لا شيء متاح
    return null;
  }

  // ============================================
  // === الحفظ اليدوي ===
  // ============================================

  /// حفظ MAC يدويًا (يُستخدم عند فشل القراءة التلقائية)
  static Future<bool> saveManualMac(String mac) async {
    final normalized = _normalizeMac(mac);
    if (!_isValidMac(normalized)) {
      debugPrint('[MacUtils] Invalid MAC format: $mac');
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyManualMac, normalized);
    debugPrint('[MacUtils] ✅ Manual MAC saved: $normalized');
    return true;
  }

  /// حذف MAC اليدوي (لو أراد المستخدم إعادة الإدخال)
  static Future<void> clearManualMac() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyManualMac);
    debugPrint('[MacUtils] Manual MAC cleared');
  }

  /// هل يوجد MAC يدوي محفوظ؟
  static Future<bool> hasManualMac() async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString(_prefsKeyManualMac);
    return mac != null && _isValidMac(mac);
  }

  // ============================================
  // === أدوات داخلية ===
  // ============================================

  /// تطبيع صيغة MAC:
  ///   "bcd1d3445566" → "BC:D1:D3:44:55:66"
  ///   "bc:d1:d3:44:55:66" → "BC:D1:D3:44:55:66"
  ///   "BC-D1-D3-44-55-66" → "BC:D1:D3:44:55:66"
  static String _normalizeMac(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleaned.length != 12) return raw.toUpperCase();

    final buf = StringBuffer();
    for (var i = 0; i < 12; i += 2) {
      if (i > 0) buf.write(':');
      buf.write(cleaned.substring(i, i + 2));
    }
    return buf.toString().toUpperCase();
  }

  /// التحقق من صحة صيغة MAC
  static bool _isValidMac(String mac) {
    if (mac.isEmpty) return false;
    if (mac == _unavailableMac) return false;
    if (mac == '00:00:00:00:00:00') return false;

    // صيغة قياسية: XX:XX:XX:XX:XX:XX
    final regex = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');
    return regex.hasMatch(mac.toUpperCase());
  }

  /// نسخة عامة للتحقق من صحة MAC (لاستخدامها من شاشة الإدخال)
  static bool validate(String mac) => _isValidMac(_normalizeMac(mac));

  /// تطبيع عام للاستخدام الخارجي
  static String normalize(String mac) => _normalizeMac(mac);
}
