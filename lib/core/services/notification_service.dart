import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// ============================================================
/// خدمة الإشعارات — تستمع لأحداث Callkit من النظام
/// ============================================================
class NotificationService extends ChangeNotifier {
  NotificationService() {
    _init();
  }

  StreamSubscription<CallEvent?>? _eventSubscription;

  final StreamController<CallEvent?> _eventController =
      StreamController<CallEvent?>.broadcast();
  Stream<CallEvent?> get callEvents => _eventController.stream;

  void _init() {
    try {
      _eventSubscription = FlutterCallkitIncoming.onEvent.listen((event) {
        if (event == null) return;
        debugPrint('[NotificationService] Event: $event');
        _eventController.add(event);
      });
      debugPrint('[NotificationService] Initialized');
    } catch (e) {
      debugPrint('[NotificationService] init error: $e');
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _eventController.close();
    super.dispose();
  }
}
