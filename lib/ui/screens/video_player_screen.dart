import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';

/// ============================================================
/// شاشة تشغيل الفيديو بملء الشاشة
/// ============================================================
class VideoPlayerScreen extends StatefulWidget {
  final String videoPath;
  final String? title;

  const VideoPlayerScreen({
    super.key,
    required this.videoPath,
    this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();

    // إخفاء شريط النظام
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    _initializePlayer();
  }

  @override
  void dispose() {
    _controller?.dispose();

    // استعادة شريط النظام
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        setState(() => _hasError = true);
        return;
      }

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();

      _controller!.addListener(_onControllerUpdate);
      await _controller!.play();

      // إخفاء الأزرار تلقائيًا بعد 3 ثوان
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showControls = false);
      });

      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('[VideoPlayer] init error: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;
    setState(() {});
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;

    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
      }
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // ============================================
            // === الفيديو ===
            // ============================================
            Positioned.fill(
              child: _buildVideoContent(),
            ),

            // ============================================
            // === زر الإغلاق (دائمًا ظاهر) ===
            // ============================================
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),

            // ============================================
            // === عناصر التحكم ===
            // ============================================
            if (_showControls && _isInitialized)
              _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoContent() {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.white54,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'تعذّر تشغيل الفيديو',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'قد يكون الملف محذوفًا أو غير مدعوم',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      ),
    );
  }

  Widget _buildControls() {
    final c = _controller!;
    final position = c.value.position;
    final duration = c.value.duration;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.6),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.6),
          ],
          stops: const [0.0, 0.25, 0.75, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),

            // ============================================
            // === زر التشغيل في المنتصف ===
            // ============================================
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 56,
                icon: Icon(
                  c.value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: Colors.white,
                ),
                onPressed: _togglePlay,
              ),
            ),

            const Spacer(),

            // ============================================
            // === شريط التقدم ===
            // ============================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  VideoProgressIndicator(
                    c,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: AppTheme.primaryColor,
                      bufferedColor: Colors.white30,
                      backgroundColor: Colors.white12,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(position),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
