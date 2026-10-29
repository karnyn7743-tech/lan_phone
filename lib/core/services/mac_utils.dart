import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// أدوات التعامل مع عنوان MAC الخاص بالواي فاي
///
/// ملاحظة مهمة:
///   Android 10+ يمنع الوصول البرمجي إلى عنوان MAC الحقيقي
///   لأسباب أمنية. لذلك التطبيق يطلب من المستخدم إدخاله يدويًا
///   مرة واحدة، ويحفظه للاستخدام في المرات القادمة.
/// ============================================================
class MacUtils {
  MacUtils._();

  static const String _prefsKeyManualMac = 'manual_wifi_mac';

  // ============================================
  // === القراءة من التخزين ===
  // ============================================

  /// الحصول على عنوان MAC المحفوظ (أو null إن لم يوجد)
  static Future<String?> getSavedMac() async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString(_prefsKeyManualMac);
    if (mac == null || mac.isEmpty) return null;
    if (!_isValidMac(mac)) return null;
    return mac;
  }

  // ============================================
  // === الحفظ ===
  // ============================================

  /// حفظ عنوان MAC (يُستخدم عند إدخال المستخدم)
  static Future<bool> saveMac(String mac) async {
    final normalized = _normalizeMac(mac);
    if (!_isValidMac(normalized)) {
      debugPrint('[MacUtils] Invalid MAC format: $mac');
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyManualMac, normalized);
    debugPrint('[MacUtils] ✅ MAC saved: $normalized');
    return true;
  }

  /// حذف عنوان MAC (لو أراد المستخدم إعادة الإدخال)
  static Future<void> clearMac() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyManualMac);
    debugPrint('[MacUtils] MAC cleared');
  }

  // ============================================
  // === التحقق ===
  // ============================================

  /// هل يوجد عنوان MAC محفوظ؟
  static Future<bool> hasSavedMac() async {
    return await getSavedMac() != null;
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
    if (cleaned.length != 12) return raw.trim().toUpperCase();

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
    if (mac == '02:00:00:00:00:00') return false;
    if (mac == '00:00:00:00:00:00') return false;

    // صيغة قياسية: XX:XX:XX:XX:XX:XX
    final regex = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');
    return regex.hasMatch(mac.toUpperCase());
  }

  /// التحقق العام (لاستخدامها من شاشة الإدخال)
  static bool validate(String mac) => _isValidMac(_normalizeMac(mac));

  /// تطبيع عام للاستخدام الخارجي
  static String normalize(String mac) => _normalizeMac(mac);
}
