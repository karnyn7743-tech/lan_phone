import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// ============================================================
/// خدمة الإشعارات والمكالمات الواردة — CallKit Incoming Service
/// ============================================================
class NotificationService extends ChangeNotifier {
  NotificationService() {
    _init();
  }

  // ============================================
  // === المراجع ===
  // ============================================
  StreamSubscription<CallEvent?>? _eventSubscription;

  // ============================================
  // === Stream للأحداث ===
  // ============================================
  final StreamController<CallEvent?> _eventController =
      StreamController<CallEvent?>.broadcast();
  Stream<CallEvent?> get callEvents => _eventController.stream;

  // ============================================
  // === التهيئة ===
  // ============================================

  void _init() {
    try {
      _eventSubscription = FlutterCallkitIncoming.onEvent.listen(
        (CallEvent? event) {
          if (event == null) return;
          debugPrint('[NotificationService] 📞 Event Received: ${event.event}');
          _eventController.add(event);
        },
        onError: (error) {
          debugPrint('[NotificationService] Stream error: $error');
        },
      );
      debugPrint('[NotificationService] ✅ Initialized successfully');
    } catch (e) {
      debugPrint('[NotificationService] init error: $e');
    }
  }

  // ============================================
  // === إظهار شاشة المكالمة الواردة (CallKit) ===
  // ============================================
  Future<void> showIncomingCall({
    required String uuid,
    required String callerName,
    required String handle,
    required bool isVideo,
  }) async {
    final params = CallKitParams(
      id: uuid,
      nameCaller: callerName,
      appName: 'Lan Phone',
      avatar: '',
      handle: handle,
      type: isVideo ? 1 : 0, // 0: Audio, 1: Video
      duration: 30000,
      textAccept: 'قبول',
      textDecline: 'رفض',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'مكالمة فائتة',
        callbackText: 'معاودة الاتصال',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'ringtone_default',
        backgroundColor: '#095D5E',
        backgroundUrl: '',
        actionColor: '#4CAF50',
        textColor: '#FFFFFF',
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      debugPrint('[NotificationService] Error showing incoming call: $e');
    }
  }

  // ============================================
  // === إنهاء المكالمة برمجيًا ===
  // ============================================
  Future<void> endCall(String uuid) async {
    try {
      await FlutterCallkitIncoming.endCall(uuid);
    } catch (e) {
      debugPrint('[NotificationService] Error ending call: $e');
    }
  }

  Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint('[NotificationService] Error ending all calls: $e');
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _eventController.close();
    super.dispose();
  }
}
