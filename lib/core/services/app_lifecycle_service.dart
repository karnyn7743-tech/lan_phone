import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// ============================================================
/// خدمة حالة دورة حياة التطبيق
///
/// المسؤوليات:
///   - تتبع ما إذا كان التطبيق في المقدمة أو الخلفية.
///   - تتبع المحادثة المفتوحة حاليًا (إن وُجدت).
///
/// الاستخدامات:
///   - MessageService: يتخطى إشعار الرسائل إن كانت المحادثة مفتوحة
///     والتطبيق في المقدمة.
///   - ChatScreen: يُبلّغ الخدمة عند فتح/إغلاق المحادثة.
/// ============================================================
class AppLifecycleService extends ChangeNotifier
    with WidgetsBindingObserver {
  AppLifecycleService() {
    WidgetsBinding.instance.addObserver(this);
  }

  // ============================================
  // === حالة التطبيق (مقدمة/خلفية) ===
  // ============================================
  bool _isInForeground = true;

  /// هل التطبيق حاليًا في المقدمة؟
  bool get isInForeground => _isInForeground;

  // ============================================
  // === المحادثة المفتوحة ===
  // ============================================
  String? _openChatPeerId;

  /// معرّف الجهاز الذي فُتحت محادثته حاليًا (أو null)
  String? get openChatPeerId => _openChatPeerId;

  /// يُستدعى عند فتح محادثة
  void setOpenChat(String peerDeviceId) {
    if (_openChatPeerId == peerDeviceId) return;
    _openChatPeerId = peerDeviceId;
    debugPrint('[Lifecycle] Open chat: $peerDeviceId');
    notifyListeners();
  }

  /// يُستدعى عند إغلاق المحادثة
  void clearOpenChat() {
    if (_openChatPeerId == null) return;
    debugPrint('[Lifecycle] Clear open chat');
    _openChatPeerId = null;
    notifyListeners();
  }

  /// هل هذه المحادثة مفتوحة حاليًا؟
  bool isChatOpen(String peerDeviceId) {
    return _openChatPeerId == peerDeviceId;
  }

  // ============================================
  // === دورة حياة التطبيق ===
  // ============================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasInForeground = _isInForeground;
    _isInForeground = state == AppLifecycleState.resumed;

    if (wasInForeground != _isInForeground) {
      debugPrint(
        '[Lifecycle] App state changed → '
        '${_isInForeground ? "foreground" : "background"}',
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
