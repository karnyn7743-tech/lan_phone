import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/database/database_helper.dart';
import '../constants.dart';
import '../services/notification_service.dart';
import '../signaling/signaling_service.dart';

/// ============================================================
/// محرك WebRTC مع تسجيل المكالمات ودعم Callkit
/// ============================================================
class RtcService extends ChangeNotifier {
  RtcService();

  // ============================================
  // === المراجع ===
  // ============================================
  SignalingService? _signaling;
  StreamSubscription<SignalingMessage>? _messageSub;

  NotificationService? _notification;
  StreamSubscription<CallEvent?>? _callkitSub;

  void attachSignaling(SignalingService signaling) {
    if (_signaling == signaling) return;
    _messageSub?.cancel();
    _signaling = signaling;
    _messageSub = _signaling!.messages.listen(_onSignalingMessage);
  }

  void attachNotification(NotificationService notification) {
    if (_notification == notification) return;
    _callkitSub?.cancel();
    _notification = notification;
    _callkitSub = _notification!.callEvents.listen(_onCallkitEvent);
  }

  // ============================================
  // === حالة المكالمة ===
  // ============================================
  String _currentCallId = '';
  String get currentCallId => _currentCallId;

  String _peerDeviceId = '';
  String get peerDeviceId => _peerDeviceId;

  String _peerName = '';
  String get peerName => _peerName;

  String _callType = AppConstants.callTypeAudio;
  String get callType => _callType;

  String _callState = AppConstants.callStateIdle;
  String get callState => _callState;

  bool get isInCall => _callState != AppConstants.callStateIdle;
  bool get isCaller => _isCaller;
  bool _isCaller = false;

  DateTime? _callStartedAt;
  DateTime? get callStartedAt => _callStartedAt;

  DateTime? _callLogStartTime;

  // ✅ تخزين SDP offer الوارد (للمستقبِل)
  String? _pendingOfferSdp;
  String? _pendingOfferType;

  int get callDurationSeconds {
    if (_callStartedAt == null) return 0;
    return DateTime.now().difference(_callStartedAt!).inSeconds;
  }

  // ============================================
  // === حالة الوسائط ===
  // ============================================
  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isVideoEnabled = true;
  bool get isVideoEnabled => _isVideoEnabled;

  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  bool _isFrontCamera = true;
  bool get isFrontCamera => _isFrontCamera;

  bool _hasRemoteVideo = false;
  bool get hasRemoteVideo => _hasRemoteVideo;

  // ============================================
  // === WebRTC Objects ===
  // ============================================
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  final List<RTCIceCandidate> _pendingCandidates = [];

  /// علامة تُبيّن أن RemoteDescription ضُبط — لتفريغ طابور ICE في الوقت الصحيح
  bool _remoteDescriptionSet = false;

  // ============================================
  // === ✅ إعدادات ICE (مُطابقة للنسخة الناجحة) ===
  // ============================================
  // على LAN بدون إنترنت لا نحتاج STUN/TURN. الإعدادات المبسطة
  // تتفق تمامًا مع wifi_p2p_app وتضمن اتصالاً مباشرًا سريعًا.
  final Map<String, dynamic> _iceServers = const {
    'iceServers': <Map<String, dynamic>>[],
    'sdpSemantics': 'unified-plan',
  };

  // ✅ قيود صوت بمعايير WebRTC الحديثة (وليست PSTN القديمة)
  static const Map<String, dynamic> _audioConstraints = {
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'sampleRate': 44100,
      'sampleSize': 16,
      'channelCount': 1,
    },
  };

  // ✅ قيود فيديو بالصيغة الحديثة (وليس mandatory/optional المهجورة)
  static const Map<String, dynamic> _videoConstraints = {
    'video': {
      'facingMode': 'user',
      'width': 640,
      'height': 480,
      'frameRate': 30,
    },
  };

  // ============================================
  // === Streams ===
  // ============================================
  final StreamController<RtcEvent> _eventController =
      StreamController<RtcEvent>.broadcast();
  Stream<RtcEvent> get events => _eventController.stream;

  // ============================================
  // === بدء مكالمة صادرة ===
  // ============================================

  Future<bool> startCall({
    required String peerDeviceId,
    required String peerName,
    required String callType,
  }) async {
    if (isInCall) {
      debugPrint('[RTC] Already in call');
      return false;
    }

    if (_signaling == null) {
      debugPrint('[RTC] Signaling not attached');
      return false;
    }

    try {
      final blocked =
          await DatabaseHelper.instance.isDeviceBlocked(peerDeviceId);
      if (blocked) {
        debugPrint('[RTC] Cannot call blocked device');
        return false;
      }
    } catch (e) {
      debugPrint('[RTC] block check error: $e');
    }

    _currentCallId = _generateCallId();
    _peerDeviceId = peerDeviceId;
    _peerName = peerName;
    _callType = callType;
    _isCaller = true;
    _callState = AppConstants.callStateCalling;
    _hasRemoteVideo = false;
    _callLogStartTime = DateTime.now();
    notifyListeners();

    await _logCallStart(direction: AppConstants.callDirectionOutgoing);

    try {
      await _openLocalMedia(callType);
      await _createPeerConnection();
      await _addLocalTracks();

      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': callType == AppConstants.callTypeVideo,
      });
      await _pc!.setLocalDescription(offer);

      await _signaling!.sendTo(peerDeviceId, {
        'type': AppConstants.msgCallInvite,
        'callId': _currentCallId,
        'media': callType,
        'peerName': peerName,
        'sdp': offer.sdp,
        'sdpType': offer.type,
      });

      debugPrint('[RTC] ✅ Call invite sent with SDP to $peerDeviceId');
      return true;
    } catch (e) {
      debugPrint('[RTC] startCall error: $e');
      await _saveCallLogEnd(state: AppConstants.callStateDeclined);
      await _cleanup();
      _callState = AppConstants.callStateIdle;
      notifyListeners();
      return false;
    }
  }

  // ============================================
  // === استقبال مكالمة ===
  // ============================================

  Future<void> _handleIncomingCall(SignalingMessage msg) async {
    if (isInCall) {
      await _signaling?.sendTo(msg.from, {
        'type': AppConstants.msgCallBusy,
        'callId': msg.payload['callId'],
      });
      return;
    }

    try {
      final blocked =
          await DatabaseHelper.instance.isDeviceBlocked(msg.from);
      if (blocked) {
        debugPrint('[RTC] Rejected call from blocked: ${msg.from}');
        await _signaling?.sendTo(msg.from, {
          'type': AppConstants.msgCallBusy,
          'callId': msg.payload['callId'],
        });
        return;
      }
    } catch (e) {
      debugPrint('[RTC] block check error: $e');
    }

    _currentCallId = msg.payload['callId'] as String;
    _peerDeviceId = msg.from;
    _peerName = msg.payload['peerName'] as String? ?? 'جهاز';
    _callType =
        msg.payload['media'] as String? ?? AppConstants.callTypeAudio;
    _isCaller = false;
    _callState = AppConstants.callStateRinging;
    _hasRemoteVideo = false;
    _callLogStartTime = DateTime.now();

    _pendingOfferSdp = msg.payload['sdp'] as String?;
    _pendingOfferType = msg.payload['sdpType'] as String? ?? 'offer';

    debugPrint(
      '[RTC] 📥 Incoming call — SDP: '
      '${_pendingOfferSdp != null ? "YES (${_pendingOfferSdp!.length} chars)" : "NO"}',
    );

    notifyListeners();

    await _logCallStart(direction: AppConstants.callDirectionIncoming);
    await _showCallkitIncoming();

    _eventController.add(RtcEvent(
      type: RtcEventType.incomingCall,
      callId: _currentCallId,
      peerDeviceId: _peerDeviceId,
      peerName: _peerName,
      callType: _callType,
    ));
  }

  // ============================================
  // === Callkit UI ===
  // ============================================

  Future<void> _showCallkitIncoming() async {
    try {
      final params = CallKitParams(
        id: _currentCallId,
        nameCaller: _peerName,
        appName: 'LanPhone',
        type: _callType == AppConstants.callTypeVideo ? 1 : 0,
        duration: 45000,
        extra: <String, dynamic>{
          'peerDeviceId': _peerDeviceId,
          'peerName': _peerName,
          'callType': _callType,
          'callId': _currentCallId,
        },
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: true,
          isShowCallID: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0F7B6C',
          actionColor: '#25D366',
          textColor: '#FFFFFF',
          incomingCallNotificationChannelName: 'مكالمات واردة',
          missedCallNotificationChannelName: 'مكالمات فائتة',
          isShowFullLockedScreen: true,
          isImportant: true,
        ),
        ios: const IOSParams(
          iconName: 'AppIcon',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          // ✅ 44100 بدل 8000
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.02,
          supportsDTMF: false,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      debugPrint('[RTC] showCallkitIncoming error: $e');
    }
  }

  Future<void> _dismissCallkit() async {
    try {
      await FlutterCallkitIncoming.endCall(_currentCallId);
    } catch (e) {
      debugPrint('[RTC] dismissCallkit error: $e');
    }
  }

  // ============================================
  // === أحداث Callkit ===
  // ============================================

  Future<void> _onCallkitEvent(CallEvent? event) async {
    if (event == null) return;

    final eventStr = event.toString();
    debugPrint('[RTC] Callkit event: $eventStr');

    if (eventStr.contains('actionCallAccept')) {
      await _onCallkitAccept(event);
    } else if (eventStr.contains('actionCallDecline')) {
      await _onCallkitDecline();
    } else if (eventStr.contains('actionCallTimeout')) {
      await _onCallkitTimeout();
    } else if (eventStr.contains('actionCallEnd')) {
      await _onCallkitEnd();
    } else if (eventStr.contains('actionCallToggleMute')) {
      toggleMute();
    }
  }

  Future<void> _onCallkitAccept(CallEvent event) async {
    if (_callState != AppConstants.callStateRinging) return;
    await acceptCall();

    _eventController.add(RtcEvent(
      type: RtcEventType.callAccepted,
      callId: _currentCallId,
      peerDeviceId: _peerDeviceId,
      peerName: _peerName,
      callType: _callType,
    ));
  }

  Future<void> _onCallkitDecline() async {
    if (_callState != AppConstants.callStateRinging) return;
    await rejectCall();
  }

  Future<void> _onCallkitTimeout() async {
    if (_callState != AppConstants.callStateRinging) return;
    await _saveCallLogEnd(state: AppConstants.callStateMissed);
    await _cleanup();
    _resetState();
    notifyListeners();
  }

  Future<void> _onCallkitEnd() async {
    if (!isInCall) return;
    await endCall(reason: 'user-hangup');
  }

  // ============================================
  // === قبول المكالمة (مع SDP) ===
  // ============================================

  Future<bool> acceptCall() async {
    if (_callState != AppConstants.callStateRinging) return false;

    if (_pendingOfferSdp == null) {
      debugPrint('[RTC] ❌ Cannot accept: no SDP offer stored');
      return false;
    }

    try {
      _callState = AppConstants.callStateConnecting;
      notifyListeners();

      await _openLocalMedia(_callType);
      await _createPeerConnection();

      await _pc!.setRemoteDescription(
        RTCSessionDescription(_pendingOfferSdp!, _pendingOfferType!),
      );
      _remoteDescriptionSet = true;
      debugPrint('[RTC] ✅ Remote description set from offer');

      await _drainPendingCandidates();
      await _addLocalTracks();

      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _callType == AppConstants.callTypeVideo,
      });
      await _pc!.setLocalDescription(answer);

      await _signaling!.sendTo(_peerDeviceId, {
        'type': AppConstants.msgCallAccept,
        'callId': _currentCallId,
        'sdp': answer.sdp,
        'sdpType': answer.type,
      });

      debugPrint('[RTC] ✅ Call accepted with SDP answer sent');
      return true;
    } catch (e) {
      debugPrint('[RTC] acceptCall error: $e');
      await endCall(reason: 'error');
      return false;
    }
  }

  Future<void> rejectCall({String reason = 'declined'}) async {
    if (_callState != AppConstants.callStateRinging) return;

    await _signaling?.sendTo(_peerDeviceId, {
      'type': AppConstants.msgCallReject,
      'callId': _currentCallId,
      'reason': reason,
    });

    _callState = AppConstants.callStateDeclined;
    notifyListeners();

    await _saveCallLogEnd(state: AppConstants.callStateDeclined);
    await _dismissCallkit();
    await _cleanup();
    _resetState();
  }

  // ============================================
  // === معالجة Signaling ===
  // ============================================

  Future<void> _onSignalingMessage(SignalingMessage msg) async {
    switch (msg.type) {
      case AppConstants.msgCallInvite:
        await _handleIncomingCall(msg);
        break;
      case AppConstants.msgCallAccept:
        await _handleCallAccept(msg);
        break;
      case AppConstants.msgCallReject:
        await _handleCallReject(msg);
        break;
      case AppConstants.msgCallBusy:
        await _handleCallBusy(msg);
        break;
      case AppConstants.msgCallEnd:
        await _handleRemoteEnd();
        break;
      case AppConstants.msgSdpOffer:
        await _handleSdpOffer(msg);
        break;
      case AppConstants.msgSdpAnswer:
        await _handleSdpAnswer(msg);
        break;
      case AppConstants.msgIceCandidate:
        await _handleRemoteIce(msg);
        break;
      default:
        break;
    }
  }

  Future<void> _handleCallAccept(SignalingMessage msg) async {
    if (_callState != AppConstants.callStateCalling) return;

    _callState = AppConstants.callStateConnecting;
    notifyListeners();

    final sdp = msg.payload['sdp'] as String?;
    final sdpType = msg.payload['sdpType'] as String? ?? 'answer';

    if (sdp != null && _pc != null) {
      try {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(sdp, sdpType),
        );
        _remoteDescriptionSet = true;
        debugPrint('[RTC] ✅ Remote description set from answer');
        await _drainPendingCandidates();
      } catch (e) {
        debugPrint('[RTC] setRemoteDescription(answer) error: $e');
      }
    } else {
      debugPrint('[RTC] ⚠️ Accept received without SDP');
    }
  }

  Future<void> _handleCallReject(SignalingMessage msg) async {
    if (msg.payload['callId'] != _currentCallId) return;

    _callState = AppConstants.callStateDeclined;
    _eventController.add(RtcEvent(
      type: RtcEventType.callEnded,
      callId: _currentCallId,
      peerDeviceId: _peerDeviceId,
      peerName: _peerName,
      callType: _callType,
      reason: 'declined',
    ));
    notifyListeners();

    await _saveCallLogEnd(state: AppConstants.callStateDeclined);
    await _dismissCallkit();
    await _cleanup();
    _resetState();
  }

  Future<void> _handleCallBusy(SignalingMessage msg) async {
    if (msg.payload['callId'] != _currentCallId) return;

    _callState = AppConstants.callStateDeclined;
    _eventController.add(RtcEvent(
      type: RtcEventType.callEnded,
      callId: _currentCallId,
      peerDeviceId: _peerDeviceId,
      peerName: _peerName,
      callType: _callType,
      reason: 'busy',
    ));
    notifyListeners();

    await _saveCallLogEnd(state: AppConstants.callStateDeclined);
    await _dismissCallkit();
    await _cleanup();
    _resetState();
  }

  Future<void> _handleRemoteEnd() async {
    if (_callState == AppConstants.callStateIdle) return;

    _eventController.add(RtcEvent(
      type: RtcEventType.callEnded,
      callId: _currentCallId,
      peerDeviceId: _peerDeviceId,
      peerName: _peerName,
      callType: _callType,
      reason: 'ended',
    ));

    final finalState = _callStartedAt == null
        ? AppConstants.callStateMissed
        : AppConstants.callStateEnded;

    await _saveCallLogEnd(state: finalState);
    await _dismissCallkit();
    await _cleanup();
    _resetState();
    notifyListeners();
  }

  // ============================================
  // === SDP / ICE ===
  // ============================================

  Future<void> _handleSdpOffer(SignalingMessage msg) async {
    final callId = msg.payload['callId'] as String?;
    if (callId != _currentCallId || _pc == null) return;

    try {
      final sdp = msg.payload['sdp'] as String;
      final type = msg.payload['sdpType'] as String? ?? 'offer';

      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteDescriptionSet = true;
      await _drainPendingCandidates();

      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _callType == AppConstants.callTypeVideo,
      });
      await _pc!.setLocalDescription(answer);

      await _signaling!.sendTo(_peerDeviceId, {
        'type': AppConstants.msgSdpAnswer,
        'callId': _currentCallId,
        'sdp': answer.sdp,
        'sdpType': answer.type,
      });
    } catch (e) {
      debugPrint('[RTC] handleSdpOffer error: $e');
    }
  }

  Future<void> _handleSdpAnswer(SignalingMessage msg) async {
    if (_pc == null) return;
    if (msg.payload['callId'] != _currentCallId) return;

    try {
      final sdp = msg.payload['sdp'] as String;
      final type = msg.payload['sdpType'] as String? ?? 'answer';
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteDescriptionSet = true;
      await _drainPendingCandidates();
    } catch (e) {
      debugPrint('[RTC] handleSdpAnswer error: $e');
    }
  }

  Future<void> _handleRemoteIce(SignalingMessage msg) async {
    final candidateMap = msg.payload['candidate'] as Map<String, dynamic>?;
    if (candidateMap == null) return;

    final candidate = RTCIceCandidate(
      candidateMap['candidate'] as String?,
      candidateMap['sdpMid'] as String?,
      candidateMap['sdpMLineIndex'] as int?,
    );

    // ✅ نعتمد على علم صريح بدل getRemoteDescription() الذي قد لا يعمل على كل الأجهزة
    if (_pc == null || !_remoteDescriptionSet) {
      _pendingCandidates.add(candidate);
      debugPrint('[RTC] ICE queued (no remote desc yet)');
      return;
    }

    try {
      await _pc!.addCandidate(candidate);
      debugPrint('[RTC] ICE added');
    } catch (e) {
      debugPrint('[RTC] addCandidate error: $e');
    }
  }

  Future<void> _drainPendingCandidates() async {
    if (_pc == null) return;
    debugPrint('[RTC] Draining ${_pendingCandidates.length} ICE candidates');
    for (final c in _pendingCandidates) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  // ============================================
  // === RTCPeerConnection ===
  // ============================================

  Future<void> _createPeerConnection() async {
    // ✅ استدعاء حديث بدون المعامل الثاني المهجور
    _pc = await createPeerConnection(_iceServers);

    _pc!.onIceCandidate = (candidate) async {
      if (candidate.candidate == null) return;
      debugPrint('[RTC] Local ICE → sending');
      await _signaling!.sendTo(_peerDeviceId, {
        'type': AppConstants.msgIceCandidate,
        'callId': _currentCallId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _pc!.onTrack = (RTCTrackEvent event) {
      debugPrint('[RTC] 🎯 Remote track: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        if (event.track.kind == 'video') _hasRemoteVideo = true;
        notifyListeners();

        _eventController.add(RtcEvent(
          type: RtcEventType.remoteStream,
          callId: _currentCallId,
          peerDeviceId: _peerDeviceId,
          peerName: _peerName,
          callType: _callType,
        ));
      }
    };

    _pc!.onIceConnectionState = (state) {
      debugPrint('[RTC] ICE state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        endCall(reason: 'ice-failed');
      }
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[RTC] Connection state: $state');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _callState = AppConstants.callStateConnected;
          _callStartedAt ??= DateTime.now();
          _updateCallLogState(AppConstants.callStateConnected);
          notifyListeners();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          if (isInCall) endCall(reason: 'disconnected');
          break;
        default:
          break;
      }
    };
  }

  // ============================================
  // === الوسائط ===
  // ============================================

  Future<void> _openLocalMedia(String callType) async {
    final constraints = <String, dynamic>{};

    // ✅ نبدأ من قيود الصوت (بمعايير حديثة 44100)
    constraints.addAll(_audioConstraints);

    // ✅ الفيديو صراحةً: إما constraints كاملة أو false
    if (callType == AppConstants.callTypeVideo) {
      constraints.addAll(_videoConstraints);
    } else {
      constraints['video'] = false; // ← مهم: يمنع مسار فيديو فارغًا
    }

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    debugPrint(
      '[RTC] Local stream: ${_localStream!.getTracks().length} tracks '
      '(audio: ${_localStream!.getAudioTracks().length}, '
      'video: ${_localStream!.getVideoTracks().length})',
    );

    if (callType != AppConstants.callTypeVideo) {
      _isVideoEnabled = false;
    }
  }

  Future<void> _addLocalTracks() async {
    if (_localStream == null || _pc == null) return;
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
      debugPrint('[RTC] Added track: ${track.kind}');
    }
  }

  // ============================================
  // === التحكم ===
  // ============================================

  void toggleMute() {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = _isMuted;
    }
    _isMuted = !_isMuted;
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    if (_localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();

    if (videoTracks.isEmpty && !_isVideoEnabled) {
      try {
        final stream =
            await navigator.mediaDevices.getUserMedia(_videoConstraints);
        final newTrack = stream.getVideoTracks().first;
        await _pc?.addTrack(newTrack, _localStream!);
        _isVideoEnabled = true;
      } catch (e) {
        debugPrint('[RTC] re-enable video error: $e');
      }
    } else {
      for (final track in videoTracks) {
        track.enabled = !_isVideoEnabled;
      }
      _isVideoEnabled = !_isVideoEnabled;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (_localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return;

    try {
      await Helper.switchCamera(videoTracks.first);
      _isFrontCamera = !_isFrontCamera;
      notifyListeners();
    } catch (e) {
      debugPrint('[RTC] switchCamera error: $e');
    }
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
    notifyListeners();
  }

  // ============================================
  // === إنهاء المكالمة ===
  // ============================================

  Future<void> endCall({String reason = 'user-hangup'}) async {
    if (!isInCall) return;

    String finalState;
    if (_callStartedAt != null) {
      finalState = AppConstants.callStateEnded;
    } else if (reason == 'disconnected' || reason == 'ice-failed') {
      finalState = AppConstants.callStateDeclined;
    } else {
      finalState = AppConstants.callStateMissed;
    }

    await _saveCallLogEnd(state: finalState);

    if (_signaling != null && _peerDeviceId.isNotEmpty) {
      try {
        await _signaling!.sendTo(_peerDeviceId, {
          'type': AppConstants.msgCallEnd,
          'callId': _currentCallId,
          'reason': reason,
        });
      } catch (_) {}
    }

    _eventController.add(RtcEvent(
      type: RtcEventType.callEnded,
      callId: _currentCallId,
      peerDeviceId: _peerDeviceId,
      peerName: _peerName,
      callType: _callType,
      reason: reason,
    ));

    await _dismissCallkit();
    await _cleanup();
    _resetState();
    notifyListeners();
  }

  // ============================================
  // === تسجيل المكالمات ===
  // ============================================

  Future<void> _logCallStart({required String direction}) async {
    try {
      await DatabaseHelper.instance.insertCallLog({
        'call_id': _currentCallId,
        'peer_device_id': _peerDeviceId,
        'peer_name': _peerName,
        'type': _callType,
        'direction': direction,
        'state': AppConstants.callStateRinging,
        'started_at': _callLogStartTime?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
        'duration_seconds': 0,
      });
    } catch (e) {
      debugPrint('[RTC] logCallStart error: $e');
    }
  }

  Future<void> _updateCallLogState(String state) async {
    try {
      await DatabaseHelper.instance.updateCallLog(
        callId: _currentCallId,
        state: state,
        endedAt: 0,
        durationSeconds: 0,
      );
    } catch (e) {
      debugPrint('[RTC] updateCallLogState error: $e');
    }
  }

  Future<void> _saveCallLogEnd({required String state}) async {
    if (_currentCallId.isEmpty) return;
    try {
      final endTime = DateTime.now();
      final duration = _callStartedAt != null
          ? endTime.difference(_callStartedAt!).inSeconds
          : 0;

      await DatabaseHelper.instance.updateCallLog(
        callId: _currentCallId,
        state: state,
        endedAt: endTime.millisecondsSinceEpoch,
        durationSeconds: duration,
      );
    } catch (e) {
      debugPrint('[RTC] saveCallLogEnd error: $e');
    }
  }

  // ============================================
  // === تنظيف ===
  // ============================================

  Future<void> _cleanup() async {
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
        try {
          _localStream!.removeTrack(track);
        } catch (_) {}
      }
      try {
        await _localStream!.dispose();
      } catch (_) {}
      _localStream = null;
    }

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    _remoteStream = null;
    _pendingCandidates.clear();
    _hasRemoteVideo = false;
    _pendingOfferSdp = null;
    _pendingOfferType = null;
    _remoteDescriptionSet = false; // ✅ تصفير العلم

    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
    _isSpeakerOn = false;
  }

  void _resetState() {
    _currentCallId = '';
    _peerDeviceId = '';
    _peerName = '';
    _callType = AppConstants.callTypeAudio;
    _callState = AppConstants.callStateIdle;
    _isCaller = false;
    _callStartedAt = null;
    _callLogStartTime = null;
    _isMuted = false;
    _isVideoEnabled = true;
    _isFrontCamera = true;
    _pendingOfferSdp = null;
    _pendingOfferType = null;
  }

  String _generateCallId() {
    return 'call_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}';
  }

  String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    final buf = StringBuffer();
    var v = now;
    for (var i = 0; i < 6; i++) {
      buf.write(chars[v % chars.length]);
      v ~/= chars.length;
    }
    return buf.toString();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _callkitSub?.cancel();
    _cleanup();
    _eventController.close();
    super.dispose();
  }
}

// ============================================================
// === نماذج ===
// ============================================================

enum RtcEventType {
  incomingCall,
  callAccepted,
  callEnded,
  remoteStream,
  error,
}

class RtcEvent {
  final RtcEventType type;
  final String callId;
  final String peerDeviceId;
  final String peerName;
  final String callType;
  final String? reason;

  RtcEvent({
    required this.type,
    required this.callId,
    required this.peerDeviceId,
    required this.peerName,
    required this.callType,
    this.reason,
  });
}
