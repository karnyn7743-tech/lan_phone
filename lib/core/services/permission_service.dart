import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart'
    as ph; // ← استيراد مُسمّى لتجنب التعارض

/// ============================================================
/// خدمة إدارة الأذونات
/// تتعامل مع الفروق بين إصدارات Android وتطلب الأذونات بذكاء
/// ============================================================
class PermissionService {
  PermissionService._();

  // ============================================
  // === الأذونات المطلوبة حسب المجموعة ===
  // ============================================

  /// أذونات لاكتشاف الأجهزة على الشبكة المحلية
  static List<ph.Permission> get _discoveryPermissions {
    return <ph.Permission>[
      ph.Permission.locationWhenInUse,
      ph.Permission.nearbyWifiDevices,
    ];
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
    // Android 13+ يستخدم أذونات منفصلة للصور/الفيديو/الصوت
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

  /// طلب أذونات الاكتشاف (يُطلب عند بدء التطبيق)
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

  /// طلب الأذونات الأساسية عند أول تشغيل
  static Future<PermissionSummary> requestEssentialAtStartup() async {
    final discoveryOk = await requestDiscovery();
    final notificationsOk = await requestNotifications();

    return PermissionSummary(
      discoveryGranted: discoveryOk,
      notificationsGranted: notificationsOk,
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
  /// ✅ الآن تعمل بشكل صحيح — تستدعي دالة permission_handler الأصلية
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

  /// طلب أذونات مع نتيجة واضحة (للعرض في واجهة)
  static Future<PermissionResult> requestWithGuidance(
    List<ph.Permission> permissions,
    String reason,
  ) async {
    // 1) هل مُمنوحة أصلًا؟
    if (await checkAll(permissions)) {
      return PermissionResult.alreadyGranted();
    }

    // 2) هل مرفوضة نهائيًا؟
    if (await isPermanentlyDenied(permissions)) {
      return PermissionResult.permanentlyDenied();
    }

    // 3) اطلبها
    final granted = await requestAll(permissions);
    if (granted) {
      return PermissionResult.granted();
    }

    // 4) رُفضت للتو
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
  final bool audioCallGranted;
  final bool videoCallGranted;
  final bool mediaGranted;

  const PermissionSummary({
    required this.discoveryGranted,
    required this.notificationsGranted,
    required this.audioCallGranted,
    required this.videoCallGranted,
    required this.mediaGranted,
  });

  bool get isEssentialOk => discoveryGranted;
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
