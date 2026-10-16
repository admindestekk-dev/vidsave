import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

typedef VideoPlayerControllerFactory = Future<VideoPlayerController> Function(
  AssetEntity asset,
);

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    this.asset,
    this.file,
    this.title,
    this.controllerFactory,
  });

  final AssetEntity? asset;
  final File? file;
  final String? title;
  final VideoPlayerControllerFactory? controllerFactory;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(_initializePlayer());
  }

  Future<void> _initializePlayer() async {
    try {
      final controller = await _resolveController();
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
      await controller.play();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'VidSave video player',
          context: ErrorDescription(
            'while opening ${widget.title ?? widget.asset?.title ?? "video"}',
          ),
        ),
      );
      if (!mounted) return;
      setState(() {
        _error = error;
      });
    }
  }

  Future<VideoPlayerController> _resolveController() async {
    if (widget.controllerFactory != null && widget.asset != null) {
      return widget.controllerFactory!(widget.asset!);
    }
    if (widget.file != null) {
      return VideoPlayerController.file(widget.file!);
    }
    if (widget.asset != null) {
      final file = await widget.asset!.file;
      if (file == null) {
        throw StateError('Video dosyasına erişilemiyor.');
      }
      return VideoPlayerController.file(file);
    }
    throw StateError('Oynatılacak video bulunamadı.');
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            )
          else if (_error != null)
            _PlayerError(error: _error!)
          else
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF20B8C5)),
            ),
          if (controller != null && controller.value.isInitialized)
            _PlaybackControls(controller: controller),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 20),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Geri',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title ?? widget.asset?.title ?? 'Video oynatıcı',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Material(
                color: Colors.black.withValues(alpha: 0.48),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () {
                    if (value.isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  },
                  tooltip: value.isPlaying ? 'Duraklat' : 'Oynat',
                  color: Colors.white,
                  iconSize: 42,
                  padding: const EdgeInsets.all(18),
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          _formatDuration(value.position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDuration(value.duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      colors: VideoProgressColors(
                        playedColor: const Color(0xFF20B8C5),
                        bufferedColor: Colors.white.withValues(alpha: 0.35),
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Color(0xFF20B8C5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Video açılamadı',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
