import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/database/database_helper.dart';
import '../constants.dart';
import '../services/notification_service.dart';
import '../signaling/signaling_service.dart';

class RtcService extends ChangeNotifier {
  RtcService();

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

  String? _pendingOfferSdp;
  String? _pendingOfferType;

  String _localIp = '';

  int get callDurationSeconds {
    if (_callStartedAt == null) return 0;
    return DateTime.now().difference(_callStartedAt!).inSeconds;
  }

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

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  final Map<String, dynamic> _iceServers = const {
    'iceServers': <Map<String, dynamic>>[],
    'sdpSemantics': 'unified-plan',
  };

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

  static const Map<String, dynamic> _videoConstraints = {
    'video': {
      'facingMode': 'user',
      'width': {'ideal': 640},
      'height': {'ideal': 480},
      'frameRate': {'ideal': 30},
    },
  };

  final StreamController<RtcEvent> _eventController =
      StreamController<RtcEvent>.broadcast();
  Stream<RtcEvent> get events => _eventController.stream;

  Future<String> _detectLocalIp() async {
    if (_localIp.isNotEmpty) return _localIp;

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('en0') ||
            name.contains('ap')) {
          for (final addr in iface.addresses) {
            final ip = addr.address;
            if (_isPrivateIp(ip)) {
              _localIp = ip;
              return ip;
            }
          }
        }
      }

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (_isPrivateIp(addr.address)) {
            _localIp = addr.address;
            return _localIp;
          }
        }
      }
    } catch (e) {
      debugPrint('[RTC] _detectLocalIp error: $e');
    }

    return '';
  }

  bool _isPrivateIp(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? 0;
        if (second >= 16 && second <= 31) return true;
      }
    }
    return false;
  }

  String _fixSdp(String sdp) {
    if (_localIp.isEmpty) return sdp;

    final fixed = sdp.replaceAllMapped(
      RegExp(
        r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32,})\.local',
      ),
      (m) => _localIp,
    );
    return fixed;
  }

  Future<bool> startCall({
    required String peerDeviceId,
    required String peerName,
    required String callType,
  }) async {
    if (isInCall) return false;
    if (_signaling == null) return false;

    try {
      final blocked =
          await DatabaseHelper.instance.isDeviceBlocked(peerDeviceId);
      if (blocked) return false;
    } catch (e) {
      debugPrint('[RTC] block check error: $e');
    }

    _resetState();

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
      await _detectLocalIp();
      await _openLocalMedia(callType);
      await _createPeerConnection();
      await _addLocalTracks();
      await _activateAudioSessionForWebRTC();

      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': callType == AppConstants.callTypeVideo,
      });

      await _pc!.setLocalDescription(offer);

      final fixedSdp = _fixSdp(offer.sdp ?? '');

      await _signaling!.sendTo(peerDeviceId, {
        'type': AppConstants.msgCallInvite,
        'callId': _currentCallId,
        'media': callType,
        'peerName': peerName,
        'sdp': fixedSdp,
        'sdpType': offer.type,
      });

      debugPrint('[RTC] ✅ Call invite sent with tracks');
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
        await _signaling?.sendTo(msg.from, {
          'type': AppConstants.msgCallBusy,
          'callId': msg.payload['callId'],
        });
        return;
      }
    } catch (e) {
      debugPrint('[RTC] block check error: $e');
    }

    _resetState();

    _currentCallId = msg.payload['callId'] as String;
    _peerDeviceId = msg.from;
    _peerName = msg.payload['peerName'] as String? ?? 'جهاز محلي';
    _callType =
        msg.payload['media'] as String? ?? AppConstants.callTypeAudio;
    _isCaller = false;
    _callState = AppConstants.callStateRinging;
    _hasRemoteVideo = false;
    _callLogStartTime = DateTime.now();

    _pendingOfferSdp = msg.payload['sdp'] as String?;
    _pendingOfferType = msg.payload['sdpType'] as String? ?? 'offer';

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

  Future<void> _onCallkitEvent(CallEvent? event) async {
    if (event == null) return;

    final eventStr = event.toString();

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

    _eventController.add(RtcEvent(
      type: RtcEventType.callAccepted,
      callId: _currentCallId,
      peerDeviceId: _peerDeviceId,
      peerName: _peerName,
      callType: _callType,
    ));

    await acceptCall();
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

  Future<bool> acceptCall() async {
    if (_callState != AppConstants.callStateRinging &&
        _callState != AppConstants.callStateConnecting) {
      debugPrint('[RTC] ❌ Cannot accept: invalid call state ($_callState)');
      return false;
    }

    if (_pendingOfferSdp == null) {
      debugPrint('[RTC] ❌ Cannot accept: no SDP offer stored');
      return false;
    }

    try {
      _callState = AppConstants.callStateConnecting;
      notifyListeners();

      await _detectLocalIp();
      await _openLocalMedia(_callType);
      await _createPeerConnection();
      await _addLocalTracks();
      await _activateAudioSessionForWebRTC();

      await _pc!.setRemoteDescription(
        RTCSessionDescription(_pendingOfferSdp!, _pendingOfferType!),
      );
      _remoteDescriptionSet = true;

      await _drainPendingCandidates();

      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _callType == AppConstants.callTypeVideo,
      });

      await _pc!.setLocalDescription(answer);

      final fixedAnswer = _fixSdp(answer.sdp ?? '');

      await _signaling!.sendTo(_peerDeviceId, {
        'type': AppConstants.msgCallAccept,
        'callId': _currentCallId,
        'sdp': fixedAnswer,
        'sdpType': answer.type,
      });

      _callState = AppConstants.callStateConnected;
      _callStartedAt = DateTime.now();
      await _updateCallLogState(AppConstants.callStateConnected);

      _eventController.add(RtcEvent(
        type: RtcEventType.callAccepted,
        callId: _currentCallId,
        peerDeviceId: _peerDeviceId,
        peerName: _peerName,
        callType: _callType,
      ));

      notifyListeners();
      debugPrint('[RTC] ✅ Call accepted & tracks setup complete');
      return true;
    } catch (e) {
      debugPrint('[RTC] ❌ acceptCall error: $e');
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
        await _drainPendingCandidates();
      } catch (e) {
        debugPrint('[RTC] setRemoteDescription(answer) error: $e');
      }
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

      final fixedAnswer = _fixSdp(answer.sdp ?? '');

      await _signaling!.sendTo(_peerDeviceId, {
        'type': AppConstants.msgSdpAnswer,
        'callId': _currentCallId,
        'sdp': fixedAnswer,
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

    if (_pc == null || !_remoteDescriptionSet) {
      _pendingCandidates.add(candidate);
      return;
    }

    try {
      await _pc!.addCandidate(candidate);
    } catch (e) {
      debugPrint('[RTC] addCandidate error: $e');
    }
  }

  Future<void> _drainPendingCandidates() async {
    if (_pc == null) return;
    for (final c in _pendingCandidates) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  Future<void> _createPeerConnection() async {
    _pc = await createPeerConnection(_iceServers);

    _pc!.onIceCandidate = (candidate) async {
      if (candidate.candidate == null) return;

      final fixedCandidate = _localIp.isNotEmpty
          ? candidate.candidate!.replaceAllMapped(
              RegExp(
                r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32,})\.local',
              ),
              (m) => _localIp,
            )
          : candidate.candidate!;

      await _signaling!.sendTo(_peerDeviceId, {
        'type': AppConstants.msgIceCandidate,
        'callId': _currentCallId,
        'candidate': {
          'candidate': fixedCandidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _pc!.onTrack = (RTCTrackEvent event) async {
      debugPrint('[RTC] 🎯 Remote track received: ${event.track.kind}');

      if (event.streams.isNotEmpty && event.streams[0] != null) {
        _remoteStream = event.streams[0];
      } else {
        _remoteStream ??= await createLocalMediaStream('remote_stream');
        _remoteStream!.addTrack(event.track);
      }

      if (event.track.kind == 'video') {
        _hasRemoteVideo = true;
      }

      if (event.track.kind == 'audio') {
        event.track.enabled = true;
        await Helper.setSpeakerphoneOn(_isSpeakerOn);
      }

      notifyListeners();

      _eventController.add(RtcEvent(
        type: RtcEventType.remoteStream,
        callId: _currentCallId,
        peerDeviceId: _peerDeviceId,
        peerName: _peerName,
        callType: _callType,
      ));
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

  Future<void> _openLocalMedia(String callType) async {
    final constraints = <String, dynamic>{};
    constraints.addAll(_audioConstraints);

    if (callType == AppConstants.callTypeVideo) {
      constraints.addAll(_videoConstraints);
    } else {
      constraints['video'] = false;
    }

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);

    if (callType != AppConstants.callTypeVideo) {
      _isVideoEnabled = false;
    }
  }

  Future<void> _addLocalTracks() async {
    if (_localStream == null || _pc == null) return;

    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
  }

  Future<void> _activateAudioSessionForWebRTC() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      _isSpeakerOn = (_callType == AppConstants.callTypeVideo);
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
    } catch (e) {
      debugPrint('[RTC] activateAudioSession safe handling: $e');
    }
  }

  void toggleMute() {
    if (_localStream == null) return;
    _isMuted = !_isMuted;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    if (_localStream == null || _pc == null) return;

    final videoTracks = _localStream!.getVideoTracks();

    if (videoTracks.isEmpty && !_isVideoEnabled) {
      try {
        final stream =
            await navigator.mediaDevices.getUserMedia(_videoConstraints);
        final newTrack = stream.getVideoTracks().first;
        _localStream!.addTrack(newTrack);

        final senders = await _pc!.getSenders();
        final videoSender = senders.firstWhere(
          (s) => s.track?.kind == 'video',
          orElse: () => null as RTCRtpSender,
        );

        if (videoSender != null) {
          await videoSender.replaceTrack(newTrack);
        } else {
          await _pc!.addTrack(newTrack, _localStream!);
          // إعادة تفاوض جديدة للطرف الآخر عند إضافة مسار
          final offer = await _pc!.createOffer();
          await _pc!.setLocalDescription(offer);
          await _signaling?.sendTo(_peerDeviceId, {
            'type': AppConstants.msgSdpOffer,
            'callId': _currentCallId,
            'sdp': _fixSdp(offer.sdp ?? ''),
            'sdpType': offer.type,
          });
        }
        _isVideoEnabled = true;
      } catch (e) {
        debugPrint('[RTC] re-enable video error: $e');
      }
    } else {
      _isVideoEnabled = !_isVideoEnabled;
      for (final track in videoTracks) {
        track.enabled = _isVideoEnabled;
      }
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
    _remoteDescriptionSet = false;

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
