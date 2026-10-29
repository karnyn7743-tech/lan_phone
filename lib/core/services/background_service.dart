import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// ============================================================
/// خدمة الخلفية المستمرة لـ LanPhone
///
/// الهدف:
///   إبقاء عملية التطبيق نشطة في الخلفية، حتى تستمر
///   SignalingService و DeviceDiscovery في العمل واستقبال
///   إشارات المكالمات الواردة حتى عندما يكون التطبيق
///   في الخلفية أو الشاشة مقفلة.
///
/// ملاحظة معمارية:
///   لا ننقل SignalingService إلى isolate الخلفية — بل
///   نُبقيها في الـ main isolate ونحميها من التجميد عبر
///   Foreground Service، لأن هذا أقل تغييرًا معماريًا.
/// ============================================================
class BackgroundServiceManager {
  BackgroundServiceManager._();

  static final BackgroundServiceManager instance =
      BackgroundServiceManager._();

  static const String _channelId = 'lanphone_service_channel';
  static const int _notificationId = 9001;

  bool _initialized = false;

  /// بدء الخدمة (يُستدعى من main)
  Future<void> start() async {
    if (!Platform.isAndroid) return;
    if (_initialized) return;

    try {
      final service = FlutterBackgroundService();

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onServiceStart,
          autoStart: true,
          autoStartOnBoot: true,
          isForegroundMode: true,
          notificationChannelId: _channelId,
          initialNotificationTitle: 'LanPhone',
          initialNotificationContent: 'جاهز لاستقبال المكالمات',
          foregroundServiceNotificationId: _notificationId,
          // ✅ جديد — استخدام الأيقونة المخصصة (drawable/ic_stat_lanphone.xml)
          icon: 'ic_stat_lanphone',
          // ⚠️ الأنواع يجب أن تطابق الأذونات المعلنة في Manifest
          foregroundServiceTypes: const [
            AndroidForegroundType.phoneCall,
            AndroidForegroundType.microphone,
            AndroidForegroundType.connectedDevice,
          ],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: true,
          onForeground: _onServiceStart,
          onBackground: _onIosBackground,
        ),
      );

      await service.startService();
      _initialized = true;
      debugPrint('[BackgroundService] ✅ Started');
    } catch (e) {
      debugPrint('[BackgroundService] start error: $e');
    }
  }

  /// إيقاف الخدمة (اختياري — يُستخدم عند إغلاق التطبيق يدويًا)
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      FlutterBackgroundService().invoke('stopService');
      _initialized = false;
      debugPrint('[BackgroundService] Stopped');
    } catch (e) {
      debugPrint('[BackgroundService] stop error: $e');
    }
  }

  /// هل الخدمة تعمل؟
  Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    return FlutterBackgroundService().isRunning();
  }
}

// ============================================================
// === نقطة دخول الخدمة (تعمل في isolate منفصل) ===
// ============================================================
@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    // ✅ إبقاء الخدمة في وضع Foreground دائمًا
    service.setAsForegroundService();

    // استقبال أوامر من الواجهة
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });

    // تحديث محتوى الإشعار ديناميكيًا (اختياري)
    service.on('updateNotification').listen((event) {
      final title = event?['title'] as String? ?? 'LanPhone';
      final content = event?['content'] as String? ??
          'جاهز لاستقبال المكالمات';
      service.setForegroundNotificationInfo(
        title: title,
        content: content,
      );
    });
  }

  // استقبال أمر الإيقاف
  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  // لا نفعل شيئًا آخر — الهدف فقط إبقاء العملية نشطة
  // SignalingService و DeviceDiscovery يعملان في الـ main isolate
  debugPrint('[BackgroundService] Isolate running');
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  return true;
}
