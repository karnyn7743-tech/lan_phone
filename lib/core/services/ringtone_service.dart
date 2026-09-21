import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// أنواع الرنات المتاحة
/// ============================================================
enum RingtoneType {
  ringtone,
  alarm,
  notification,
  silent,
}

extension RingtoneTypeExt on RingtoneType {
  String get label {
    switch (this) {
      case RingtoneType.ringtone:
        return 'نغمة المكالمات';
      case RingtoneType.alarm:
        return 'نغمة المنبه';
      case RingtoneType.notification:
        return 'نغمة الإشعار';
      case RingtoneType.silent:
        return 'صامت';
    }
  }

  String get description {
    switch (this) {
      case RingtoneType.ringtone:
        return 'نغمة الرنين الافتراضية للهاتف';
      case RingtoneType.alarm:
        return 'نغمة المنبه القوية';
      case RingtoneType.notification:
        return 'نغمة إشعار خفيفة';
      case RingtoneType.silent:
        return 'بدون صوت (اهتزاز فقط)';
    }
  }

  String get storageKey {
    switch (this) {
      case RingtoneType.ringtone:
        return 'ringtone';
      case RingtoneType.alarm:
        return 'alarm';
      case RingtoneType.notification:
        return 'notification';
      case RingtoneType.silent:
        return 'silent';
    }
  }
}

/// ============================================================
/// خدمة الرنات
/// ============================================================
class RingtoneService extends ChangeNotifier {
  // ✅ مُنشئ عام (للتسجيل مع Provider)
  RingtoneService();

  static const String _keyRingtoneType = 'ringtone_type';

  // ============================================
  // === الحالة ===
  // ============================================
  RingtoneType _type = RingtoneType.ringtone;
  RingtoneType get type => _type;

  // ✅ التعديل هنا: إضافة الـ Getter المطلوب حلّاً لخطأ البناء
  String get currentRingtoneName => _type.label;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  // ============================================
  // === التهيئة ===
  // ============================================

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_keyRingtoneType) ?? 'ringtone';
      _type = _fromString(saved);
      debugPrint('[Ringtone] Loaded: ${_type.label}');
      notifyListeners();
    } catch (e) {
      debugPrint('[Ringtone] load error: $e');
    }
  }

  // ============================================
  // === التعديل ===
  // ============================================

  Future<void> setType(RingtoneType type) async {
    if (_type == type) return;

    _type = type;
    notifyListeners();

    try {
      await FlutterRingtonePlayer().stop();
      _isPlaying = false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyRingtoneType, type.storageKey);
      debugPrint('[Ringtone] Changed to: ${type.label}');
    } catch (e) {
      debugPrint('[Ringtone] setType error: $e');
    }
  }

  // ============================================
  // === المعاينة ===
  // ============================================

  Future<void> preview(RingtoneType type) async {
    try {
      await FlutterRingtonePlayer().stop();

      switch (type) {
        case RingtoneType.ringtone:
          await FlutterRingtonePlayer().playRingtone(
            looping: false,
            volume: 1.0,
          );
          break;
        case RingtoneType.alarm:
          await FlutterRingtonePlayer().playAlarm(
            looping: false,
            volume: 1.0,
          );
          break;
        case RingtoneType.notification:
          await FlutterRingtonePlayer().playNotification(
            volume: 1.0,
          );
          break;
        case RingtoneType.silent:
          break;
      }
    } catch (e) {
      debugPrint('[Ringtone] preview error: $e');
    }
  }

  // ============================================
  // === الرنين للمكالمات ===
  // ============================================

  Future<void> startRinging() async {
    if (_type == RingtoneType.silent) {
      debugPrint('[Ringtone] Silent — no ring');
      return;
    }

    try {
      switch (_type) {
        case RingtoneType.ringtone:
          await FlutterRingtonePlayer().playRingtone(
            looping: true,
            volume: 1.0,
          );
          break;
        case RingtoneType.alarm:
          await FlutterRingtonePlayer().playAlarm(
            looping: true,
            volume: 1.0,
          );
          break;
        case RingtoneType.notification:
          await FlutterRingtonePlayer().playNotification(
            looping: true,
            volume: 1.0,
          );
          break;
        case RingtoneType.silent:
          break;
      }
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[Ringtone] startRinging error: $e');
    }
  }

  Future<void> stopRinging() async {
    try {
      await FlutterRingtonePlayer().stop();
      _isPlaying = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Ringtone] stopRinging error: $e');
    }
  }

  // ============================================
  // === أدوات ===
  // ============================================

  RingtoneType _fromString(String s) {
    switch (s) {
      case 'alarm':
        return RingtoneType.alarm;
      case 'notification':
        return RingtoneType.notification;
      case 'silent':
        return RingtoneType.silent;
      default:
        return RingtoneType.ringtone;
    }
  }
}
