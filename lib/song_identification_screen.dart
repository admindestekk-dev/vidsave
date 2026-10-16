import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'song_identification.dart';

abstract interface class SongRecorder {
  Future<bool> hasPermission();
  Future<void> start(RecordConfig config, {required String path});
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class _RecordSongRecorder implements SongRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(RecordConfig config, {required String path}) =>
      _recorder.start(config, path: path);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

typedef SongRecorderFactory = SongRecorder Function();

enum _IdentificationState { idle, recording, identifying, matched, noMatch, error }

class SongIdentificationScreen extends StatefulWidget {
  const SongIdentificationScreen({
    super.key,
    required this.service,
    required this.onOpenBackendSettings,
    this.recorderFactory,
  });

  final SongIdentificationService service;
  final VoidCallback onOpenBackendSettings;
  final SongRecorderFactory? recorderFactory;

  @override
  State<SongIdentificationScreen> createState() =>
      _SongIdentificationScreenState();
}

class _SongIdentificationScreenState extends State<SongIdentificationScreen> {
  static const _maxRecordingDuration = Duration(seconds: 15);
  static const _minimumRecordingDuration = Duration(seconds: 5);

  late final SongRecorder _recorder =
      (widget.recorderFactory ?? _RecordSongRecorder.new)();
  Timer? _recordingTimer;
  Timer? _secondTimer;
  DateTime? _recordingStartedAt;
  Duration _elapsed = Duration.zero;
  _IdentificationState _state = _IdentificationState.idle;
  SongIdentificationResult? _result;
  String? _errorMessage;
  String? _recordingPath;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _recordingTimer?.cancel();
    _secondTimer?.cancel();
    unawaited(_recorder.cancel().catchError((_) {}));
    unawaited(_recorder.dispose().catchError((_) {}));
    final path = _recordingPath;
    if (path != null) unawaited(_deleteTempFile(path));
    super.dispose();
  }

  Future<void> _startRecording() async {
    setState(() {
      _errorMessage = null;
      _result = null;
    });

    try {
      if (!await _recorder.hasPermission()) {
        throw const SongIdentificationException('Mikrofon izni gerekiyor.');
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}${Platform.pathSeparator}'
          'vidsave-identify-${DateTime.now().microsecondsSinceEpoch}.wav';
      _recordingPath = path;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
          noiseSuppress: true,
          echoCancel: true,
        ),
        path: path,
      );
      if (!mounted) return;
      _recordingStartedAt = DateTime.now();
      setState(() {
        _elapsed = Duration.zero;
        _state = _IdentificationState.recording;
      });
      _secondTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final startedAt = _recordingStartedAt;
        if (!mounted || startedAt == null) return;
        setState(() => _elapsed = DateTime.now().difference(startedAt));
      });
      _recordingTimer = Timer(_maxRecordingDuration, _stopRecording);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = _IdentificationState.error;
        _errorMessage = error is SongIdentificationException
            ? error.message
            : 'Mikrofon kaydı başlatılamadı.';
      });
    }
  }

  Future<void> _stopRecording() async {
    if (_state != _IdentificationState.recording) return;
    _recordingTimer?.cancel();
    _secondTimer?.cancel();
    final startedAt = _recordingStartedAt;
    if (startedAt != null) _elapsed = DateTime.now().difference(startedAt);

    try {
      final path = await _recorder.stop();
      if (path == null) {
        throw const SongIdentificationException('Ses kaydı alınamadı.');
      }
      _recordingPath = path;
      if (_elapsed < _minimumRecordingDuration) {
        throw const SongIdentificationException(
          'Şarkıyı tanımak için en az 5 saniye kaydedin.',
        );
      }
      if (!mounted) {
        await _deleteTempFile(path);
        return;
      }
      setState(() => _state = _IdentificationState.identifying);
      final sample = await File(path).readAsBytes();
      final result = await widget.service.identify(sample);
      await _deleteTempFile(path);
      _recordingPath = null;
      if (!mounted) return;
      setState(() {
        _result = result;
        _state = result == null
            ? _IdentificationState.noMatch
            : _IdentificationState.matched;
      });
    } catch (error) {
      final path = _recordingPath;
      if (path != null) await _deleteTempFile(path);
      _recordingPath = null;
      if (!mounted) return;
      setState(() {
        _state = _IdentificationState.error;
        _errorMessage = error is SongIdentificationException
            ? error.message
            : 'Şarkı tanınamadı. Tekrar deneyin.';
      });
    }
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // The recording plugin may already have removed the temporary file.
    }
  }

  String get _durationLabel {
    final seconds = _elapsed.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = _state == _IdentificationState.recording;
    final isBusy = _state == _IdentificationState.identifying;

    return Scaffold(
      appBar: AppBar(title: const Text('Şarkıları Tanımlayın')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.music_note_rounded,
                size: 56,
                color: Color(0xFF087E8B),
              ),
              const SizedBox(height: 18),
              Text(
                isRecording ? 'Dinliyorum…' : 'Yakındaki şarkıyı tanımlayın',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF172B3A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isRecording
                    ? 'Şarkının en az 5 saniyesini kaydedin. Kayıt 15 saniyede durur.'
                    : 'Kısa bir ses örneği kaydedilir ve eşleşme için VidSave backend’ine gönderilir.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF74838D)),
              ),
              const SizedBox(height: 28),
              if (isRecording) ...[
                Text(
                  _durationLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: const Color(0xFF087E8B),
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Durdur'),
                ),
              ] else ...[
                SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: isBusy || _disposed ? null : _startRecording,
                    icon: isBusy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.mic_rounded),
                    label: Text(
                      isBusy ? 'Eşleşme aranıyor…' : 'Kaydı Başlat',
                    ),
                  ),
                ),
              ],
              if (_state == _IdentificationState.matched && _result != null) ...[
                const SizedBox(height: 24),
                _Notice(
                  icon: Icons.check_circle_outline_rounded,
                  message: '${_result!.title}\n${_result!.artist}'
                      '${_result!.album == null ? '' : '\n${_result!.album}'}',
                ),
              ],
              if (_state == _IdentificationState.noMatch) ...[
                const SizedBox(height: 24),
                const _Notice(
                  icon: Icons.search_off_rounded,
                  message: 'Eşleşme bulunamadı. Daha net bir örnekle tekrar deneyin.',
                ),
              ],
              if (_state == _IdentificationState.error) ...[
                const SizedBox(height: 24),
                _Notice(
                  icon: Icons.error_outline_rounded,
                  isError: true,
                  message: _errorMessage ?? 'Şarkı tanınamadı. Tekrar deneyin.',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.onOpenBackendSettings,
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Backend ayarlarını aç'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFF0EF) : const Color(0xFFE5F3F4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isError ? const Color(0xFF9C2F29) : const Color(0xFF087E8B),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? const Color(0xFF9C2F29) : const Color(0xFF17656D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
