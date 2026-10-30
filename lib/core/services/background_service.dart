import 'dart:async';
import 'dart:io';
import 'dart:ui'; // لتعريف DartPluginRegistrant

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// ============================================================
/// خدمة الخلفية المستمرة لـ LanPhone
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
          // ✅ التعديل الجوهري: استخدام connectedDevice بدلاً من phoneCall
          // لتجنب انهيار التطبيق على Android 14+
          foregroundServiceTypes: const [
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

  /// إيقاف الخدمة
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

  Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    return FlutterBackgroundService().isRunning();
  }
}

// ============================================================
// === نقطة دخول الخدمة ===
// ============================================================
@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });

    service.on('updateNotification').listen((event) {
      final title = event?['title'] as String? ?? 'LanPhone';
      final content = event?['content'] as String? ?? 'جاهز لاستقبال المكالمات';
      service.setForegroundNotificationInfo(
        title: title,
        content: content,
      );
    });
  }

  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  debugPrint('[BackgroundService] Isolate running');
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  return true;
}
