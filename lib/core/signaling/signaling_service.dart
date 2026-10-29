import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import '../../data/database/database_helper.dart';
import '../constants.dart';
import '../discovery/device_discovery.dart';
import '../discovery/discovered_device.dart';

/// ============================================================
/// خدمة التحكم (Signaling Service)
/// ============================================================
class SignalingService extends ChangeNotifier {
  SignalingService();

  // ============================================
  // === المراجع ===
  // ============================================
  DeviceDiscovery? _discovery;

  void attachDiscovery(DeviceDiscovery discovery) {
    if (_discovery == discovery) return;
    _discovery = discovery;
    _discovery!.addListener(_onDiscoveryChanged);
  }

  // ============================================
  // === الحالة ===
  // ============================================
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  HttpServer? _server;
  HttpServer? get server => _server;

  final Map<String, WebSocketChannel> _channels = {};
  final Map<WebSocketChannel, String> _pendingIncoming = {};

  /// الأجهزة المحظورة (cache للفحص السريع)
  Set<String> _blockedDeviceIds = {};

  Future<void> refreshBlockedDevices() async {
    try {
      _blockedDeviceIds =
          await DatabaseHelper.instance.getBlockedDeviceIds();
      debugPrint(
        '[Signaling] Blocked devices loaded: ${_blockedDeviceIds.length}',
      );
    } catch (e) {
      debugPrint('[Signaling] refreshBlocked error: $e');
    }
  }

  Map<String, bool> get connectionStatus => {
        for (final entry in _channels.entries)
          entry.key: _isChannelOpen(entry.value),
      };

  Timer? _keepAliveTimer;
  final Map<String, Timer> _reconnectTimers = {};

  // ============================================
  // === Streams ===
  // ============================================
  final StreamController<SignalingMessage> _messageController =
      StreamController<SignalingMessage>.broadcast();
  Stream<SignalingMessage> get messages => _messageController.stream;

  final StreamController<SignalingConnectionEvent> _connectionController =
      StreamController<SignalingConnectionEvent>.broadcast();
  Stream<SignalingConnectionEvent> get connectionEvents =>
      _connectionController.stream;

  // ============================================
  // === دورة الحياة ===
  // ============================================

  Future<void> start() async {
    if (_isRunning) return;

    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        AppConstants.signalingPort,
        shared: true,
      );

      debugPrint('[Signaling] Server started on port ${_server!.port}');

      _server!.listen(
        _handleIncomingRequest,
        onError: (e) => debugPrint('[Signaling] Server error: $e'),
      );

      // ✅ حمّل قائمة المحظورين
      await refreshBlockedDevices();

      _keepAliveTimer = Timer.periodic(
        const Duration(seconds: AppConstants.keepAliveSeconds),
        (_) => _sendKeepAlive(),
      );

      _isRunning = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[Signaling] Failed to start server: $e');
    }
  }

  Future<void> stop() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;

    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();

    for (final ch in _channels.values) {
      try {
        await ch.sink.close();
      } catch (_) {}
    }
    _channels.clear();
    _pendingIncoming.clear();

    await _server?.close(force: true);
    _server = null;

    _isRunning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _discovery?.removeListener(_onDiscoveryChanged);
    _messageController.close();
    _connectionController.close();
    super.dispose();
  }

  // ============================================
  // === الاتصالات الواردة ===
  // ============================================

  Future<void> _handleIncomingRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket required')
        ..close();
      return;
    }

    try {
      final socket = await WebSocketTransformer.upgrade(request);
      final channel = IOWebSocketChannel(socket);

      _pendingIncoming[channel] = '';

      channel.stream.listen(
        (data) => _handleIncomingMessage(channel, data),
        onError: (e) {
          debugPrint('[Signaling] Incoming error: $e');
          _cleanupChannel(channel);
        },
        onDone: () => _cleanupChannel(channel),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[Signaling] Upgrade failed: $e');
    }
  }

  void _handleIncomingMessage(WebSocketChannel channel, dynamic data) {
    try {
      final text = data is String ? data : utf8.decode(data as List<int>);
      final json = jsonDecode(text) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';

      final pendingId = _pendingIncoming[channel];
      if (pendingId != null && pendingId.isEmpty) {
        final deviceId = json['deviceId'] as String? ??
            json['from'] as String? ??
            '';
        if (deviceId.isEmpty) {
          debugPrint('[Signaling] First message without deviceId — closing');
          channel.sink.close();
          return;
        }

        // ✅ ارفض الاتصال من جهاز محظور
        if (_blockedDeviceIds.contains(deviceId)) {
          debugPrint(
            '[Signaling] Rejected connection from blocked: $deviceId',
          );
          channel.sink.close();
          _pendingIncoming.remove(channel);
          return;
        }

        _pendingIncoming.remove(channel);
        _registerChannel(deviceId, channel);
        debugPrint('[Signaling] Incoming registered: $deviceId');

        _connectionController.add(SignalingConnectionEvent(
          deviceId: deviceId,
          connected: true,
          isIncoming: true,
        ));
        notifyListeners();
      }

      _emitMessage(json);
    } catch (e) {
      debugPrint('[Signaling] Message parse error: $e');
    }
  }

  // ============================================
  // === الاتصال بالأجهزة ===
  // ============================================

  Future<bool> connectTo(String deviceId) async {
    if (_isConnected(deviceId)) return true;

    // ✅ لا تتصل بجهاز محظور
    if (_blockedDeviceIds.contains(deviceId)) {
      debugPrint('[Signaling] Cannot connect to blocked: $deviceId');
      return false;
    }

    final device = _discovery?.getDevice(deviceId);
    if (device == null) {
      debugPrint('[Signaling] Device not found: $deviceId');
      return false;
    }

    return _connectToDevice(device);
  }

  Future<bool> _connectToDevice(DiscoveredDevice device) async {
    _reconnectTimers[device.deviceId]?.cancel();
    _reconnectTimers.remove(device.deviceId);

    // ✅ تحقق من الحظر
    if (_blockedDeviceIds.contains(device.deviceId)) {
      debugPrint(
        '[Signaling] Refusing connect to blocked: ${device.deviceId}',
      );
      return false;
    }

    try {
      if (!_isLocalAddress(device.ip)) {
        debugPrint('[Signaling] Refusing non-local address: ${device.ip}');
        return false;
      }

      final uri = Uri.parse('ws://${device.ip}:${device.port}');
      final socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(
            seconds: AppConstants.connectionTimeoutSeconds,
          ));

      final channel = IOWebSocketChannel(socket);
      _registerChannel(device.deviceId, channel);

      _send(channel, {
        'type': 'HELLO',
        'deviceId': _discovery!.deviceId,
        'name': _discovery!.deviceName,
        'capabilities': const ['text', 'voice', 'video', 'media'],
      });

      channel.stream.listen(
        (data) => _handleIncomingMessage(channel, data),
        onError: (e) {
          debugPrint('[Signaling] Outgoing error to ${device.deviceId}: $e');
          _cleanupChannel(channel);
        },
        onDone: () => _cleanupChannel(channel),
        cancelOnError: false,
      );

      debugPrint('[Signaling] Connected to ${device.name} (${device.ip})');

      _connectionController.add(SignalingConnectionEvent(
        deviceId: device.deviceId,
        connected: true,
        isIncoming: false,
      ));
      notifyListeners();

      return true;
    } catch (e) {
      debugPrint('[Signaling] Connect to ${device.deviceId} failed: $e');
      _scheduleReconnect(device.deviceId);
      return false;
    }
  }

  void _registerChannel(String deviceId, WebSocketChannel channel) {
    final old = _channels[deviceId];
    if (old != null && old != channel) {
      try {
        old.sink.close();
      } catch (_) {}
    }
    _channels[deviceId] = channel;
  }

  void _cleanupChannel(WebSocketChannel channel) {
    String? deviceId;
    for (final entry in _channels.entries) {
      if (entry.value == channel) {
        deviceId = entry.key;
        break;
      }
    }

    if (deviceId != null) {
      _channels.remove(deviceId);
      _connectionController.add(SignalingConnectionEvent(
        deviceId: deviceId,
        connected: false,
        isIncoming: false,
      ));
      notifyListeners();

      if (_discovery?.isDeviceOnline(deviceId) ?? false) {
        _scheduleReconnect(deviceId);
      }
    }

    _pendingIncoming.remove(channel);
  }

  // ============================================
  // === إعادة الاتصال ===
  // ============================================

  void _scheduleReconnect(String deviceId) {
    if (_reconnectTimers.containsKey(deviceId)) return;
    if (_blockedDeviceIds.contains(deviceId)) return;

    _reconnectTimers[deviceId] = Timer(
      const Duration(seconds: 3),
      () async {
        _reconnectTimers.remove(deviceId);
        if (!_isConnected(deviceId) &&
            !_blockedDeviceIds.contains(deviceId) &&
            (_discovery?.isDeviceOnline(deviceId) ?? false)) {
          await connectTo(deviceId);
        }
      },
    );
  }

  // ============================================
  // === إرسال ===
  // ============================================

  Future<bool> sendTo(String deviceId, Map<String, dynamic> payload) async {
    // ✅ لا ترسل لجهاز محظور
    if (_blockedDeviceIds.contains(deviceId)) {
      debugPrint('[Signaling] Cannot send to blocked: $deviceId');
      return false;
    }

    payload['from'] = _discovery?.deviceId;
    payload['to'] = deviceId;
    payload['timestamp'] = DateTime.now().millisecondsSinceEpoch;

    if (!_isConnected(deviceId)) {
      final ok = await connectTo(deviceId);
      if (!ok) return false;
    }

    final channel = _channels[deviceId];
    if (channel == null) return false;

    return _send(channel, payload);
  }

  Future<void> broadcastTo(
    List<String> deviceIds,
    Map<String, dynamic> payload,
  ) async {
    for (final id in deviceIds) {
      await sendTo(id, Map<String, dynamic>.from(payload));
    }
  }

  bool _send(WebSocketChannel channel, Map<String, dynamic> payload) {
    try {
      channel.sink.add(jsonEncode(payload));
      return true;
    } catch (e) {
      debugPrint('[Signaling] send error: $e');
      return false;
    }
  }

  void _sendKeepAlive() {
    for (final channel in _channels.values) {
      try {
        channel.sink.add(jsonEncode({
          'type': AppConstants.msgPing,
          'from': _discovery?.deviceId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      } catch (_) {}
    }
  }

  // ============================================
  // === معالجة الرسائل ===
  // ============================================

  void _emitMessage(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == AppConstants.msgPing) {
      final from = json['from'] as String?;
      if (from != null && _isConnected(from)) {
        final ch = _channels[from]!;
        _send(ch, {
          'type': AppConstants.msgPong,
          'from': _discovery?.deviceId,
        });
      }
      return;
    }

    if (type == AppConstants.msgPong) return;

    // ✅ تجاهل الرسائل من محظورين
    final from = json['from'] as String? ?? '';
    if (from.isNotEmpty && _blockedDeviceIds.contains(from)) {
      debugPrint('[Signaling] Ignored message from blocked: $from');
      return;
    }

    _messageController.add(SignalingMessage(
      from: from,
      to: json['to'] as String? ?? '',
      type: type ?? '',
      payload: json,
      receivedAt: DateTime.now(),
    ));
  }

  // ============================================
  // === أحداث الاكتشاف ===
  // ============================================

  void _onDiscoveryChanged() {
    final discovery = _discovery;
    if (discovery == null) return;

    for (final device in discovery.onlineDevices) {
      // ✅ تجاهل المحظورين
      if (_blockedDeviceIds.contains(device.deviceId)) continue;

      if (!_isConnected(device.deviceId)) {
        if (!_reconnectTimers.containsKey(device.deviceId)) {
          _connectToDevice(device);
        }
      }
    }
  }

  // ============================================
  // === أدوات ===
  // ============================================

  bool _isConnected(String deviceId) {
    final ch = _channels[deviceId];
    if (ch == null) return false;
    return _isChannelOpen(ch);
  }

  bool _isChannelOpen(WebSocketChannel channel) {
    try {
      return channel.closeCode == null;
    } catch (_) {
      return false;
    }
  }

  bool _isLocalAddress(String ip) {
    if (ip.isEmpty) return false;
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('127.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? 0;
        if (second >= 16 && second <= 31) return true;
      }
    }
    return false;
  }

  bool isDeviceConnected(String deviceId) => _isConnected(deviceId);

  List<String> get connectedDeviceIds =>
      _channels.keys.where(_isConnected).toList();

  Future<void> disconnect(String deviceId) async {
    final ch = _channels.remove(deviceId);
    if (ch != null) {
      try {
        await ch.sink.close();
      } catch (_) {}
      notifyListeners();
    }
  }
}

// ============================================================
// === نماذج ===
// ============================================================

class SignalingMessage {
  final String from;
  final String to;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime receivedAt;

  SignalingMessage({
    required this.from,
    required this.to,
    required this.type,
    required this.payload,
    required this.receivedAt,
  });

  @override
  String toString() => 'SignalingMessage($type, from=$from)';
}

class SignalingConnectionEvent {
  final String deviceId;
  final bool connected;
  final bool isIncoming;

  SignalingConnectionEvent({
    required this.deviceId,
    required this.connected,
    required this.isIncoming,
  });
}
