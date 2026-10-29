import 'dart:convert';
import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// خدمة تنشيط التطبيق
/// ------------------------------------------------
/// كل مفتاح مُشتق رياضياً من:
///   1) معرّف هذا الجهاز (Android ID الحقيقي / iOS identifierForVendor)
///   2) سر هذا التطبيق (خاص بمشروع LanPhone فقط)
///   3) معرّف التطبيق الصريح (يضمن عدم التسريب لتطبيقات أخرى)
///
/// الخصائص:
///   ✅ مفتاح الجهاز A لا يعمل على الجهاز B
///   ✅ مفتاح تطبيقنا لا يعمل في أي تطبيق آخر
///   ✅ مفتاح أي تطبيق آخر لا يعمل في تطبيقنا
///   ✅ ثابت عند إعادة التثبيت
/// ============================================================
class ActivationService extends ChangeNotifier {
  ActivationService() {
    _init();
  }

  // ============================================
  // === مفاتيح SharedPreferences ===
  // ============================================
  static const String _keyActivatedDeviceId = 'activation_device_id';
  static const String _keyActivatedKeyHash = 'activation_key_hash';

  // ============================================
  // === السرّان (مُقسَّمان لتشويش) ===
  // ============================================
  /// ⚠️ مهم: غيّر هذه القيم إلى قيم فريدة قبل النشر
  /// غيّر كل مقطع، ولا تستخدم نفس القيم الموجودة هنا.

  /// السرّ الأول — يُستخدم في أول طبقة hash
  static const List<String> _secretPartA = [
    'Lan',
    'Phone',
    '-Act',
    '-A1',
    '-2024',
    '-7kXz',
  ];

  /// السرّ الثاني — يُستخدم في الطبقة الثانية
  static const List<String> _secretPartB = [
    'Lp',
    'Sec',
    '-B2',
    '-2024',
    '-9mNq',
  ];

  /// معرّف التطبيق الصريح (يُدخل بين السرّين)
  static const String _appIdentifier = 'com.lanphone.app.v1';

  static String get _secretA => _secretPartA.join();
  static String get _secretB => _secretPartB.join();

  // ============================================
  // === الحالة ===
  // ============================================
  bool _checking = true;
  bool get checking => _checking;

  bool _activated = false;
  bool get activated => _activated;

  String _deviceId = '';
  String get deviceId => _deviceId;

  String? _error;
  String? get error => _error;

  // ============================================
  // === التهيئة ===
  // ============================================

  Future<void> _init() async {
    try {
      final id = await _getStableDeviceId();
      _deviceId = id;

      debugPrint('[Activation] Stable device ID: $_deviceId');

      final prefs = await SharedPreferences.getInstance();
      final savedDeviceId = prefs.getString(_keyActivatedDeviceId);
      final savedKeyHash = prefs.getString(_keyActivatedKeyHash);

      if (savedDeviceId == _deviceId && savedKeyHash != null) {
        final expectedKey = generateExpectedKey(_deviceId);
        final expectedHash = _hashKey(expectedKey);
        _activated = (savedKeyHash == expectedHash);
        debugPrint('[Activation] Saved state: activated=$_activated');
      } else {
        _activated = false;
        debugPrint('[Activation] No saved activation');
      }

      _checking = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Activation] init error: $e');
      _checking = false;
      _activated = false;
      notifyListeners();
    }
  }

  // ============================================
  // === معرّف الجهاز الثابت (مُحدَّث) ===
  // ============================================

  Future<String> _getStableDeviceId() async {
    try {
      if (Platform.isAndroid) {
        // ✅ المحاولة الأولى: Android ID الحقيقي
        // (16 حرف hex — فريد لكل جهاز، حتى بين نفس الموديل)
        try {
          const androidId = AndroidId();
          final id = await androidId.getId();
          if (id != null &&
              id.isNotEmpty &&
              id != 'unknown' &&
              id != '0') {
            debugPrint('[Activation] ✅ Real Android ID: $id');
            return 'ANDROID-$id';
          }
        } catch (e) {
          debugPrint('[Activation] android_id package error: $e');
        }

        // ⚠️ Fallback: إذا فشل Android ID → استخدم device_info_plus
        // لكن هذا قد يُعطي نفس المعرّف للأجهزة المتطابقة
        try {
          final plugin = DeviceInfoPlugin();
          final info = await plugin.androidInfo;
          final fallbackId =
              '${info.id}-${info.fingerprint.hashCode}-${info.device.hashCode}';
          debugPrint('[Activation] ⚠️ Fallback device ID: $fallbackId');
          return 'ANDROID-$fallbackId';
        } catch (e) {
          debugPrint('[Activation] device_info_plus error: $e');
        }

        // آخر حل: معرّف عشوائي محفوظ
        final prefs = await SharedPreferences.getInstance();
        var fallback = prefs.getString('fallback_device_id');
        if (fallback == null || fallback.isEmpty) {
          fallback =
              'fallback-${DateTime.now().millisecondsSinceEpoch}-${identityHashCode(this)}';
          await prefs.setString('fallback_device_id', fallback);
        }
        debugPrint('[Activation] ⚠️ Emergency fallback: $fallback');
        return 'ANDROID-$fallback';
      }

      if (Platform.isIOS) {
        final plugin = DeviceInfoPlugin();
        final info = await plugin.iosInfo;
        return 'IOS-${info.identifierForVendor ?? ''}';
      }

      return 'UNKNOWN-${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('[Activation] getStableDeviceId error: $e');
      return 'FALLBACK-$e';
    }
  }

  // ============================================
  // === توليد المفتاح — 3 طبقات تشفير ===
  // ============================================

  /// توليد المفتاح المتوقع لهذا الجهاز
  ///
  /// الطبقة 1: hash(deviceId + A)
  /// الطبقة 2: hash(hash1 + appIdentifier + B)
  /// الطبقة 3: تحويل إلى 16 حرف hex + تنسيق
  String generateExpectedKey(String deviceId) {
    // ✅ الطبقة 1
    final layer1 = sha256.convert(
      utf8.encode('$deviceId:$_secretA'),
    ).toString();

    // ✅ الطبقة 2 (يُدخل معرّف التطبيق بين السرّين)
    final layer2 = sha256.convert(
      utf8.encode('$layer1:$_appIdentifier:$_secretB'),
    ).toString();

    // ✅ الطبقة 3: نأخذ 16 حرف من الطبقة 2
    final hex = layer2.toUpperCase();
    final part = hex.substring(0, 16);

    return '${part.substring(0, 4)}-'
        '${part.substring(4, 8)}-'
        '${part.substring(8, 12)}-'
        '${part.substring(12, 16)}';
  }

  // ============================================
  // === التنشيط ===
  // ============================================

  Future<bool> activate(String inputKey) async {
    _error = null;

    final normalized = _normalizeKey(inputKey);

    if (normalized.length != 16) {
      _error = 'المفتاح يجب أن يكون 16 حرفًا (بصيغة XXXX-XXXX-XXXX-XXXX)';
      notifyListeners();
      return false;
    }

    final expectedKey = generateExpectedKey(_deviceId);
    final expectedNormalized = _normalizeKey(expectedKey);

    if (normalized != expectedNormalized) {
      _error = 'المفتاح غير صحيح لهذا الجهاز';
      notifyListeners();
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyActivatedDeviceId, _deviceId);
      await prefs.setString(_keyActivatedKeyHash, _hashKey(expectedKey));

      _activated = true;
      _error = null;
      notifyListeners();
      debugPrint('[Activation] Successfully activated!');
      return true;
    } catch (e) {
      debugPrint('[Activation] save error: $e');
      _error = 'تعذّر حفظ التنشيط';
      notifyListeners();
      return false;
    }
  }

  // ============================================
  // === إلغاء التنشيط (للتطوير) ===
  // ============================================

  Future<void> deactivate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyActivatedDeviceId);
      await prefs.remove(_keyActivatedKeyHash);
      _activated = false;
      notifyListeners();
      debugPrint('[Activation] Deactivated');
    } catch (e) {
      debugPrint('[Activation] deactivate error: $e');
    }
  }

  // ============================================
  // === أدوات ===
  // ============================================

  String _normalizeKey(String input) {
    return input.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
  }

  String _hashKey(String key) {
    return sha256.convert(utf8.encode(key)).toString();
  }

  String formatKey(String raw) {
    final s = _normalizeKey(raw);
    if (s.length != 16) return raw;
    return '${s.substring(0, 4)}-'
        '${s.substring(4, 8)}-'
        '${s.substring(8, 12)}-'
        '${s.substring(12, 16)}';
  }
}
