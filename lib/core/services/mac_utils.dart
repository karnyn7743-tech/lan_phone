import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class MacUtils {
  static const String _prefKeyHardwareId = 'app_unique_hardware_id';

  /// استخراج معرّف فريد ومستقر للجهاز لا يتأثر بقيود أندرويد 10+
  static Future<String> getDeviceIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    
    // إذا كان المعرّف محفوظاً مسبقاً، استخدمه لضمان عدم تغيير مفتاح التفعيل
    String? savedId = prefs.getString(_prefKeyHardwareId);
    if (savedId != null && savedId.isNotEmpty) {
      return savedId;
    }

    final deviceInfo = DeviceInfoPlugin();
    String rawId = '';

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // استخدام المعرف الثابت للأندرويد
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

    // توليد تجزئة SHA-256 نظيفة كمعرف ثابت للجهاز
    final generatedId = sha256.convert(utf8.encode(rawId)).toString().substring(0, 16).toUpperCase();
    await prefs.setString(_prefKeyHardwareId, generatedId);
    return generatedId;
  }
}
