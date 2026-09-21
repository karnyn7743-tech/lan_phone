  Future<void> _activateAudioSessionForWebRTC() async {
    try {
      // إعطاء مهلة زمنية قصيرة لتأكيد حجز العتاد من النظام لمنع الانهيار
      await Future.delayed(const Duration(milliseconds: 300));
      _isSpeakerOn = (_callType == AppConstants.callTypeVideo);
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
    } catch (e) {
      debugPrint('[RTC] activateAudioSession safe handling: $e');
    }
  }
