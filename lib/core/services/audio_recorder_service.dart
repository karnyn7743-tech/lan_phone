import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// ============================================================
/// خدمة التسجيل الصوتي
/// ------------------------------------------------
/// تُسجّل بصيغة AAC/M4A بجودة عالية
/// ============================================================
class AudioRecorderService {
  // ============================================
  // === Singleton ===
  // ============================================
  AudioRecorderService._internal();
  static final AudioRecorderService instance =
      AudioRecorderService._internal();

  final AudioRecorder _recorder = AudioRecorder();

  String? _currentPath;
  DateTime? _startedAt;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  String? get currentPath => _currentPath;

  // ============================================
  // === الأذونات ===
  // ============================================

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('[Recorder] permission error: $e');
      return false;
    }
  }

  // ============================================
  // === ✅ تكوين جلسة الصوت ===
  // ============================================
  //
  // نُهيئ جلسة الصوت لوضع التسجيل لضمان:
  //   - استخدام مكبر الصوت الأمامي (لأخذ صوت أعلى)
  //   - تحسين مستوى الإدخال
  //   - تفعيل AGC (تحكم تلقائي بالكسب)

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;

      // تكوين للتسجيل بجودة عالية
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.videoRecording,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientExclusive,
        androidWillPauseWhenDucked: false,
      ));

      await session.setActive(true);
      debugPrint('[Recorder] ✅ Audio session configured for recording');
    } catch (e) {
      debugPrint('[Recorder] _configureAudioSession error: $e');
    }
  }

  Future<void> _releaseAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
      debugPrint('[Recorder] Audio session released');
    } catch (e) {
      debugPrint('[Recorder] _releaseAudioSession error: $e');
    }
  }

  // ============================================
  // === بدء التسجيل ===
  // ============================================

  Future<String?> start() async {
    try {
      // أوقف أي تسجيل جارٍ
      if (_isRecording) {
        await _recorder.stop();
        await _releaseAudioSession();
      }

      // تحقق من الإذن
      final ok = await _recorder.hasPermission();
      if (!ok) {
        debugPrint('[Recorder] No permission');
        return null;
      }

      // ✅ هيّئ جلسة الصوت
      await _configureAudioSession();

      // مجلد الصوت
      final dir = await getApplicationDocumentsDirectory();
      final audioDir = Directory(p.join(dir.path, 'audio'));
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }

      // اسم الملف
      final fileName =
          'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentPath = p.join(audioDir.path, fileName);
      _startedAt = DateTime.now();

      // ✅ إعدادات تسجيل عالية الجودة (صوت أعلى وأوضح)
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        // ✅ 128 kbps بدل 48 (جودة عالية، صوت أوضح وأعلى)
        bitRate: 128000,
        // ✅ 44.1 kHz بدل 16 (جودة صوت موسيقية)
        sampleRate: 44100,
        // مونو لتوفير المساحة
        numChannels: 1,
        // ✅ تحسينات إضافية
        autoGain: true,        // تحكم تلقائي بمستوى الصوت
        echoCancel: true,      // إلغاء الصدى
        noiseSuppress: true,   // إزالة الضجيج
      );

      await _recorder.start(config, path: _currentPath!);
      _isRecording = true;

      debugPrint('[Recorder] ✅ Started: $_currentPath');
      debugPrint('[Recorder]    bitRate: 128000, sampleRate: 44100');
      return _currentPath;
    } catch (e) {
      debugPrint('[Recorder] start error: $e');
      await _releaseAudioSession();
      _reset();
      return null;
    }
  }

  // ============================================
  // === إيقاف التسجيل (مع الحفظ) ===
  // ============================================

  Future<RecordingResult?> stop() async {
    if (!_isRecording) return null;

    try {
      final path = await _recorder.stop();
      final started = _startedAt;
      _isRecording = false;
      _startedAt = null;

      // ✅ حرّر جلسة الصوت
      await _releaseAudioSession();

      if (path == null || started == null) {
        _reset();
        return null;
      }

      final durationMs = DateTime.now().difference(started).inMilliseconds;

      // تحقق من وجود الملف
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[Recorder] File not found after stop');
        _reset();
        return null;
      }

      final size = await file.length();

      // إذا كان التسجيل قصيرًا جدًا (< 1 ثانية) → تجاهل
      if (durationMs < 1000 || size < 2000) {
        debugPrint('[Recorder] Too short — discarding');
        await file.delete();
        _reset();
        return null;
      }

      debugPrint(
        '[Recorder] ✅ Stopped: $path '
        '(${durationMs}ms, ${(size / 1024).toStringAsFixed(1)} KB)',
      );

      _currentPath = null;

      return RecordingResult(
        path: path,
        durationMs: durationMs,
        sizeBytes: size,
      );
    } catch (e) {
      debugPrint('[Recorder] stop error: $e');
      await _releaseAudioSession();
      _reset();
      return null;
    }
  }

  // ============================================
  // === إلغاء التسجيل ===
  // ============================================

  Future<void> cancel() async {
    try {
      if (_isRecording) {
        await _recorder.stop();
      }
      _isRecording = false;

      await _releaseAudioSession();

      // احذف الملف
      if (_currentPath != null) {
        final file = File(_currentPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('[Recorder] cancel error: $e');
    } finally {
      _reset();
    }
  }

  // ============================================
  // === المستوى الصوتي (للتغذية البصرية) ===
  // ============================================

  Stream<Amplitude> getAmplitudeStream() {
    return _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 150));
  }

  // ============================================
  // === أدوات داخلية ===
  // ============================================

  void _reset() {
    _currentPath = null;
    _startedAt = null;
    _isRecording = false;
  }

  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
    await _releaseAudioSession();
  }
}

// ============================================================
// === نموذج نتيجة التسجيل ===
// ============================================================
class RecordingResult {
  final String path;
  final int durationMs;
  final int sizeBytes;

  const RecordingResult({
    required this.path,
    required this.durationMs,
    required this.sizeBytes,
  });

  String get formattedDuration {
    final s = (durationMs / 1000).round();
    final m = s ~/ 60;
    final rem = s % 60;
    return '$m:${rem.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
