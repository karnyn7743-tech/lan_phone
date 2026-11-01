import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart'
    as ph; // ← استيراد مُسمّى لتجنب التعارض

/// ============================================================
/// خدمة إدارة الأذونات
/// تتعامل مع الفروق بين إصدارات Android وتطلب الأذونات بذكاء
/// مع دعم فحص وإلغاء قيود توفير البطارية (Doze Mode)
/// ============================================================
class PermissionService {
  PermissionService._();

  // ============================================
  // === الأذونات المطلوبة حسب المجموعة ===
  // ============================================

  /// اكتشاف الأجهزة عبر UDP وMulticast
  static List<ph.Permission> get _discoveryPermissions {
    if (Platform.isIOS) {
      return <ph.Permission>[ph.Permission.locationWhenInUse];
    }
    return <ph.Permission>[];
  }

  /// أذونات المكالمات الصوتية
  static List<ph.Permission> get _audioCallPermissions => [
        ph.Permission.microphone,
        ph.Permission.bluetoothConnect,
      ];

  /// أذونات مكالمات الفيديو
  static List<ph.Permission> get _videoCallPermissions => [
        ph.Permission.microphone,
        ph.Permission.camera,
        ph.Permission.bluetoothConnect,
      ];

  /// أذونات الوسائط والملفات
  static List<ph.Permission> get _mediaPermissions {
    if (Platform.isAndroid) {
      return [
        ph.Permission.photos,
        ph.Permission.videos,
        ph.Permission.audio,
        ph.Permission.storage,
      ];
    }
    return [ph.Permission.photos, ph.Permission.storage];
  }

  /// أذونات الإشعارات
  static List<ph.Permission> get _notificationPermissions => [
        ph.Permission.notification,
      ];

  // ============================================
  // === إدارة قيود تحسين البطارية (Doze Mode) ===
  // ============================================

  /// فحص هل التطبيق مستثنى من قيود تحسين البطارية
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await ph.Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (e) {
      debugPrint('[Permissions] isBatteryOptimizationIgnored error: $e');
      return false;
    }
  }

  /// طلب استثناء التطبيق من تحسين البطارية لضمان بقاء المقابس والاتصالات حية
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await ph.Permission.ignoreBatteryOptimizations.request();
      debugPrint('[Permissions] Battery optimization status: $status');
      return status.isGranted;
    } catch (e) {
      debugPrint('[Permissions] requestIgnoreBatteryOptimizations error: $e');
      return false;
    }
  }

  // ============================================
  // === الطلب الأساسي ===
  // ============================================

  /// طلب مجموعة أذونات دفعة واحدة
  /// يُرجع true إذا مُنحت كل الأذونات
  static Future<bool> requestAll(List<ph.Permission> permissions) async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    try {
      final statuses = await permissions.request();

      for (final status in statuses.values) {
        if (!status.isGranted && !status.isLimited) {
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[Permissions] requestAll error: $e');
      return false;
    }
  }

  /// فحص هل كل الأذونات مُمنوحة (بدون طلب)
  static Future<bool> checkAll(List<ph.Permission> permissions) async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    try {
      for (final p in permissions) {
        final status = await p.status;
        if (!status.isGranted && !status.isLimited) {
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[Permissions] checkAll error: $e');
      return false;
    }
  }

  // ============================================
  // === طلبات جاهزة (High-Level) ===
  // ============================================

  /// فحص/طلب أذونات الاكتشاف
  static Future<bool> requestDiscovery() async {
    return requestAll(_discoveryPermissions);
  }

  /// طلب أذونات المكالمة الصوتية
  static Future<bool> requestAudioCall() async {
    return requestAll(_audioCallPermissions);
  }

  /// طلب أذونات مكالمة الفيديو
  static Future<bool> requestVideoCall() async {
    return requestAll(_videoCallPermissions);
  }

  /// طلب أذونات الوسائط
  static Future<bool> requestMedia() async {
    return requestAll(_mediaPermissions);
  }

  /// طلب أذونات الإشعارات
  static Future<bool> requestNotifications() async {
    return requestAll(_notificationPermissions);
  }

  /// طلب الأذونات الأساسية عند أول تشغيل (بما في ذلك فحص قيود البطارية)
  static Future<PermissionSummary> requestEssentialAtStartup() async {
    final discoveryOk = await requestDiscovery();
    final notificationsOk = await requestNotifications();
    
    // طلب استثناء توفير البطارية لضمان عدم إيقاف استقبال الاتصالات
    bool batteryIgnored = await isBatteryOptimizationIgnored();
    if (!batteryIgnored) {
      batteryIgnored = await requestIgnoreBatteryOptimizations();
    }

    return PermissionSummary(
      discoveryGranted: discoveryOk,
      notificationsGranted: notificationsOk,
      batteryOptimizationIgnored: batteryIgnored,
      audioCallGranted: false,
      videoCallGranted: false,
      mediaGranted: false,
    );
  }

  // ============================================
  // === فحوصات سريعة (بدون طلب) ===
  // ============================================

  static Future<bool> hasMicPermission() async {
    final s = await ph.Permission.microphone.status;
    return s.isGranted;
  }

  static Future<bool> hasCameraPermission() async {
    final s = await ph.Permission.camera.status;
    return s.isGranted;
  }

  static Future<bool> hasDiscoveryPermission() async {
    return checkAll(_discoveryPermissions);
  }

  static Future<bool> hasMediaPermission() async {
    return checkAll(_mediaPermissions);
  }

  // ============================================
  // === تفاصيل مفيدة ===
  // ============================================

  /// هل أحد الأذونات "مرفوض نهائيًا"؟
  static Future<bool> isPermanentlyDenied(
    List<ph.Permission> permissions,
  ) async {
    for (final p in permissions) {
      final status = await p.status;
      if (status.isPermanentlyDenied) return true;
    }
    return false;
  }

  /// فتح إعدادات التطبيق (لتفعيل الأذونات المرفوضة نهائيًا)
  static Future<bool> openAppSettings() async {
    try {
      return await ph.openAppSettings();
    } catch (e) {
      debugPrint('[Permissions] openAppSettings error: $e');
      return false;
    }
  }

  // ============================================
  // === طلب ذكي مع إرشاد المستخدم ===
  // ============================================

  static Future<PermissionResult> requestWithGuidance(
    List<ph.Permission> permissions,
    String reason,
  ) async {
    if (await checkAll(permissions)) {
      return PermissionResult.alreadyGranted();
    }

    if (await isPermanentlyDenied(permissions)) {
      return PermissionResult.permanentlyDenied();
    }

    final granted = await requestAll(permissions);
    if (granted) {
      return PermissionResult.granted();
    }

    if (await isPermanentlyDenied(permissions)) {
      return PermissionResult.permanentlyDenied();
    }

    return PermissionResult.denied();
  }
}

// ============================================================
// === نماذج النتائج ===
// ============================================================

class PermissionSummary {
  final bool discoveryGranted;
  final bool notificationsGranted;
  final bool batteryOptimizationIgnored;
  final bool audioCallGranted;
  final bool videoCallGranted;
  final bool mediaGranted;

  const PermissionSummary({
    required this.discoveryGranted,
    required this.notificationsGranted,
    required this.batteryOptimizationIgnored,
    required this.audioCallGranted,
    required this.videoCallGranted,
    required this.mediaGranted,
  });

  bool get isEssentialOk => discoveryGranted && notificationsGranted;
}

enum PermissionResultStatus {
  alreadyGranted,
  granted,
  denied,
  permanentlyDenied,
}

class PermissionResult {
  final PermissionResultStatus status;

  PermissionResult._(this.status);

  factory PermissionResult.alreadyGranted() =>
      PermissionResult._(PermissionResultStatus.alreadyGranted);

  factory PermissionResult.granted() =>
      PermissionResult._(PermissionResultStatus.granted);

  factory PermissionResult.denied() =>
      PermissionResult._(PermissionResultStatus.denied);

  factory PermissionResult.permanentlyDenied() =>
      PermissionResult._(PermissionResultStatus.permanentlyDenied);

  bool get isOk =>
      status == PermissionResultStatus.granted ||
      status == PermissionResultStatus.alreadyGranted;

  bool get shouldOpenSettings =>
      status == PermissionResultStatus.permanentlyDenied;
}
