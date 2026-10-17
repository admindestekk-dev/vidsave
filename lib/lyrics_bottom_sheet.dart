import 'dart:io';
import 'package:flutter/material.dart';

/// Spotify benzeri yukarı kayan (Swipe up / DraggableScrollableSheet)
/// Şık Karaoke / Şarkı Sözleri (Lyrics) Paneli
class LyricsBottomSheet extends StatefulWidget {
  const LyricsBottomSheet({
    super.key,
    required this.songTitle,
    this.lyrics,
    this.filePath,
  });

  final String songTitle;
  final String? lyrics;
  final String? filePath;

  /// Modüler çağrı metodu
  static Future<void> show({
    required BuildContext context,
    required String songTitle,
    String? lyrics,
    String? filePath,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LyricsBottomSheet(
        songTitle: songTitle,
        lyrics: lyrics,
        filePath: filePath,
      ),
    );
  }

  @override
  State<LyricsBottomSheet> createState() => _LyricsBottomSheetState();
}

class _LyricsBottomSheetState extends State<LyricsBottomSheet> {
  String? _loadedLyrics;

  @override
  void initState() {
    super.initState();
    _loadedLyrics = widget.lyrics;
    if (_loadedLyrics == null || _loadedLyrics!.isEmpty) {
      _tryExtractFromId3();
    }
  }

  void _tryExtractFromId3() {
    // MP3 dosya etiketlerinden ID3 USLT okuma
    if (widget.filePath != null && File(widget.filePath!).existsSync()) {
      try {
        final bytes = File(widget.filePath!).readAsBytesSync();
        // USLT tag tag searching in raw ID3v2 header bytes
        final usltIndex = _findSublist(bytes, [0x55, 0x53, 0x4C, 0x54]); // 'USLT'
        if (usltIndex != -1 && usltIndex + 10 < bytes.length) {
          // Read frame size
          final size = (bytes[usltIndex + 4] << 24) |
              (bytes[usltIndex + 5] << 16) |
              (bytes[usltIndex + 6] << 8) |
              bytes[usltIndex + 7];
          final textBytes = bytes.sublist(
            usltIndex + 10,
            (usltIndex + 10 + size).clamp(0, bytes.length),
          );
          // Clean text
          final text = String.fromCharCodes(
            textBytes.where((b) => b >= 32 || b == 10 || b == 13),
          ).trim();
          if (text.isNotEmpty) {
            setState(() {
              _loadedLyrics = text;
            });
            return;
          }
        }
      } catch (_) {}
    }
  }

  int _findSublist(List<int> list, List<int> sub) {
    if (sub.isEmpty) return 0;
    for (int i = 0; i <= list.length - sub.length; i++) {
      bool match = true;
      for (int j = 0; j < sub.length; j++) {
        if (list[i + j] != sub[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  List<String> _parseLyricsLines(String raw) {
    final clean = raw.replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '');
    return clean
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _loadedLyrics != null ? _parseLyricsLines(_loadedLyrics!) : <String>[];

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF191414), // Spotify tarzı koyu renk
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 30,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            children: [
              // Üst çekme çubuğu
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Şarkı Başlığı ve İkon
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5436).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mic_external_on_rounded,
                        color: Color(0xFFFF5436),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Şarkı Sözleri (Karaoke)',
                            style: TextStyle(
                              color: Color(0xFFFF5436),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            widget.songTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white10, height: 1),

              // Sözler Listesi
              Expanded(
                child: lines.isNotEmpty
                    ? ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        itemCount: lines.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              lines[index],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                height: 1.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                size: 52,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Bu parça için senkronize söz bulunamadı.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 14,
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
      },
    );
  }
}
