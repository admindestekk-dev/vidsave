import 'dart:async';

import 'package:flutter/material.dart';

import 'media_downloader.dart';
import 'services/unified_download_engine.dart';
import 'youtube_restriction.dart';

/// Alttan açılan şık 'İndirme formatı' Modal Bottom Sheet penceresi.
///
/// Algılanan veya tarayıcıdan yakalanan medyanın başlık, platform ve süre
/// bilgilerini kart şeklinde gösterir; kullanıcının tek tıkla Video (MP4)
/// veya Ses (MP3) formatında indirme başlatmasını sağlar.
class DownloadFormatBottomSheet extends StatefulWidget {
  const DownloadFormatBottomSheet({
    super.key,
    required this.url,
    this.initialTitle,
    this.allowUrlInput = false,
    required this.onFormatSelected,
    this.resolver,
  });

  final String url;
  final String? initialTitle;
  final bool allowUrlInput;
  final void Function(DownloadKind kind, String selectedUrl) onFormatSelected;
  final MediaResolver? resolver;

  /// Bottom sheet'i açmak için statik yardımcı fonksiyon.
  static Future<void> show({
    required BuildContext context,
    required String url,
    String? initialTitle,
    bool allowUrlInput = false,
    required void Function(DownloadKind kind, String selectedUrl)
    onFormatSelected,
    MediaResolver? resolver,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E2630),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DownloadFormatBottomSheet(
        url: url,
        initialTitle: initialTitle,
        allowUrlInput: allowUrlInput,
        onFormatSelected: onFormatSelected,
        resolver: resolver,
      ),
    );
  }

  @override
  State<DownloadFormatBottomSheet> createState() =>
      _DownloadFormatBottomSheetState();
}

class _DownloadFormatBottomSheetState extends State<DownloadFormatBottomSheet> {
  late final TextEditingController _urlController;
  MediaPreview? _preview;
  bool _isLoadingPreview = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.url);
    _loadPreviewIfNeeded();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _loadPreviewIfNeeded() {
    final clean = evrenselTemizUrl(widget.url);
    if (clean.isEmpty || isYouTubeUrl(clean)) return;

    _isLoadingPreview = true;
    UnifiedDownloadEngine.instance
        .preview(clean, DownloadKind.video, fallbackResolver: widget.resolver)
        .then((preview) {
          if (mounted) {
            setState(() {
              _preview = preview;
              _isLoadingPreview = false;
            });
          }
        })
        .catchError((Object error) {
          debugPrint('DownloadFormatBottomSheet önizleme alınamadı: $error');
          if (mounted) {
            setState(() => _isLoadingPreview = false);
          }
        });
  }

  String _detectPlatformName(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('instagram.com') || lower.contains('instagr.am')) {
      return 'Instagram • Reel / Post';
    }
    if (lower.contains('tiktok.com') || lower.contains('douyin.com')) {
      return 'TikTok • Video';
    }
    if (lower.contains('facebook.com') ||
        lower.contains('fb.watch') ||
        lower.contains('fb.com')) {
      return 'Facebook • Video';
    }
    if (lower.contains('twitter.com') || lower.contains('x.com')) {
      return 'X (Twitter) • Medya';
    }
    if (lower.contains('pinterest.com') || lower.contains('pin.it')) {
      return 'Pinterest • Pin';
    }
    if (lower.contains('vimeo.com')) {
      return 'Vimeo • Video';
    }
    if (lower.contains('dailymotion.com') || lower.contains('dai.ly')) {
      return 'Dailymotion • Video';
    }
    if (lower.contains('reddit.com') || lower.contains('redd.it')) {
      return 'Reddit • Video';
    }

    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host.replaceFirst('www.', '');
    }
    return 'Web Medya';
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getContentTitle() {
    if (widget.initialTitle != null &&
        widget.initialTitle!.trim().isNotEmpty &&
        !widget.initialTitle!.trim().startsWith('http')) {
      return widget.initialTitle!.trim();
    }
    final hasPreviewTitle = _preview != null &&
        _preview!.title.trim().isNotEmpty &&
        !_preview!.title.trim().startsWith('http');
    if (hasPreviewTitle) {
      return _preview!.title.trim();
    }
    if (_preview != null && _preview!.title.trim().isNotEmpty) {
      return _preview!.title.trim();
    }
    final uri = Uri.tryParse(widget.url);
    if (uri != null && uri.host.isNotEmpty) {
      final pathSegs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (pathSegs.isNotEmpty) {
        return pathSegs.last.replaceAll(RegExp(r'[-_]'), ' ');
      }
      return uri.host;
    }
    return widget.url;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final contentTitle = _getContentTitle();
    final platformBadge = _detectPlatformName(widget.url);
    final durationStr = _formatDuration(_preview?.duration);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Üst sürükleme çizgisi
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Başlık Satırı & Kapatma Butonu
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'İndirme formatı',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white60,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // İçerik Bilgileri Kartı (Content Info Card)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF26323E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Medya / Platform İkon Rozeti
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5436).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFF5436)
                              .withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.video_library_rounded,
                          color: Color(0xFFFF5436),
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // İçerik Başlığı ve Platform Bilgileri
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  platformBadge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFFF5436),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              if (durationStr.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.timer_outlined,
                                        size: 11,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        durationStr,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            contentTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          if (_isLoadingPreview) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: const LinearProgressIndicator(
                                minHeight: 2,
                                backgroundColor: Colors.white10,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFFF5436),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (widget.allowUrlInput) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Video veya ses bağlantısı yapıştırın',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(
                      Icons.link_rounded,
                      color: Color(0xFFFF5436),
                      size: 20,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              const Text(
                'İNDİRME SEÇENEKLERİ',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),

              // 1. Video (MP4) Seçeneği
              _buildFormatOptionButton(
                key: const ValueKey('browser_download_video_option'),
                icon: Icons.videocam_rounded,
                iconColor: const Color(0xFFFF5436),
                title: 'Video (MP4)',
                subtitle: 'En Yüksek Kalite • Canlı İndir',
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                  widget.onFormatSelected(
                    DownloadKind.video,
                    _urlController.text.trim(),
                  );
                },
              ),
              const SizedBox(height: 10),

              // 2. Ses (MP3) Seçeneği
              _buildFormatOptionButton(
                key: const ValueKey('browser_download_audio_option'),
                icon: Icons.music_note_rounded,
                iconColor: const Color(0xFF1DB954),
                title: 'Ses (MP3)',
                subtitle: 'Yüksek Kalite Ses Dosyası (320 kbps)',
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                  widget.onFormatSelected(
                    DownloadKind.audio,
                    _urlController.text.trim(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormatOptionButton({
    required Key key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2C3642),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.download_rounded,
                color: Colors.white70,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
