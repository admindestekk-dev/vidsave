import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'music_player.dart';

class PremiumPlayerScreen extends StatefulWidget {
  const PremiumPlayerScreen({
    super.key,
    required this.file,
    this.title,
    this.audioPlayerFactory,
  });

  final File file;
  final String? title;
  final AudioPlayerFactory? audioPlayerFactory;

  @override
  State<PremiumPlayerScreen> createState() => _PremiumPlayerScreenState();
}

class _PremiumPlayerScreenState extends State<PremiumPlayerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color _background = Color(0xFF10151B);
  static const Color _surface = Color(0xFF1B232C);
  static const Color _accent = Color(0xFFFF5436);
  static const List<String> _qualities = ['1080p', '720p', '480p'];

  late File _file;
  late String _title;
  late final bool _isAudio;
  late final AnimationController _waveAnimation;

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  MusicPlayerController? _audioPlayer;
  StreamSubscription<PlayerState>? _audioStateSubscription;
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<Duration>? _audioDurationSubscription;

  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  PlayerState _audioState = PlayerState.stopped;
  bool _isLoading = true;
  bool _isRenaming = false;
  bool _isHandlingOrientation = false;
  bool _isPlaybackCommandPending = false;
  String? _selectedQuality;
  Object? _error;

  bool get _isPlaying => _isAudio
      ? _audioState == PlayerState.playing
      : (_videoController?.value.isPlaying ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _file = widget.file;
    _title = widget.title?.trim().isNotEmpty == true
        ? widget.title!.trim()
        : _file.uri.pathSegments.last;
    final extension = _file.path.split('.').last.toLowerCase();
    _isAudio = const {
      'mp3',
      'm4a',
      'aac',
      'wav',
      'ogg',
      'flac',
    }.contains(extension);
    _waveAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (!_file.existsSync()) {
        throw FileSystemException('Dosya bulunamadı.', _file.path);
      }

      if (_isAudio) {
        await _initializeAudio();
      } else {
        await _initializeVideo();
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'VidSave premium player',
          context: ErrorDescription('while opening ${_file.path}'),
        ),
      );
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeAudio() async {
    final audioAsset = AssetEntity(
      id: _file.path,
      typeInt: AssetType.audio.index,
      width: 0,
      height: 0,
      duration: 0,
    );
    final player =
        widget.audioPlayerFactory?.call(audioAsset) ??
        createMusicPlayerController();
    _audioPlayer = player;
    _audioStateSubscription = player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _audioState = state);
      _updateWaveAnimation(state);
    });
    _audioPositionSubscription = player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _audioPosition = position);
    });
    _audioDurationSubscription = player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _audioDuration = duration);
    });
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(DeviceFileSource(_file.path));
    await player.resume();
    _updateWaveAnimation(PlayerState.playing);
  }

  void _updateWaveAnimation(PlayerState state) {
    if (!_isAudio ||
        (!_waveAnimation.isAnimating && state != PlayerState.playing)) {
      return;
    }
    if (state == PlayerState.playing) {
      if (!_waveAnimation.isAnimating) _waveAnimation.repeat();
    } else {
      _waveAnimation
        ..stop()
        ..value = 0;
    }
  }

  Future<void> _initializeVideo() async {
    final controller = VideoPlayerController.file(_file);
    _videoController = controller;
    await controller.initialize();
    await controller.setLooping(false);
    _chewieController = ChewieController(
      videoPlayerController: controller,
      autoPlay: true,
      allowFullScreen: true,
      deviceOrientationsOnEnterFullScreen: const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      deviceOrientationsAfterFullScreen: const [DeviceOrientation.portraitUp],
      systemOverlaysOnEnterFullScreen: const [],
      systemOverlaysAfterFullScreen: SystemUiOverlay.values,
      materialProgressColors: ChewieProgressColors(
        playedColor: _accent,
        handleColor: _accent,
        bufferedColor: Colors.white30,
        backgroundColor: Colors.white12,
      ),
    );
    await controller.play();
  }

  @override
  void didChangeMetrics() {
    if (_isAudio || _isHandlingOrientation || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isHandlingOrientation) return;
      final isLandscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      final chewie = _chewieController;
      if (chewie == null || chewie.isFullScreen == isLandscape) return;
      _isHandlingOrientation = true;
      if (isLandscape) {
        chewie.enterFullScreen();
      } else {
        chewie.exitFullScreen();
      }
      _isHandlingOrientation = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waveAnimation.dispose();
    _audioStateSubscription?.cancel();
    _audioPositionSubscription?.cancel();
    _audioDurationSubscription?.cancel();
    final audioPlayer = _audioPlayer;
    if (audioPlayer != null) unawaited(audioPlayer.dispose());
    _chewieController?.dispose();
    final videoController = _videoController;
    if (videoController != null) unawaited(videoController.dispose());
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_isPlaybackCommandPending) return;
    _isPlaybackCommandPending = true;
    try {
      if (_isAudio) {
        final player = _audioPlayer;
        if (player == null) return;
        if (_audioState == PlayerState.playing) {
          await player.pause();
          if (mounted) setState(() => _audioState = PlayerState.paused);
          _updateWaveAnimation(PlayerState.paused);
        } else {
          if (_audioState == PlayerState.completed) {
            await player.seek(Duration.zero);
          }
          await player.resume();
          if (mounted) setState(() => _audioState = PlayerState.playing);
          _updateWaveAnimation(PlayerState.playing);
        }
        return;
      }

      final controller = _videoController;
      if (controller == null) return;
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } finally {
      _isPlaybackCommandPending = false;
    }
  }

  Future<void> _seekAudio(Duration position) async {
    final player = _audioPlayer;
    if (player == null) return;
    await player.seek(position);
  }

  Future<void> _seekAudioBy(int seconds) async {
    if (_audioDuration <= Duration.zero) return;
    final target = _audioPosition + Duration(seconds: seconds);
    final boundedTarget = target < Duration.zero
        ? Duration.zero
        : target > _audioDuration
        ? _audioDuration
        : target;
    setState(() => _audioPosition = boundedTarget);
    await _seekAudio(boundedTarget);
  }

  Future<void> _showQualityPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Oynatma kalitesi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bu dosya cihazınızdaki yerel bir kopyadır. Kalite seçenekleri '
                'arayüz önizlemesidir; kaynak dosyanın çözünürlüğünü değiştirmez.',
                style: TextStyle(color: Colors.white60, height: 1.4),
              ),
              const SizedBox(height: 14),
              for (final quality in _qualities)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    quality == _selectedQuality
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: quality == _selectedQuality
                        ? _accent
                        : Colors.white54,
                  ),
                  title: Text(
                    quality,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, quality),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedQuality = selected);
    }
  }

  Future<void> _showRenameDialog() async {
    final currentName = _file.uri.pathSegments.last;
    final extensionIndex = currentName.lastIndexOf('.');
    final extension = extensionIndex > 0
        ? currentName.substring(extensionIndex)
        : '';
    final initialName = extension.isEmpty
        ? currentName
        : currentName.substring(0, extensionIndex);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RenameFileDialog(initialName: initialName, extension: extension),
    );
    if (newName == null || !mounted) return;
    await _renameFile(newName, extension);
  }

  Future<void> _renameFile(String enteredName, String extension) async {
    final baseName = enteredName.trim();
    if (baseName.isEmpty ||
        baseName == '.' ||
        baseName == '..' ||
        baseName.contains('/') ||
        baseName.contains(r'\')) {
      _showMessage('Geçerli bir dosya adı girin.');
      return;
    }

    final fullName =
        extension.isEmpty ||
            baseName.toLowerCase().endsWith(extension.toLowerCase())
        ? baseName
        : '$baseName$extension';
    final target = File(
      '${_file.parent.path}${Platform.pathSeparator}$fullName',
    );
    if (fullName == _file.uri.pathSegments.last) return;
    if (target.existsSync()) {
      _showMessage('Bu adla bir dosya zaten var.');
      return;
    }

    setState(() => _isRenaming = true);
    try {
      await _releasePlayback();
      final renamedFile = _file.renameSync(target.path);
      if (!mounted) return;
      setState(() {
        _file = renamedFile;
        _title = fullName;
        _error = null;
        _isLoading = true;
      });
      await _initialize();
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() {
          _error = null;
          _isLoading = true;
        });
        await _initialize();
        _showMessage('Dosya yeniden adlandırılamadı: ${error.message}');
      }
    } finally {
      if (mounted) setState(() => _isRenaming = false);
    }
  }

  Future<void> _releasePlayback() async {
    await _audioStateSubscription?.cancel();
    await _audioPositionSubscription?.cancel();
    await _audioDurationSubscription?.cancel();
    _audioStateSubscription = null;
    _audioPositionSubscription = null;
    _audioDurationSubscription = null;

    final audioPlayer = _audioPlayer;
    _audioPlayer = null;
    if (audioPlayer != null) await audioPlayer.dispose();

    final chewie = _chewieController;
    _chewieController = null;
    chewie?.dispose();
    final videoController = _videoController;
    _videoController = null;
    if (videoController != null) await videoController.dispose();
  }

  Future<void> _shareFile() async {
    if (!await _file.exists()) {
      _showMessage('Paylaşılacak dosya bulunamadı.');
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(_file.path)], title: _title, subject: _title),
      );
    } catch (error) {
      debugPrint('[VidSave Oynatıcı] Dosya paylaşımı başarısız: $error');
      if (mounted) _showMessage('Dosya paylaşılırken bir hata oluştu.');
    }
  }

  Future<void> _toggleFullScreen() async {
    if (_isAudio) {
      final isLandscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      await SystemChrome.setPreferredOrientations(
        isLandscape
            ? const [DeviceOrientation.portraitUp]
            : const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
      );
      return;
    }

    final chewie = _chewieController;
    if (chewie == null) return;
    if (chewie.isFullScreen) {
      chewie.exitFullScreen();
    } else {
      chewie.enterFullScreen();
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _surface,
        ),
      );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: _background,
      appBar: isLandscape
          ? null
          : AppBar(
              backgroundColor: _background,
              foregroundColor: Colors.white,
              title: Text(
                _title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              actions: [
                IconButton(
                  key: const Key('premium_player_rename'),
                  tooltip: 'Yeniden adlandır',
                  onPressed: _isRenaming ? null : _showRenameDialog,
                  icon: const Icon(Icons.edit_rounded),
                ),
              ],
            ),
      body: SafeArea(
        top: !isLandscape,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : _error != null
            ? _buildError()
            : _isAudio
            ? _buildAudioPlayer()
            : _buildVideoPlayer(),
      ),
    );
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: _accent, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Medya açılamadı',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _shareFile,
            icon: const Icon(Icons.share_rounded),
            label: const Text('Paylaş dosya'),
          ),
        ],
      ),
    ),
  );

  Widget _buildVideoPlayer() {
    final chewie = _chewieController;
    final controller = _videoController;
    if (chewie == null || controller == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: Chewie(controller: chewie),
            ),
          ),
        ),
        if (MediaQuery.orientationOf(context) != Orientation.landscape)
          _buildActionBar(),
      ],
    );
  }

  Widget _buildAudioPlayer() {
    final maxMilliseconds = math.max(1, _audioDuration.inMilliseconds);
    final position = _audioPosition.inMilliseconds
        .clamp(0, maxMilliseconds)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _waveAnimation,
                      builder: (context, child) => CustomPaint(
                        painter: _WaveformPainter(_waveAnimation.value),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _surface,
                        border: Border.all(color: Colors.white12),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.18),
                            blurRadius: 48,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        size: 84,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            _title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Slider(
            value: position,
            max: maxMilliseconds.toDouble(),
            activeColor: _accent,
            inactiveColor: Colors.white24,
            onChanged: _audioDuration == Duration.zero
                ? null
                : (value) => setState(
                    () =>
                        _audioPosition = Duration(milliseconds: value.round()),
                  ),
            onChangeEnd: _audioDuration == Duration.zero
                ? null
                : (value) => _seekAudio(Duration(milliseconds: value.round())),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text(
                  _formatDuration(_audioPosition),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  _formatDuration(_audioDuration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('premium_player_seek_backward'),
                tooltip: '10 saniye geri',
                onPressed: _audioDuration <= Duration.zero
                    ? null
                    : () => _seekAudioBy(-10),
                icon: const Icon(Icons.replay_10_rounded),
                color: Colors.white,
                iconSize: 32,
              ),
              const SizedBox(width: 20),
              IconButton.filled(
                key: const Key('premium_player_play_pause'),
                onPressed: _togglePlayback,
                style: IconButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  fixedSize: const Size(68, 68),
                ),
                iconSize: 34,
                icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(width: 20),
              IconButton(
                key: const Key('premium_player_seek_forward'),
                tooltip: '10 saniye ileri',
                onPressed: _audioDuration <= Duration.zero
                    ? null
                    : () => _seekAudioBy(10),
                icon: const Icon(Icons.forward_10_rounded),
                color: Colors.white,
                iconSize: 32,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildActionBar() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _PlayerAction(
        key: const Key('premium_player_quality'),
        icon: Icons.settings_rounded,
        label: _selectedQuality ?? 'Kalite',
        onPressed: _showQualityPicker,
      ),
      _PlayerAction(
        key: const Key('premium_player_share'),
        icon: Icons.share_rounded,
        label: 'Paylaş',
        onPressed: _shareFile,
      ),
      _PlayerAction(
        key: const Key('premium_player_fullscreen'),
        icon: Icons.fullscreen_rounded,
        label: 'Tam ekran',
        onPressed: _toggleFullScreen,
      ),
    ],
  );
}

class _PlayerAction extends StatelessWidget {
  const _PlayerAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(foregroundColor: Colors.white70),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 23),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

class _RenameFileDialog extends StatefulWidget {
  const _RenameFileDialog({required this.initialName, required this.extension});

  final String initialName;
  final String extension;

  @override
  State<_RenameFileDialog> createState() => _RenameFileDialogState();
}

class _RenameFileDialogState extends State<_RenameFileDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF1B232C),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: const Text(
      'Dosya adını düzenle',
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
    ),
    content: TextField(
      controller: _controller,
      autofocus: true,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        suffixText: widget.extension,
        suffixStyle: const TextStyle(color: Colors.white54),
        hintText: 'Dosya adı',
        hintStyle: const TextStyle(color: Colors.white38),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFFF5436)),
        ),
      ),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('İPTAL', style: TextStyle(color: Colors.white70)),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF5436)),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('KAYDET'),
      ),
    ],
  );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = const Color(0xFFFF5436).withValues(alpha: 0.42)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final count = 48;
    final radius = size.shortestSide * 0.34;
    for (var index = 0; index < count; index++) {
      final angle = 2 * math.pi * index / count;
      final wave = (math.sin(index * 0.75 + progress * 2 * math.pi) + 1) / 2;
      final inner = radius + wave * 4;
      final outer = inner + 8 + wave * 20;
      canvas.drawLine(
        Offset(
          center.dx + math.cos(angle) * inner,
          center.dy + math.sin(angle) * inner,
        ),
        Offset(
          center.dx + math.cos(angle) * outer,
          center.dy + math.sin(angle) * outer,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
