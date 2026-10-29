import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/database_helper.dart';
import '../constants.dart';
import '../discovery/device_discovery.dart';
import '../services/app_lifecycle_service.dart';
import '../services/local_notification_service.dart';
import '../signaling/signaling_service.dart';

/// ============================================================
/// خدمة الرسائل والوسائط
/// ============================================================
class MessageService extends ChangeNotifier {
  MessageService();

  // ============================================
  // === المراجع ===
  // ============================================
  DeviceDiscovery? _discovery;
  SignalingService? _signaling;
  AppLifecycleService? _lifecycle;
  StreamSubscription<SignalingMessage>? _msgSub;

  void attach(DeviceDiscovery discovery, SignalingService signaling) {
    _discovery = discovery;
    _signaling = signaling;

    _msgSub?.cancel();
    _msgSub = _signaling!.messages.listen(_onSignalingMessage);

    // ✅ حمّل قائمة المحظورين عند البدء
    refreshBlockedDevices();
  }

  void attachLifecycle(AppLifecycleService lifecycle) {
    _lifecycle = lifecycle;
  }

  // ============================================
  // === Stream ===
  // ============================================
  final StreamController<MessageEvent> _eventController =
      StreamController<MessageEvent>.broadcast();
  Stream<MessageEvent> get events => _eventController.stream;

  final Map<String, double> _transfers = {};
  Map<String, double> get transfers => Map.unmodifiable(_transfers);

  // ============================================
  // === الأجهزة المحظورة (cache) ===
  // ============================================
  Set<String> _blockedDeviceIds = {};
  Set<String> get blockedDeviceIds => _blockedDeviceIds;

  Future<void> refreshBlockedDevices() async {
    try {
      _blockedDeviceIds =
          await DatabaseHelper.instance.getBlockedDeviceIds();
      debugPrint(
        '[Messages] Blocked devices loaded: ${_blockedDeviceIds.length}',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[Messages] refreshBlocked error: $e');
    }
  }

  bool isDeviceBlocked(String deviceId) =>
      _blockedDeviceIds.contains(deviceId);

  // ============================================
  // === إرسال ===
  // ============================================

  Future<MessageResult> sendText({
    required String peerDeviceId,
    required String body,
    String? replyToId,
  }) async {
    if (body.trim().isEmpty) {
      return MessageResult.failure('الرسالة فارغة');
    }

    // ✅ امنع الإرسال لجهاز محظور
    if (_blockedDeviceIds.contains(peerDeviceId)) {
      return MessageResult.failure('لا يمكن المراسلة مع جهاز محظور');
    }

    if (body.length > AppConstants.maxTextMessageLength) {
      return MessageResult.failure('الرسالة طويلة جدًا');
    }

    final messageId = const Uuid().v4();
    final now = DateTime.now();

    final message = {
      'message_id': messageId,
      'conversation_id': _conversationId(peerDeviceId),
      'sender_id': _discovery?.deviceId ?? '',
      'receiver_id': peerDeviceId,
      'type': AppConstants.mediaText,
      'body': body,
      'status': 'pending',
      'is_outgoing': 1,
      'reply_to_id': replyToId,
      'created_at': now.millisecondsSinceEpoch,
    };

    await DatabaseHelper.instance.insertMessage(message);
    await _updateConversationLastMessage(message);

    final sent = await _signaling?.sendTo(peerDeviceId, {
      'type': AppConstants.msgTextMessage,
      'msgId': messageId,
      'msgType': AppConstants.mediaText,
      'body': body,
      'replyToId': replyToId,
    }) ??
        false;

    final newStatus = sent ? 'sent' : 'failed';
    await DatabaseHelper.instance.updateMessageStatus(messageId, newStatus);

    notifyListeners();
    _eventController.add(MessageEvent(
      type: MessageEventType.sent,
      messageId: messageId,
      peerDeviceId: peerDeviceId,
    ));

    return sent
        ? MessageResult.success(messageId)
        : MessageResult.failure('فشل الإرسال');
  }

  Future<MessageResult> sendMedia({
    required String peerDeviceId,
    required String filePath,
    required String mediaType,
    String? caption,
    String? replyToId,
  }) async {
    // ✅ امنع الإرسال لجهاز محظور
    if (_blockedDeviceIds.contains(peerDeviceId)) {
      return MessageResult.failure('لا يمكن المراسلة مع جهاز محظور');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      return MessageResult.failure('الملف غير موجود');
    }

    final size = await file.length();
    if (size > AppConstants.maxFileSize) {
      return MessageResult.failure('الملف كبير جدًا');
    }

    final messageId = const Uuid().v4();
    final now = DateTime.now();
    final fileName = p.basename(filePath);
    final mimeType = _guessMimeType(fileName, mediaType);

    final message = {
      'message_id': messageId,
      'conversation_id': _conversationId(peerDeviceId),
      'sender_id': _discovery?.deviceId ?? '',
      'receiver_id': peerDeviceId,
      'type': mediaType,
      'body': caption,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': size,
      'mime_type': mimeType,
      'status': 'pending',
      'is_outgoing': 1,
      'reply_to_id': replyToId,
      'created_at': now.millisecondsSinceEpoch,
    };

    await DatabaseHelper.instance.insertMessage(message);
    await _updateConversationLastMessage(message);

    await _signaling?.sendTo(peerDeviceId, {
      'type': AppConstants.msgTextMessage,
      'msgId': messageId,
      'msgType': mediaType,
      'fileName': fileName,
      'fileSize': size,
      'mimeType': mimeType,
      'caption': caption,
      'replyToId': replyToId,
    });

    final ok = await _sendFileInChunks(
      peerDeviceId: peerDeviceId,
      messageId: messageId,
      file: file,
      fileName: fileName,
    );

    final newStatus = ok ? 'sent' : 'failed';
    await DatabaseHelper.instance.updateMessageStatus(messageId, newStatus);

    _transfers.remove(messageId);
    notifyListeners();

    return ok
        ? MessageResult.success(messageId)
        : MessageResult.failure('فشل إرسال الملف');
  }

  Future<bool> _sendFileInChunks({
    required String peerDeviceId,
    required String messageId,
    required File file,
    required String fileName,
  }) async {
    if (_signaling == null) return false;

    try {
      final total = await file.length();
      final raf = await file.open();
      var sent = 0;
      var chunkIndex = 0;

      while (sent < total) {
        final remaining = total - sent;
        final toRead = remaining < AppConstants.fileChunkSize
            ? remaining
            : AppConstants.fileChunkSize;

        final bytes = await raf.read(toRead);
        sent += bytes.length;

        final base64Data = base64Encode(bytes);

        final ok = await _signaling!.sendTo(peerDeviceId, {
          'type': 'MEDIA_CHUNK',
          'msgId': messageId,
          'chunkIndex': chunkIndex,
          'data': base64Data,
          'isLast': sent >= total,
          'fileName': fileName,
        });

        if (!ok) {
          await raf.close();
          return false;
        }

        chunkIndex++;
        _transfers[messageId] = sent / total;
        notifyListeners();
      }

      await raf.close();
      return true;
    } catch (e) {
      debugPrint('[Messages] sendFile error: $e');
      return false;
    }
  }

  // ============================================
  // === استقبال ===
  // ============================================

  final Map<String, _IncomingMedia> _incomingMedia = {};

  Future<void> _onSignalingMessage(SignalingMessage msg) async {
    switch (msg.type) {
      case AppConstants.msgTextMessage:
        await _handleIncomingMessage(msg);
        break;
      case 'MEDIA_CHUNK':
        await _handleIncomingChunk(msg);
        break;
      case AppConstants.msgMessageAck:
        await _handleAck(msg);
        break;
    }
  }

  Future<void> _handleIncomingMessage(SignalingMessage msg) async {
    // ✅ تجاهل الرسائل من الأجهزة المحظورة
    if (_blockedDeviceIds.contains(msg.from)) {
      debugPrint(
        '[Messages] Ignored message from blocked device: ${msg.from}',
      );
      return;
    }

    final msgId = msg.payload['msgId'] as String?;
    final msgType = msg.payload['msgType'] as String? ??
        AppConstants.mediaText;
    if (msgId == null) return;

    final conversationId = _conversationId(msg.from);

    // رسالة نصية → احفظ فورًا
    if (msgType == AppConstants.mediaText) {
      final body = msg.payload['body'] as String? ?? '';

      final message = {
        'message_id': msgId,
        'conversation_id': conversationId,
        'sender_id': msg.from,
        'receiver_id': _discovery?.deviceId ?? '',
        'type': AppConstants.mediaText,
        'body': body,
        'status': 'delivered',
        'is_outgoing': 0,
        'reply_to_id': msg.payload['replyToId'],
        'created_at': msg.receivedAt.millisecondsSinceEpoch,
        'delivered_at': DateTime.now().millisecondsSinceEpoch,
      };

      await DatabaseHelper.instance.insertMessage(message);
      await _updateConversationLastMessage(message);
      await DatabaseHelper.instance.incrementUnread(conversationId);

      await _sendAck(msg.from, msgId, 'delivered');

      notifyListeners();
      _eventController.add(MessageEvent(
        type: MessageEventType.received,
        messageId: msgId,
        peerDeviceId: msg.from,
      ));

      await _maybeNotify(
        peerDeviceId: msg.from,
        messageId: msgId,
        body: body,
      );
      return;
    }

    // وسائط → انتظر القطع
    _incomingMedia[msgId] = _IncomingMedia(
      messageId: msgId,
      from: msg.from,
      fileName: msg.payload['fileName'] as String? ?? 'file',
      totalSize: (msg.payload['fileSize'] as num?)?.toInt() ?? 0,
      mimeType: msg.payload['mimeType'] as String? ?? '',
      type: msgType,
      caption: msg.payload['caption'] as String?,
      replyToId: msg.payload['replyToId'] as String?,
      createdAt: msg.receivedAt.millisecondsSinceEpoch,
    );
  }

  Future<void> _handleIncomingChunk(SignalingMessage msg) async {
    final msgId = msg.payload['msgId'] as String?;
    if (msgId == null) return;

    final media = _incomingMedia[msgId];
    if (media == null) return;

    // ✅ تجاهل قطع الملفات من المحظورين
    if (_blockedDeviceIds.contains(media.from)) {
      debugPrint('[Messages] Ignored chunk from blocked device');
      _incomingMedia.remove(msgId);
      return;
    }

    try {
      final data = base64Decode(msg.payload['data'] as String);
      media.buffer.addAll(data);

      _transfers[msgId] = media.totalSize > 0
          ? media.buffer.length / media.totalSize
          : 0.0;
      notifyListeners();

      if (msg.payload['isLast'] == true) {
        await _finalizeIncomingMedia(media);
      }
    } catch (e) {
      debugPrint('[Messages] chunk error: $e');
    }
  }

  Future<void> _finalizeIncomingMedia(_IncomingMedia media) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(p.join(dir.path, 'media'));
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      final safeName = '${media.messageId}_${media.fileName}';
      final filePath = p.join(mediaDir.path, safeName);
      final file = File(filePath);
      await file.writeAsBytes(media.buffer);

      final conversationId = _conversationId(media.from);

      final message = {
        'message_id': media.messageId,
        'conversation_id': conversationId,
        'sender_id': media.from,
        'receiver_id': _discovery?.deviceId ?? '',
        'type': media.type,
        'body': media.caption,
        'file_path': filePath,
        'file_name': media.fileName,
        'file_size': media.buffer.length,
        'mime_type': media.mimeType,
        'status': 'delivered',
        'is_outgoing': 0,
        'reply_to_id': media.replyToId,
        'created_at': media.createdAt,
        'delivered_at': DateTime.now().millisecondsSinceEpoch,
      };

      await DatabaseHelper.instance.insertMessage(message);
      await _updateConversationLastMessage(message);
      await DatabaseHelper.instance.incrementUnread(conversationId);

      await _sendAck(media.from, media.messageId, 'delivered');

      _incomingMedia.remove(media.messageId);
      _transfers.remove(media.messageId);
      notifyListeners();

      _eventController.add(MessageEvent(
        type: MessageEventType.received,
        messageId: media.messageId,
        peerDeviceId: media.from,
      ));

      await _maybeNotify(
        peerDeviceId: media.from,
        messageId: media.messageId,
        body: _mediaDescription(media.type, media.caption),
      );
    } catch (e) {
      debugPrint('[Messages] finalize error: $e');
    }
  }

  // ============================================
  // === الإشعارات ===
  // ============================================

  Future<void> _maybeNotify({
    required String peerDeviceId,
    required String messageId,
    required String body,
  }) async {
    try {
      // 1) إذا المحادثة مفتوحة حاليًا → لا إشعار
      if (_lifecycle != null &&
          _lifecycle!.isInForeground &&
          _lifecycle!.isChatOpen(peerDeviceId)) {
        debugPrint('[Messages] Skipping notification (chat open)');
        return;
      }

      // 2) احصل على معلومات الجهاز
      final peer = _discovery?.getDevice(peerDeviceId);
      if (peer == null) {
        debugPrint('[Messages] Peer not found for notification');
        return;
      }

      // 3) اعرض الإشعار
      // الخدمة تتحقق من إعدادات الإشعارات لكل جهاز داخليًا
      await LocalNotificationService.instance.showMessageNotification(
        peerDeviceId: peerDeviceId,
        peerName: peer.name,
        peerNumber: peer.number,
        body: body,
        messageId: messageId,
        conversationId: _conversationId(peerDeviceId),
      );
    } catch (e) {
      debugPrint('[Messages] notify error: $e');
    }
  }

  String _mediaDescription(String type, String? caption) {
    final typeLabel = switch (type) {
      AppConstants.mediaImage => '📷 صورة',
      AppConstants.mediaVideo => '🎥 فيديو',
      AppConstants.mediaAudio => '🎵 مقطع صوتي',
      AppConstants.mediaFile => '📎 ملف',
      _ => 'مرفق',
    };
    if (caption != null && caption.isNotEmpty) {
      return '$typeLabel: $caption';
    }
    return typeLabel;
  }

  // ============================================
  // === ACK ===
  // ============================================

  Future<void> _sendAck(
    String peerDeviceId,
    String messageId,
    String status,
  ) async {
    await _signaling?.sendTo(peerDeviceId, {
      'type': AppConstants.msgMessageAck,
      'msgId': messageId,
      'status': status,
    });
  }

  Future<void> _handleAck(SignalingMessage msg) async {
    final msgId = msg.payload['msgId'] as String?;
    final status = msg.payload['status'] as String? ?? 'delivered';
    if (msgId == null) return;

    if (status == 'read') {
      await DatabaseHelper.instance.markMessageRead(
        msgId,
        DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      await DatabaseHelper.instance.markMessageDelivered(
        msgId,
        DateTime.now().millisecondsSinceEpoch,
      );
    }

    notifyListeners();
    _eventController.add(MessageEvent(
      type: MessageEventType.ack,
      messageId: msgId,
      peerDeviceId: msg.from,
    ));
  }

  Future<void> markConversationAsRead(String peerDeviceId) async {
    final conversationId = _conversationId(peerDeviceId);

    final messages = await DatabaseHelper.instance.getMessages(
      conversationId: conversationId,
    );

    for (final m in messages) {
      final isOutgoing = (m['is_outgoing'] as int?) == 1;
      final status = m['status'] as String?;
      if (!isOutgoing && status != 'read') {
        await DatabaseHelper.instance.markMessageRead(
          m['message_id'] as String,
          DateTime.now().millisecondsSinceEpoch,
        );

        await _sendAck(
          peerDeviceId,
          m['message_id'] as String,
          'read',
        );
      }
    }

    await DatabaseHelper.instance.resetUnread(conversationId);

    // ✅ ألغِ إشعار هذه المحادثة
    await LocalNotificationService.instance
        .cancelForDevice(peerDeviceId);

    notifyListeners();
  }

  // ============================================
  // === أدوات ===
  // ============================================

  String _conversationId(String peerDeviceId) {
    final a = _discovery?.deviceId ?? '';
    final b = peerDeviceId;
    final sorted = [a, b]..sort();
    return '${sorted[0]}__${sorted[1]}';
  }

  Future<void> _updateConversationLastMessage(
    Map<String, dynamic> message,
  ) async {
    final conversationId = message['conversation_id'] as String;
    final peerId = message['is_outgoing'] == 1
        ? message['receiver_id'] as String
        : message['sender_id'] as String;

    final preview = _previewText(message);
    final ts = message['created_at'] as int;

    final existing =
        await DatabaseHelper.instance.getConversation(conversationId);
    if (existing == null) {
      await DatabaseHelper.instance.upsertConversation({
        'conversation_id': conversationId,
        'peer_device_id': peerId,
        'last_message': preview,
        'last_message_type': message['type'] as String,
        'last_message_time': ts,
        'unread_count': 0,
        'created_at': ts,
      });
    } else {
      await DatabaseHelper.instance.updateConversationLastMessage(
        conversationId: conversationId,
        lastMessage: preview,
        lastMessageType: message['type'] as String,
        lastMessageTime: ts,
      );
    }
  }

  String _previewText(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    switch (type) {
      case AppConstants.mediaText:
        return (message['body'] as String?) ?? '';
      case AppConstants.mediaImage:
        return '📷 صورة';
      case AppConstants.mediaVideo:
        return '🎥 فيديو';
      case AppConstants.mediaAudio:
        return '🎵 مقطع صوتي';
      case AppConstants.mediaFile:
        return '📎 ملف: ${message['file_name'] ?? ''}';
      default:
        return 'رسالة';
    }
  }

  String _guessMimeType(String fileName, String type) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.m4a':
      case '.aac':
        return 'audio/aac';
      case '.mp3':
        return 'audio/mpeg';
      case '.pdf':
        return 'application/pdf';
      case '.txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _eventController.close();
    super.dispose();
  }
}

// ============================================================
// === نماذج ===
// ============================================================

class _IncomingMedia {
  final String messageId;
  final String from;
  final String fileName;
  final int totalSize;
  final String mimeType;
  final String type;
  final String? caption;
  final String? replyToId;
  final int createdAt;

  final List<int> buffer = [];

  _IncomingMedia({
    required this.messageId,
    required this.from,
    required this.fileName,
    required this.totalSize,
    required this.mimeType,
    required this.type,
    required this.caption,
    required this.replyToId,
    required this.createdAt,
  });
}

class MessageResult {
  final bool ok;
  final String? messageId;
  final String? error;

  MessageResult._(this.ok, this.messageId, this.error);

  factory MessageResult.success(String messageId) =>
      MessageResult._(true, messageId, null);

  factory MessageResult.failure(String error) =>
      MessageResult._(false, null, error);
}

enum MessageEventType { sent, received, ack, error }

class MessageEvent {
  final MessageEventType type;
  final String messageId;
  final String peerDeviceId;

  MessageEvent({
    required this.type,
    required this.messageId,
    required this.peerDeviceId,
  });
}
