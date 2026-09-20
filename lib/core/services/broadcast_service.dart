import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/database/database_helper.dart';
import '../constants.dart';
import '../discovery/device_discovery.dart';
import '../discovery/discovered_device.dart';
import '../signaling/signaling_service.dart';

/// ============================================================
/// دور الجهاز في البث
/// ============================================================
enum BroadcastRole {
  /// لا يشارك في أي بث
  idle,

  /// يبث صوته للآخرين
  broadcaster,

  /// يستمع لبث جهاز آخر
  listener,
}

/// ============================================================
/// خدمة البث الصوتي المباشر
/// ------------------------------------------------
/// المُذيع: يفتح اتصال WebRTC منفصل لكل مستمع
/// المستمع: يستقبل الصوت فقط (بدون ميكروفون)
///
/// يعتمد على SignalingService لتبادل SDP/ICE
/// ============================================================
class BroadcastService extends ChangeNotifier {
  BroadcastService();

  // ============================================
  // === المراجع ===
  // ============================================
  SignalingService? _signaling;
  DeviceDiscovery? _discovery;
  StreamSubscription<SignalingMessage>? _messageSub;

  void attach({
    required SignalingService signaling,
    required DeviceDiscovery discovery,
  }) {
    _signaling = signaling;
    _discovery = discovery;

    _messageSub?.cancel();
    _messageSub = _signaling!.messages.listen(_onSignalingMessage);
  }

  // ============================================
  // === الحالة ===
  // ============================================
  BroadcastRole _role = BroadcastRole.idle;
  BroadcastRole get role => _role;

  bool get isBroadcasting => _role == BroadcastRole.broadcaster;
  bool get isListening => _role == BroadcastRole.listener;
  bool get isIdle => _role == BroadcastRole.idle;

  /// معرّف البث الحالي
  String _broadcastId = '';
  String get broadcastId => _broadcastId;

  /// اسم المُذيع (يظهر للمستمعين)
  String _broadcasterName = '';
  String get broadcasterName => _broadcasterName;

  /// معرّف جهاز المُذيع (للمستمع)
  String _broadcasterDeviceId = '';
  String get broadcasterDeviceId => _broadcasterDeviceId;

  /// هل الميكروفون مكتوم (للمُذيع)
  bool _isMuted = false;
  bool get isMuted => _isMuted;

  /// هل الصوت مسموع محليًا (للمستمع)
  bool _isListeningAudio = true;
  bool get isListeningAudio => _isListeningAudio;

  /// حالة الاتصال
  String _status = '';
  String get status => _status;

  // ============================================
  // === المُذيع: اتصالات المستمعين ===
  // ============================================
  final Map<String, RTCPeerConnection> _listenerConnections = {};

  /// معرّف المستمع ← اسمه
  final Map<String, String> _listeners = {};
  Map<String, String> get listeners => Map.unmodifiable(_listeners);

  int get listenerCount => _listeners.length;

  /// ميكروفون المُذيع
  MediaStream? _localStream;

  // ============================================
  // === المستمع: اتصال المُذيع ===
  // ============================================
  RTCPeerConnection? _broadcasterConnection;
  MediaStream? _remoteStream;

  MediaStream? get remoteStream => _remoteStream;

  // ============================================
  // === ICE Candidates المعلّقة ===
  // ============================================
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  // ============================================
  // === Streams للأحداث ===
  // ============================================
  final StreamController<BroadcastEvent> _eventController =
      StreamController<BroadcastEvent>.broadcast();
  Stream<BroadcastEvent> get events => _eventController.stream;

  // ============================================
  // === إعدادات WebRTC ===
  // ============================================
  final Map<String, dynamic> _iceServers = const {
    'iceServers': <Map<String, dynamic>>[],
    'sdpSemantics': 'unified-plan',
  };

  /// قيود الصوت (نفس جودة المكالمات)
  final Map<String, dynamic> _audioConstraints = const {
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'googEchoCancellation': true,
      'googAutoGainControl': true,
      'googNoiseSuppression': true,
      'googHighpassFilter': true,
      'sampleRate': 8000,
      'channelCount': 1,
    },
    'video': false,
  };

  // ============================================
  // === بدء البث (المُذيع) ===
  // ============================================

  Future<bool> startBroadcast() async {
    if (!isIdle) {
      debugPrint('[Broadcast] Already in session');
      return false;
    }

    if (_signaling == null || _discovery == null) {
      debugPrint('[Broadcast] Not attached');
      return false;
    }

    // طلب أذونات الميكروفون والأجهزة المجاورة
    final micStatus = await Permission.microphone.request();
    final nearbyStatus = await Permission.nearbyWifiDevices.request();
    if (!micStatus.isGranted) {
      debugPrint('[Broadcast] Microphone permission denied');
      return false;
    }

    _broadcastId = _generateBroadcastId();
    _role = BroadcastRole.broadcaster;
    _broadcasterName = _discovery!.deviceName;
    _status = 'جارٍ التحضير...';
    _isMuted = false;
    notifyListeners();

    try {
      // 1) افتح الميكروفون
      _localStream = await navigator.mediaDevices.getUserMedia(
        _audioConstraints,
      );

      // 2) أرسل دعوة لكل الأجهزة المتصلة
      _status = 'جارٍ إرسال الدعوات...';
      notifyListeners();

      final devices = _discovery!.onlineDevices;
      for (final device in devices) {
        // تجاهل المحظورين
        try {
          final blocked =
              await DatabaseHelper.instance.isDeviceBlocked(device.deviceId);
          if (blocked) continue;
        } catch (_) {}

        await _inviteListener(device);
      }

      _status = 'البث نشط';
      notifyListeners();
      debugPrint('[Broadcast] Started: $_broadcastId');
      return true;
    } catch (e) {
      debugPrint('[Broadcast] startBroadcast error: $e');
      await _cleanup();
      _reset();
      notifyListeners();
      return false;
    }
  }

  /// دعوة مستمع واحد
  Future<void> _inviteListener(DiscoveredDevice device) async {
    try {
      // أنشئ اتصال WebRTC
      final pc = await _createBroadcasterConnection(device.deviceId);
      _listenerConnections[device.deviceId] = pc;

      // أضف مسار الصوت (الميكروفون)
      for (final track in _localStream!.getAudioTracks()) {
        await pc.addTrack(track, _localStream!);
      }

      // أنشئ عرض SDP (بدون استقبال صوت)
      final offer = await pc.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': false,
      });
      await pc.setLocalDescription(offer);

      // أرسل الدعوة
      await _signaling!.sendTo(device.deviceId, {
        'type': 'BROADCAST_INVITE',
        'broadcastId': _broadcastId,
        'broadcasterName': _broadcasterName,
        'sdp': offer.sdp,
        'sdpType': offer.type,
      });

      debugPrint('[Broadcast] Invited: ${device.name}');
    } catch (e) {
      debugPrint('[Broadcast] invite ${device.deviceId} error: $e');
      _listenerConnections.remove(device.deviceId);
    }
  }

  // ============================================
  // === استقبال دعوة بث (للمستمع) ===
  // ============================================

  Future<void> _handleBroadcastInvite(SignalingMessage msg) async {
    // إذا كان المستخدم مشغولًا
    if (!isIdle) {
      await _signaling?.sendTo(msg.from, {
        'type': 'BROADCAST_REJECT',
        'broadcastId': msg.payload['broadcastId'],
        'reason': 'busy',
      });
      return;
    }

    final broadcastId = msg.payload['broadcastId'] as String? ?? '';
    final broadcasterName =
        msg.payload['broadcasterName'] as String? ?? 'جهاز';

    // أطلق حدثًا للواجهة (لعرض نافذة منبثقة)
    _eventController.add(BroadcastEvent(
      type: BroadcastEventType.invitation,
      broadcastId: broadcastId,
      peerDeviceId: msg.from,
      peerName: broadcasterName,
      sdp: msg.payload['sdp'] as String?,
      sdpType: msg.payload['sdpType'] as String?,
    ));
  }

  /// قبول الدعوة (يُستدعى من الواجهة)
  Future<bool> acceptBroadcast({
    required String broadcastId,
    required String broadcasterDeviceId,
    required String broadcasterName,
    required String sdp,
    required String sdpType,
  }) async {
    if (!isIdle) return false;

    _broadcastId = broadcastId;
    _broadcasterDeviceId = broadcasterDeviceId;
    _broadcasterName = broadcasterName;
    _role = BroadcastRole.listener;
    _status = 'جارٍ الاتصال...';
    _isListeningAudio = true;
    notifyListeners();

    try {
      // 1) أنشئ اتصال WebRTC (فقط استقبال)
      final pc = await createPeerConnection(_iceServers, {
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      });
      _broadcasterConnection = pc;

      // 2) عند وصول الصوت
      pc.onTrack = (RTCTrackEvent event) {
        debugPrint('[Broadcast] Received track: ${event.track.kind}');
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _eventController.add(BroadcastEvent(
            type: BroadcastEventType.audioReceived,
            broadcastId: _broadcastId,
            peerDeviceId: _broadcasterDeviceId,
            peerName: _broadcasterName,
          ));
          notifyListeners();
        }
      };

      // 3) عند وصول ICE candidate
      pc.onIceCandidate = (candidate) async {
        if (candidate.candidate == null) return;
        await _signaling!.sendTo(broadcasterDeviceId, {
          'type': AppConstants.msgIceCandidate,
          'callId': _broadcastId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      };

      // 4) تغيّر حالة الاتصال
      pc.onConnectionState = (state) {
        debugPrint('[Broadcast] Connection state: $state');
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _status = 'تستمع إلى $broadcasterName';
            notifyListeners();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            if (isListening) {
              _handleDisconnect();
            }
            break;
          default:
            break;
        }
      };

      // 5) اضبط Remote Description
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp, sdpType),
      );

      // 6) عالج ICE المعلّقة
      await _drainPendingCandidates(broadcastId);

      // 7) أنشئ Answer
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await pc.setLocalDescription(answer);

      // 8) أرسل القبول
      await _signaling!.sendTo(broadcasterDeviceId, {
        'type': 'BROADCAST_ACCEPT',
        'broadcastId': broadcastId,
        'sdp': answer.sdp,
        'sdpType': answer.type,
      });

      debugPrint('[Broadcast] Listening to $broadcasterName');
      return true;
    } catch (e) {
      debugPrint('[Broadcast] acceptBroadcast error: $e');
      await _cleanupListener();
      _reset();
      notifyListeners();
      return false;
    }
  }

  /// رفض الدعوة (من الواجهة)
  Future<void> rejectBroadcast(String broadcastId, String broadcasterDeviceId) async {
    await _signaling?.sendTo(broadcasterDeviceId, {
      'type': 'BROADCAST_REJECT',
      'broadcastId': broadcastId,
      'reason': 'declined',
    });
  }

  // ============================================
  // === معالجة رسائل Signaling ===
  // ============================================

  Future<void> _onSignalingMessage(SignalingMessage msg) async {
    switch (msg.type) {
      case 'BROADCAST_INVITE':
        await _handleBroadcastInvite(msg);
        break;
      case 'BROADCAST_ACCEPT':
        await _handleBroadcastAccept(msg);
        break;
      case 'BROADCAST_REJECT':
        await _handleBroadcastReject(msg);
        break;
      case 'BROADCAST_END':
        await _handleBroadcastEnd(msg);
        break;
      case 'BROADCAST_LEAVE':
        await _handleBroadcastLeave(msg);
        break;
      case AppConstants.msgIceCandidate:
        // ICE يأتي من المستمعين للمُذيع أو العكس
        await _handleIceCandidate(msg);
        break;
      case 'BROADCAST_SDP_ANSWER':
        await _handleSdpAnswer(msg);
        break;
      default:
        break;
    }
  }

  /// قبول من مستمع (وصول للمُذيع)
  Future<void> _handleBroadcastAccept(SignalingMessage msg) async {
    if (!isBroadcasting) return;

    final listenerDeviceId = msg.from;
    final sdp = msg.payload['sdp'] as String?;
    final sdpType = msg.payload['sdpType'] as String? ?? 'answer';

    if (sdp == null) return;

    final pc = _listenerConnections[listenerDeviceId];
    if (pc == null) return;

    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp, sdpType),
      );
      await _drainPendingCandidates(listenerDeviceId);

      // أضف للقائمة
      final peer = _discovery?.getDevice(listenerDeviceId);
      _listeners[listenerDeviceId] = peer?.name ?? 'جهاز';
      notifyListeners();

      debugPrint('[Broadcast] Listener joined: ${_listeners[listenerDeviceId]}');
    } catch (e) {
      debugPrint('[Broadcast] accept handling error: $e');
    }
  }

  /// رفض من مستمع
  Future<void> _handleBroadcastReject(SignalingMessage msg) async {
    if (!isBroadcasting) return;

    final listenerDeviceId = msg.from;
    final pc = _listenerConnections.remove(listenerDeviceId);
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _listeners.remove(listenerDeviceId);
    notifyListeners();

    debugPrint('[Broadcast] Listener rejected: $listenerDeviceId');
  }

  /// المُذيع أنهى البث
  Future<void> _handleBroadcastEnd(SignalingMessage msg) async {
    if (!isListening) return;

    debugPrint('[Broadcast] Broadcaster ended');
    await _cleanupListener();
    _reset();
    notifyListeners();

    _eventController.add(BroadcastEvent(
      type: BroadcastEventType.ended,
      broadcastId: msg.payload['broadcastId'] as String? ?? '',
      peerDeviceId: msg.from,
      peerName: _broadcasterName,
    ));
  }

  /// مستمع غادر
  Future<void> _handleBroadcastLeave(SignalingMessage msg) async {
    if (!isBroadcasting) return;

    final listenerDeviceId = msg.from;
    final pc = _listenerConnections.remove(listenerDeviceId);
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _listeners.remove(listenerDeviceId);
    notifyListeners();

    debugPrint('[Broadcast] Listener left: $listenerDeviceId');
  }

  /// ICE من المستمع
  Future<void> _handleIceCandidate(SignalingMessage msg) async {
    final candidateMap = msg.payload['candidate'] as Map<String, dynamic>?;
    if (candidateMap == null) return;

    final candidate = RTCIceCandidate(
      candidateMap['candidate'] as String?,
      candidateMap['sdpMid'] as String?,
      candidateMap['sdpMLineIndex'] as int?,
    );

    // إذا كنا المُذيع ← ابحث عن اتصال المستمع
    if (isBroadcasting) {
      final pc = _listenerConnections[msg.from];
      if (pc == null) {
        _pendingCandidates.putIfAbsent(msg.from, () => []).add(candidate);
        return;
      }
      try {
        await pc.addCandidate(candidate);
      } catch (e) {
        debugPrint('[Broadcast] addCandidate (listener) error: $e');
      }
      return;
    }

    // إذا كنا المستمع ← استخدم اتصال المُذيع
    if (isListening) {
      final pc = _broadcasterConnection;
      if (pc == null || pc.getRemoteDescription() == null) {
        _pendingCandidates
            .putIfAbsent(_broadcasterDeviceId, () => [])
            .add(candidate);
        return;
      }
      try {
        await pc.addCandidate(candidate);
      } catch (e) {
        debugPrint('[Broadcast] addCandidate (broadcaster) error: $e');
      }
    }
  }

  /// SDP answer من مستمع (نادرًا)
  Future<void> _handleSdpAnswer(SignalingMessage msg) async {
    if (!isBroadcasting) return;
    final pc = _listenerConnections[msg.from];
    if (pc == null) return;

    try {
      final sdp = msg.payload['sdp'] as String;
      final type = msg.payload['sdpType'] as String? ?? 'answer';
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      await _drainPendingCandidates(msg.from);
    } catch (e) {
      debugPrint('[Broadcast] sdpAnswer error: $e');
    }
  }

  // ============================================
  // === إنشاء اتصال مُذيع ← مستمع ===
  // ============================================

  Future<RTCPeerConnection> _createBroadcasterConnection(
    String listenerDeviceId,
  ) async {
    final pc = await createPeerConnection(_iceServers, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    // عند وصول ICE محلي ← أرسله للمستمع
    pc.onIceCandidate = (candidate) async {
      if (candidate.candidate == null) return;
      await _signaling!.sendTo(listenerDeviceId, {
        'type': AppConstants.msgIceCandidate,
        'callId': _broadcastId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    // عند فشل الاتصال
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _listeners.remove(listenerDeviceId);
        _listenerConnections.remove(listenerDeviceId);
        notifyListeners();
      }
    };

    return pc;
  }

  // ============================================
  // === معالجة ICE المعلّقة ===
  // ============================================

  Future<void> _drainPendingCandidates(String deviceId) async {
    final candidates = _pendingCandidates.remove(deviceId);
    if (candidates == null || candidates.isEmpty) return;

    RTCPeerConnection? pc;
    if (isBroadcasting) {
      pc = _listenerConnections[deviceId];
    } else if (isListening && deviceId == _broadcasterDeviceId) {
      pc = _broadcasterConnection;
    }
    if (pc == null) return;

    for (final c in candidates) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
  }

  // ============================================
  // === التحكم ===
  // ============================================

  /// كتم/إلغاء كتم الميكروفون (للمُذيع)
  void toggleMute() {
    if (!isBroadcasting || _localStream == null) return;

    _isMuted = !_isMuted;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
    notifyListeners();
  }

  /// إيقاف/تشغيل استقبال الصوت (للمستمع)
  Future<void> toggleAudioPlayback() async {
    if (!isListening || _remoteStream == null) return;

    _isListeningAudio = !_isListeningAudio;
    for (final track in _remoteStream!.getAudioTracks()) {
      track.enabled = _isListeningAudio;
    }
    notifyListeners();
  }

  // ============================================
  // === إنهاء البث (المُذيع) ===
  // ============================================

  Future<void> stopBroadcast() async {
    if (!isBroadcasting) return;

    // أرسل BROADCAST_END لكل مستمع
    for (final listenerId in _listenerConnections.keys.toList()) {
      try {
        await _signaling?.sendTo(listenerId, {
          'type': 'BROADCAST_END',
          'broadcastId': _broadcastId,
        });
      } catch (_) {}
    }

    await _cleanup();

    _eventController.add(BroadcastEvent(
      type: BroadcastEventType.ended,
      broadcastId: _broadcastId,
      peerDeviceId: '',
      peerName: _broadcasterName,
    ));

    _reset();
    notifyListeners();
    debugPrint('[Broadcast] Stopped');
  }

  // ============================================
  // === مغادرة البث (المستمع) ===
  // ============================================

  Future<void> leaveBroadcast() async {
    if (!isListening) return;

    try {
      await _signaling?.sendTo(_broadcasterDeviceId, {
        'type': 'BROADCAST_LEAVE',
        'broadcastId': _broadcastId,
      });
    } catch (_) {}

    await _cleanupListener();
    _reset();
    notifyListeners();
    debugPrint('[Broadcast] Left');
  }

  // ============================================
  // === معالجة فقدان الاتصال ===
  // ============================================

  void _handleDisconnect() {
    debugPrint('[Broadcast] Connection lost');
    _cleanupListener().then((_) {
      _reset();
      notifyListeners();
      _eventController.add(BroadcastEvent(
        type: BroadcastEventType.disconnected,
        broadcastId: _broadcastId,
        peerDeviceId: _broadcasterDeviceId,
        peerName: _broadcasterName,
      ));
    });
  }

  // ============================================
  // === التنظيف ===
  // ============================================

  Future<void> _cleanup() async {
    // أوقف الميكروفون
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await _localStream!.dispose();
      } catch (_) {}
      _localStream = null;
    }

    // أغلق كل اتصالات المستمعين
    for (final pc in _listenerConnections.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _listenerConnections.clear();
    _listeners.clear();
    _pendingCandidates.clear();
  }

  Future<void> _cleanupListener() async {
    if (_remoteStream != null) {
      for (final track in _remoteStream!.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      _remoteStream = null;
    }

    try {
      await _broadcasterConnection?.close();
    } catch (_) {}
    _broadcasterConnection = null;
    _pendingCandidates.clear();
  }

  void _reset() {
    _role = BroadcastRole.idle;
    _broadcastId = '';
    _broadcasterName = '';
    _broadcasterDeviceId = '';
    _isMuted = false;
    _isListeningAudio = true;
    _status = '';
  }

  // ============================================
  // === أدوات ===
  // ============================================

  String _generateBroadcastId() {
    return 'bc_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _cleanup();
    _cleanupListener();
    _eventController.close();
    super.dispose();
  }
}

// ============================================================
// === الأحداث ===
// ============================================================

enum BroadcastEventType {
  /// دعوة للاستماع (تُعرض للمستمع)
  invitation,

  /// وصل الصوت لأول مرة (للمستمع)
  audioReceived,

  /// انتهى البث (من المُذيع)
  ended,

  /// فُقد الاتصال فجأة
  disconnected,
}

class BroadcastEvent {
  final BroadcastEventType type;
  final String broadcastId;
  final String peerDeviceId;
  final String peerName;
  final String? sdp;
  final String? sdpType;

  BroadcastEvent({
    required this.type,
    required this.broadcastId,
    required this.peerDeviceId,
    required this.peerName,
    this.sdp,
    this.sdpType,
  });
}
