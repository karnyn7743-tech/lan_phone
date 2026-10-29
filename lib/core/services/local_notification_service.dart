import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/database/database_helper.dart';

/// ============================================================
/// خدمة الإشعارات المحلية
/// ------------------------------------------------
/// تعرض إشعارات للرسائل الجديدة مع احترام
/// الإعدادات المخصصة لكل جهاز
/// ============================================================
class LocalNotificationService {
  // ============================================
  // === Singleton ===
  // ============================================
  LocalNotificationService._internal();
  static final LocalNotificationService instance =
      LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ============================================
  // === Callbacks للتنقل ===
  // ============================================
  Function(String peerDeviceId, String? messageId)? onMessageTap;

  // ============================================
  // === Channels ===
  // ============================================
  /// قناة الإشعارات الصامتة (رسائل من أجهزة مُسكتة)
  static const String _silentChannelId = 'lanphone_messages_silent';
  static const String _silentChannelName = 'رسائل صامتة';
  static const String _silentChannelDesc = 'رسائل بدون صوت أو اهتزاز';

  /// قناة الإشعارات مع صوت
  static const String _soundChannelId = 'lanphone_messages_sound';
  static const String _soundChannelName = 'رسائل بصوت';
  static const String _soundChannelDesc = 'رسائل مع صوت';

  /// قناة الإشعارات مع اهتزاز
  static const String _vibrateChannelId = 'lanphone_messages_vibrate';
  static const String _vibrateChannelName = 'رسائل بالاهتزاز';
  static const String _vibrateChannelDesc = 'رسائل مع اهتزاز';

  /// قناة الإشعارات الكاملة (صوت + اهتزاز)
  static const String _fullChannelId = 'lanphone_messages_full';
  static const String _fullChannelName = 'رسائل كاملة';
  static const String _fullChannelDesc = 'رسائل مع صوت واهتزاز';

  // ============================================
  // === التهيئة ===
  // ============================================

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            _onBackgroundNotificationResponse,
      );

      await _createAndroidChannels();

      _initialized = true;
      debugPrint('[Notifications] Initialized');
    } catch (e) {
      debugPrint('[Notifications] init error: $e');
    }
  }

  Future<void> _createAndroidChannels() async {
    if (!Platform.isAndroid) return;

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    // قناة صامتة
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _silentChannelId,
        _silentChannelName,
        description: _silentChannelDesc,
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: true,
      ),
    );

    // قناة الصوت فقط
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _soundChannelId,
        _soundChannelName,
        description: _soundChannelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: false,
        showBadge: true,
      ),
    );

    // قناة الاهتزاز فقط
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _vibrateChannelId,
        _vibrateChannelName,
        description: _vibrateChannelDesc,
        importance: Importance.high,
        playSound: false,
        enableVibration: true,
        showBadge: true,
      ),
    );

    // قناة كاملة
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _fullChannelId,
        _fullChannelName,
        description: _fullChannelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  // ============================================
  // === معالجة الضغط على الإشعار ===
  // ============================================

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final peerDeviceId = data['peerDeviceId'] as String?;
      final messageId = data['messageId'] as String?;

      if (peerDeviceId != null) {
        debugPrint(
          '[Notifications] Tapped: peer=$peerDeviceId, msg=$messageId',
        );
        onMessageTap?.call(peerDeviceId, messageId);
      }
    } catch (e) {
      debugPrint('[Notifications] parse payload error: $e');
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(
    NotificationResponse response,
  ) {
    debugPrint('[Notifications] Background tap: ${response.payload}');
  }

  // ============================================
  // === عرض إشعار رسالة ===
  // ============================================

  /// عرض إشعار رسالة جديدة مع احترام إعدادات الجهاز
  Future<void> showMessageNotification({
    required String peerDeviceId,
    required String peerName,
    String? peerNumber,
    required String body,
    String? messageId,
    String? conversationId,
  }) async {
    if (!_initialized) await init();

    try {
      // 1) اجلب إعدادات الجهاز
      final settings =
          await DatabaseHelper.instance.getNotificationSettings(peerDeviceId);

      final isEnabled = (settings['enabled'] as int?) == 1;
      final hasSound = (settings['sound'] as int?) == 1;
      final hasVibration = (settings['vibration'] as int?) == 1;

      // 2) إذا الإشعارات متوقفة → لا شيء
      if (!isEnabled) {
        debugPrint(
          '[Notifications] Skipped (disabled): $peerName',
        );
        return;
      }

      // 3) عنوان الإشعار
      final title = peerNumber != null && peerNumber.isNotEmpty
          ? '$peerName • #$peerNumber'
          : peerName;

      // 4) محتوى الإشعار
      final preview = _truncate(body, 100);

      // 5) Payload
      final payload = jsonEncode({
        'peerDeviceId': peerDeviceId,
        'messageId': messageId,
        'conversationId': conversationId,
        'type': 'message',
      });

      // 6) اختر القناة المناسبة
      final channel = _selectChannel(
        hasSound: hasSound,
        hasVibration: hasVibration,
      );

      // 7) إعدادات أندرويد
      final androidDetails = AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: _priorityFromImportance(channel.importance),
        showWhen: true,
        icon: '@mipmap/ic_launcher',
        playSound: hasSound,
        enableVibration: hasVibration,
        styleInformation: BigTextStyleInformation(
          preview,
          contentTitle: title,
          summaryText: 'LanPhone',
        ),
        groupKey: conversationId ?? peerDeviceId,
        autoCancel: true,
        onlyAlertOnce: false,
      );

      // 8) إعدادات iOS
      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: hasSound,
        interruptionLevel: hasSound
            ? InterruptionLevel.active
            : InterruptionLevel.passive,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // 9) معرّف الإشعار (نفس لكل رسالة في نفس المحادثة)
      final notificationId = peerDeviceId.hashCode & 0x7FFFFFFF;

      await _plugin.show(
        notificationId,
        title,
        preview,
        details,
        payload: payload,
      );

      debugPrint(
        '[Notifications] Shown: $peerName '
        '(sound=$hasSound, vib=$hasVibration)',
      );
    } catch (e) {
      debugPrint('[Notifications] showMessage error: $e');
    }
  }

  // ============================================
  // === اختيار القناة ===
  // ============================================

  _ChannelInfo _selectChannel({
    required bool hasSound,
    required bool hasVibration,
  }) {
    if (hasSound && hasVibration) {
      return const _ChannelInfo(
        id: _fullChannelId,
        name: _fullChannelName,
        description: _fullChannelDesc,
        importance: Importance.high,
      );
    }
    if (hasSound) {
      return const _ChannelInfo(
        id: _soundChannelId,
        name: _soundChannelName,
        description: _soundChannelDesc,
        importance: Importance.high,
      );
    }
    if (hasVibration) {
      return const _ChannelInfo(
        id: _vibrateChannelId,
        name: _vibrateChannelName,
        description: _vibrateChannelDesc,
        importance: Importance.high,
      );
    }
    return const _ChannelInfo(
      id: _silentChannelId,
      name: _silentChannelName,
      description: _silentChannelDesc,
      importance: Importance.low,
    );
  }

  Priority _priorityFromImportance(Importance importance) {
    switch (importance) {
      case Importance.min:
        return Priority.min;
      case Importance.low:
        return Priority.low;
      case Importance.defaultImportance:
        return Priority.defaultPriority;
      case Importance.high:
        return Priority.high;
      case Importance.max:
        return Priority.max;
    }
  }

  // ============================================
  // === إلغاء الإشعارات ===
  // ============================================

  Future<void> cancelForDevice(String peerDeviceId) async {
    if (!_initialized) return;
    try {
      final id = peerDeviceId.hashCode & 0x7FFFFFFF;
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('[Notifications] cancel error: $e');
    }
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('[Notifications] cancelAll error: $e');
    }
  }

  // ============================================
  // === طلب الأذونات ===
  // ============================================

  Future<bool> requestPermission() async {
    if (!_initialized) await init();

    try {
      if (Platform.isAndroid) {
        final androidPlugin = _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        final granted =
            await androidPlugin?.requestNotificationsPermission();
        return granted ?? false;
      }

      if (Platform.isIOS) {
        final iosPlugin = _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        final granted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }

      return true;
    } catch (e) {
      debugPrint('[Notifications] requestPermission error: $e');
      return false;
    }
  }

  // ============================================
  // === أدوات ===
  // ============================================

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}

// ============================================================
// === نموذج معلومات القناة ===
// ============================================================
class _ChannelInfo {
  final String id;
  final String name;
  final String description;
  final Importance importance;

  const _ChannelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.importance,
  });
}
