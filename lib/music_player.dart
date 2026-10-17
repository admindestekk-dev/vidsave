import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'lyrics_bottom_sheet.dart';

/// Small playback contract that keeps the UI testable without native audio.
abstract interface class MusicPlayerController {
  Stream<PlayerState> get onPlayerStateChanged;
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
  Stream<void> get onPlayerComplete;

  Future<void> setReleaseMode(ReleaseMode releaseMode);
  Future<void> setSource(Source source);
  Future<void> resume();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<Duration?> getCurrentPosition();
  Future<Duration?> getDuration();
  Future<void> stop();
  Future<void> dispose();
}

/// Creates a playback controller for [asset]. Tests can provide a fake without
/// touching the native audio stack.
typedef AudioPlayerFactory = MusicPlayerController Function(AssetEntity asset);

/// Turns an [AssetEntity] into a playable [Source].
typedef AudioSourceResolver = Future<Source> Function(AssetEntity asset);

class _AudioplayersMusicController implements MusicPlayerController {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) =>
      _player.setReleaseMode(releaseMode);

  @override
  Future<void> setSource(Source source) => _player.setSource(source);

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<Duration?> getCurrentPosition() => _player.getCurrentPosition();

  @override
  Future<Duration?> getDuration() => _player.getDuration();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Bundles the player with the source of the asset currently loaded, so the UI
/// can resume playback without resolving the file again.
class MusicPlayback {
  const MusicPlayback({
    required this.asset,
    required this.player,
    required this.source,
  });

  final AssetEntity asset;
  final MusicPlayerController player;
  final Source source;
}

/// The palette shared with [MusicPlayerScreen] and [MiniPlayer].
const Color _kAccent = Color(0xFF087E8B);
const Color _kAccentSoft = Color(0xFF20B8C5);
const Color _kInk = Color(0xFF263943);
const Color _kMuted = Color(0xFF74838D);

/// Loads [asset] into a fresh [AudioPlayer] and immediately starts playback.
///
/// The caller owns the returned [MusicPlayback] and must dispose its player.
Future<MusicPlayback> openMusicPlayback(
  AssetEntity asset, {
  AudioPlayerFactory? playerFactory,
  AudioSourceResolver? sourceResolver,
  bool autoStart = true,
}) async {
  final player = (playerFactory ?? _defaultAudioPlayerFactory)(asset);
  try {
    final source = await (sourceResolver ?? _defaultAudioSourceResolver)(asset);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(source);
    if (autoStart) await player.resume();
    return MusicPlayback(asset: asset, player: player, source: source);
  } catch (_) {
    await player.dispose();
    rethrow;
  }
}

MusicPlayerController _defaultAudioPlayerFactory(AssetEntity asset) =>
    _AudioplayersMusicController();

Future<Source> _defaultAudioSourceResolver(AssetEntity asset) async {
  final file = await asset.file;
  if (file == null) {
    throw StateError('Müzik dosyasına erişilemiyor.');
  }
  return DeviceFileSource(file.path);
}

/// Full-screen "now playing" page. It shows the artwork placeholder, the song
/// title, a scrubbable [Slider] backed by the player's position stream and the
/// usual previous / play-pause / next controls.
///
/// When [showMiniPlayerOnClose] is true (used for the mini player's "expand"
/// gesture) popping the route leaves the mini player visible instead of
/// stopping playback.
class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({
    super.key,
    this.asset,
    this.file,
    this.title,
    this.player,
    this.autoStart = true,
    this.showMiniPlayerOnClose = false,
    this.playerFactory,
    this.sourceResolver,
  });

  final AssetEntity? asset;
  final File? file;
  final String? title;
  final MusicPlayerController? player;
  final bool autoStart;
  final bool showMiniPlayerOnClose;
  final AudioPlayerFactory? playerFactory;
  final AudioSourceResolver? sourceResolver;

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  static const _kFallbackDuration = Duration(minutes: 3);

  MusicPlayerController? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;

  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _dragValue = 0;
  bool _isDragging = false;
  bool _isLoading = true;
  Object? _error;

  bool get _ownsPlayer => widget.player == null;

  @override
  void initState() {
    super.initState();
    final dur = widget.asset?.duration ?? 0;
    _duration = dur > 0 ? Duration(seconds: dur) : _kFallbackDuration;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (widget.player case final provided?) {
        _player = provided;
        await _subscribe(provided);
      } else if (widget.file != null) {
        final player = _AudioplayersMusicController();
        final source = DeviceFileSource(widget.file!.path);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(source);
        _player = player;
        await _subscribe(player);
      } else if (widget.asset != null) {
        final playback = await openMusicPlayback(
          widget.asset!,
          playerFactory: widget.playerFactory,
          sourceResolver: widget.sourceResolver,
          autoStart: false,
        );
        if (!mounted) {
          await playback.player.dispose();
          return;
        }
        _player = playback.player;
        await _subscribe(playback.player);
      } else {
        throw StateError('Oynatılacak müzik bulunamadı.');
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (widget.autoStart && widget.player == null) {
        await _player?.resume();
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'VidSave music player',
          context: ErrorDescription(
            'while opening ${widget.title ?? widget.asset?.title ?? "müzik"}',
          ),
        ),
      );
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _subscribe(MusicPlayerController player) async {
    _stateSub = player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _playerState = state;
        if (state == PlayerState.completed) {
          _position = _duration;
        }
      });
    });
    _positionSub = player.onPositionChanged.listen((position) {
      if (!mounted || _isDragging) return;
      setState(() => _position = position);
    });
    _durationSub = player.onDurationChanged.listen((duration) {
      if (!mounted || duration == Duration.zero) return;
      setState(() => _duration = duration);
    });
    _completeSub = player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _position = _duration;
        _playerState = PlayerState.completed;
      });
    });

    _position = await player.getCurrentPosition() ?? Duration.zero;
    _duration = await player.getDuration() ?? _duration;
  }

  Future<void> _togglePlayPause() async {
    final player = _player;
    if (player == null) return;
    if (_playerState == PlayerState.playing) {
      await player.pause();
      return;
    }
    if (_playerState == PlayerState.completed) {
      await player.seek(Duration.zero);
    }
    await player.resume();
  }

  Future<void> _seekTo(double seconds) async {
    final player = _player;
    if (player == null) return;
    final target = Duration(seconds: seconds.round());
    setState(() {
      _position = target;
      _isDragging = false;
    });
    await player.seek(target);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    if (_ownsPlayer) {
      final player = _player;
      _player = null;
      if (player != null) {
        unawaited(
          player.stop().catchError((_) {}).whenComplete(player.dispose),
        );
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final durationSeconds = _duration.inSeconds.toDouble();
    final maxSeconds = durationSeconds > 0 ? durationSeconds : 1.0;
    final displaySeconds = _isDragging
        ? _dragValue
        : _position.inSeconds.toDouble().clamp(0.0, maxSeconds);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1E25),
      body: Stack(
        children: [
          Positioned(
            top: -60,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 320,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      _kAccent.withValues(alpha: 0.55),
                      const Color(0xFF0F1E25).withValues(alpha: 0),
                    ],
                    radius: 0.9,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  _buildHeader(),
                  const Spacer(),
                  _buildArtwork(),
                  const SizedBox(height: 28),
                  _buildTitle(),
                  const SizedBox(height: 18),
                  _buildProgress(maxSeconds, displaySeconds, player),
                  const SizedBox(height: 8),
                  _buildControls(),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Geri',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
        const Expanded(
          child: Text(
            'Şimdi Çalıyor',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Şarkı Sözleri (Karaoke)',
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFFF5436).withValues(alpha: 0.15),
            foregroundColor: const Color(0xFFFF5436),
          ),
          icon: const Icon(Icons.lyrics_rounded),
          onPressed: () {
            final title = widget.title ?? widget.asset?.title ?? 'Müzik';
            LyricsBottomSheet.show(
              context: context,
              songTitle: title,
            );
          },
        ),
      ],
    );
  }

  Widget _buildArtwork() {
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kAccent, _kAccentSoft],
        ),
        boxShadow: [
          BoxShadow(
            color: _kAccent.withValues(alpha: 0.35),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: _error != null
          ? const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: Colors.white,
            )
          : const Icon(Icons.music_note_rounded, size: 88, color: Colors.white),
    );
  }

  Widget _buildTitle() {
    final title = widget.title ?? widget.asset?.title ?? 'Bilinmeyen müzik';
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _error != null ? 'Şarkı çalınamadı' : 'VidSave Müzik',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildProgress(
    double maxSeconds,
    double displaySeconds,
    MusicPlayerController? player,
  ) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: _kAccentSoft,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayColor: _kAccentSoft.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            min: 0,
            max: maxSeconds,
            value: displaySeconds,
            onChanged: player == null
                ? null
                : (value) => setState(() {
                    _dragValue = value;
                    _isDragging = true;
                  }),
            onChangeEnd: player == null ? null : _seekTo,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Text(
                _formatDuration(
                  _isDragging ? _dragValue.round() : _position.inSeconds,
                ),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              Text(
                _formatDuration(_duration.inSeconds),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final isPlaying = _playerState == PlayerState.playing;
    final enabled = _player != null && _error == null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: enabled ? _seekBackward : null,
          tooltip: '10 saniye geri',
          iconSize: 30,
          color: Colors.white,
          disabledColor: Colors.white24,
          icon: const Icon(Icons.replay_10_rounded),
        ),
        const SizedBox(width: 18),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [_kAccent, _kAccentSoft]),
            boxShadow: [
              BoxShadow(
                color: _kAccent.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: IconButton(
            onPressed: enabled ? _togglePlayPause : null,
            tooltip: isPlaying ? 'Duraklat' : 'Oynat',
            iconSize: 40,
            padding: const EdgeInsets.all(14),
            color: Colors.white,
            disabledColor: Colors.white54,
            icon: _isLoading && _error == null
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
          ),
        ),
        const SizedBox(width: 18),
        IconButton(
          onPressed: enabled ? _seekForward : null,
          tooltip: '10 saniye ileri',
          iconSize: 30,
          color: Colors.white,
          disabledColor: Colors.white24,
          icon: const Icon(Icons.forward_10_rounded),
        ),
      ],
    );
  }

  Future<void> _seekBackward() async {
    final target = _position - const Duration(seconds: 10);
    await _player?.seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> _seekForward() async {
    final target = _position + const Duration(seconds: 10);
    await _player?.seek(target > _duration ? _duration : target);
  }
}

/// Compact "now playing" bar that sits above the bottom navigation while a song
/// plays. Tapping the row opens [MusicPlayerScreen] without stopping the audio;
/// the close button stops playback and hides the bar.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.asset,
    required this.player,
    required this.onClose,
  });

  final AssetEntity asset;
  final MusicPlayerController player;
  final VoidCallback onClose;

  Future<void> _openFullPlayer(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MusicPlayerScreen(
          asset: asset,
          player: player,
          showMiniPlayerOnClose: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = asset.title ?? 'Bilinmeyen müzik';
    final fallbackDuration = asset.duration > 0
        ? Duration(seconds: asset.duration)
        : const Duration(minutes: 3);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openFullPlayer(context),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE7ECEF))),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [_kAccent, _kAccentSoft],
                    ),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kInk,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _MiniProgress(
                        player: player,
                        fallbackDuration: fallbackDuration,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                _MiniPlayPauseButton(player: player),
                IconButton(
                  onPressed: onClose,
                  tooltip: 'Kapat',
                  color: _kMuted,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayPauseButton extends StatelessWidget {
  const _MiniPlayPauseButton({required this.player});

  final MusicPlayerController player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.onPlayerStateChanged,
      initialData: PlayerState.stopped,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data == PlayerState.playing;
        return IconButton(
          onPressed: () async {
            if (isPlaying) {
              await player.pause();
            } else {
              if (snapshot.data == PlayerState.completed) {
                await player.seek(Duration.zero);
              }
              await player.resume();
            }
          },
          tooltip: isPlaying ? 'Duraklat' : 'Oynat',
          color: _kAccent,
          icon: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
        );
      },
    );
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.player, required this.fallbackDuration});

  final MusicPlayerController player;
  final Duration fallbackDuration;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.onPositionChanged,
      initialData: Duration.zero,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration>(
          stream: player.onDurationChanged,
          initialData: fallbackDuration,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? fallbackDuration;
            final total = duration.inMilliseconds > 0
                ? duration.inMilliseconds
                : fallbackDuration.inMilliseconds;
            final position = positionSnapshot.data ?? Duration.zero;
            final value = total > 0
                ? (position.inMilliseconds / total).clamp(0.0, 1.0)
                : 0.0;
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: const Color(0xFFE7ECEF),
                valueColor: const AlwaysStoppedAnimation<Color>(_kAccentSoft),
              ),
            );
          },
        );
      },
    );
  }
}

String _formatDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final remainingSeconds = duration.inSeconds
      .remainder(60)
      .toString()
      .padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$remainingSeconds';
  }
  return '$minutes:$remainingSeconds';
}
