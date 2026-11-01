import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MacUtils {
  static const String _prefKeyHardwareId = 'app_unique_hardware_id';
  static const String _prefKeySavedMac = 'saved_device_mac';

  /// استخراج معرّف فريد ومستقر للجهاز
  static Future<String> getDeviceIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedId = prefs.getString(_prefKeyHardwareId);
    if (savedId != null && savedId.isNotEmpty) {
      return savedId;
    }

    final deviceInfo = DeviceInfoPlugin();
    String rawId = '';

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        rawId = '${androidInfo.id}_${androidInfo.model}_${androidInfo.brand}';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        rawId = windowsInfo.deviceId;
      } else {
        rawId = DateTime.now().millisecondsSinceEpoch.toString();
      }
    } catch (_) {
      rawId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    final generatedId = sha256.convert(utf8.encode(rawId)).toString().substring(0, 16).toUpperCase();
    await prefs.setString(_prefKeyHardwareId, generatedId);
    return generatedId;
  }

  /// قراءة الماك المحفوظ (أو المعرف البديل)
  static Future<String?> getSavedMac() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKeySavedMac);
    if (saved != null && saved.isNotEmpty) return saved;
    return await getDeviceIdentifier();
  }

  /// حفظ الماك أو المعرف
  static Future<void> saveMac(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySavedMac, mac.trim().toUpperCase());
  }

  /// التحقق من صحة الصيغة (يقبل صيغة الـ MAC أو معرّف بطول 12-17 خانة)
  static bool validate(String mac) {
    if (mac.trim().isEmpty) return false;
    final clean = mac.trim().toUpperCase();
    
    // فحص صيغة الـ MAC التقليدية XX:XX:XX:XX:XX:XX
    final macRegex = RegExp(r'^([0-9A-F]{2}[:-]){5}([0-9A-F]{2})$');
    if (macRegex.hasMatch(clean)) return true;

    // فحص المعرفات بدون فواصل (12 إلى 16 حرف/رقم)
    final hexRegex = RegExp(r'^[0-9A-F]{12,16}$');
    return hexRegex.hasMatch(clean);
  }
}
