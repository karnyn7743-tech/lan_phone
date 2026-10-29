import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../theme/app_theme.dart';

/// ============================================================
/// فقاعة تشغيل رسالة صوتية
/// --------------------------------------------------------
/// تعرض: زر تشغيل/إيقاف، شريط تقدم، مدة الصوت
/// ============================================================
class VoiceMessageBubble extends StatefulWidget {
  final String filePath;
  final int? durationMs;
  final bool isOutgoing;
  final bool isDark;

  const VoiceMessageBubble({
    super.key,
    required this.filePath,
    required this.isDark,
    this.durationMs,
    this.isOutgoing = false,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  AudioSession? _session;

  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    _total = Duration(
      milliseconds: widget.durationMs ?? 0,
    );

    _initPlayer();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player?.dispose();

    // ✅ حرّر جلسة الصوت
    _session?.setActive(false);

    super.dispose();
  }

  // ============================================
  // === تهيئة المشغل ===
  // ============================================

  Future<void> _initPlayer() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) setState(() => _hasError = true);
        return;
      }

      // ✅ 1) تكوين جلسة الصوت للتشغيل بصوت عالٍ
      await _configureAudioSession();

      // ✅ 2) إنشاء المشغل
      final player = AudioPlayer();
      _player = player;

      // ✅ 3) أقصى مستوى صوت
      await player.setVolume(1.0);

      final dur = await player.setFilePath(widget.filePath);
      if (dur != null && mounted) {
        setState(() => _total = dur);
      }

      _posSub = player.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      _stateSub = player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _isPlaying = state.playing &&
              state.processingState != ProcessingState.completed;
        });

        // عند الانتهاء → ارجع للبداية
        if (state.processingState == ProcessingState.completed) {
          _player?.seek(Duration.zero);
          _player?.pause();
        }
      });

      debugPrint('[VoiceBubble] ✅ Player initialized');
    } catch (e) {
      debugPrint('[VoiceBubble] init error: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  // ============================================
  // === ✅ تكوين جلسة الصوت ===
  // ============================================
  //
  // الهدف: تشغيل الصوت عبر مكبر الصوت الرئيسي بأقصى مستوى.
  //
  // استخدام `speech()` يُهيئ الجلسة لأوضاع التشغيل العادية
  // (وليس المكالمات)، مما يُفعِّل مكبر الصوت ويضمن الوضوح.

  Future<void> _configureAudioSession() async {
    try {
      _session = await AudioSession.instance;

      // ✅ وضع "تحدث/استماع" — صوت واضح ومرتفع
      await _session!.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );

      debugPrint('[VoiceBubble] ✅ Audio session configured');
    } catch (e) {
      debugPrint('[VoiceBubble] configureAudioSession error: $e');
    }
  }

  // ============================================
  // === التحكم ===
  // ============================================

  Future<void> _togglePlay() async {
    if (_player == null || _hasError) return;

    if (_isPlaying) {
      await _player!.pause();
      return;
    }

    // إذا وصل النهاية، ابدأ من الصفر
    if (_position >= _total && _total.inMilliseconds > 0) {
      await _player!.seek(Duration.zero);
    }

    setState(() => _isLoading = true);
    try {
      // ✅ فعّل جلسة الصوت
      await _session?.setActive(true);

      // ✅ تأكد من أقصى صوت قبل التشغيل
      await _player!.setVolume(1.0);

      await _player!.play();
    } catch (e) {
      debugPrint('[VoiceBubble] play error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================
  // === أدوات ===
  // ============================================

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = s ~/ 60;
    final rem = s % 60;
    return '$m:${rem.toString().padLeft(2, '0')}';
  }

  double get _progress {
    if (_total.inMilliseconds == 0) return 0.0;
    return (_position.inMilliseconds / _total.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorState();
    }

    final accentColor = widget.isOutgoing
        ? (widget.isDark ? Colors.white : AppTheme.primaryColor)
        : AppTheme.primaryColor;

    return Container(
      constraints: const BoxConstraints(
        minWidth: 220,
        maxWidth: 280,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ============================================
          // === زر التشغيل ===
          // ============================================
          _PlayButton(
            isPlaying: _isPlaying,
            isLoading: _isLoading,
            color: accentColor,
            onTap: _togglePlay,
          ),

          const SizedBox(width: 8),

          // ============================================
          // === شريط التقدم + المدة ===
          // ============================================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // شريط التقدم
                _ProgressBar(
                  progress: _progress,
                  color: accentColor,
                  onSeek: (percent) {
                    if (_total.inMilliseconds == 0) return;
                    final target = Duration(
                      milliseconds:
                          (percent * _total.inMilliseconds).round(),
                    );
                    _player?.seek(target);
                  },
                ),
                const SizedBox(height: 6),
                // المدة
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isPlaying || _position > Duration.zero
                          ? _fmt(_position)
                          : _fmt(_total),
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isDark
                            ? Colors.white.withOpacity(0.75)
                            : Colors.black.withOpacity(0.55),
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    // أيقونة صغيرة للصوت
                    Icon(
                      Icons.graphic_eq,
                      size: 14,
                      color: accentColor.withOpacity(0.7),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 22,
            color: widget.isDark
                ? Colors.white.withOpacity(0.6)
                : Colors.grey.shade700,
          ),
          const SizedBox(width: 8),
          Text(
            'تعذّر تشغيل الصوت',
            style: TextStyle(
              fontSize: 13,
              color: widget.isDark
                  ? Colors.white.withOpacity(0.7)
                  : Colors.black.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// === زر التشغيل ===
// ============================================================
class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final Color color;
  final VoidCallback onTap;

  const _PlayButton({
    required this.isPlaying,
    required this.isLoading,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.15),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              : Icon(
                  isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: color,
                  size: 26,
                ),
        ),
      ),
    );
  }
}

// ============================================================
// === شريط التقدم ===
// ============================================================
class _ProgressBar extends StatelessWidget {
  final double progress;
  final Color color;
  final void Function(double percent) onSeek;

  const _ProgressBar({
    required this.progress,
    required this.color,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            final percent =
                details.localPosition.dx / constraints.maxWidth;
            onSeek(percent.clamp(0.0, 1.0));
          },
          onHorizontalDragUpdate: (details) {
            final percent =
                details.localPosition.dx / constraints.maxWidth;
            onSeek(percent.clamp(0.0, 1.0));
          },
          child: Container(
            height: 20,
            alignment: Alignment.centerLeft,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // الخلفية
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // التقدم
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // نقطة السحب
                Positioned(
                  left: constraints.maxWidth * progress - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
