import 'package:flutter/material.dart';

/// VidSave Otomatik Algılama - Hızlı İndirme Dialogu (Quick Download Dialog)
class QuickDownloadDialog extends StatelessWidget {
  /// Dinamik olarak gösterilecek video/medya başlığı veya URL'si
  final String videoTitle;

  /// Video indir butonuna basıldığında tetiklenen callback
  final VoidCallback onDownloadVideo;

  /// MP3 indir butonuna basıldığında tetiklenen callback
  final VoidCallback onDownloadMp3;

  const QuickDownloadDialog({
    super.key,
    required this.videoTitle,
    required this.onDownloadVideo,
    required this.onDownloadMp3,
  });

  /// Dialogu açmak için statik yardımcı metot
  static Future<void> show({
    required BuildContext context,
    required String videoTitle,
    required VoidCallback onDownloadVideo,
    required VoidCallback onDownloadMp3,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => QuickDownloadDialog(
        videoTitle: videoTitle,
        onDownloadVideo: () {
          Navigator.of(ctx).pop();
          onDownloadVideo();
        },
        onDownloadMp3: () {
          Navigator.of(ctx).pop();
          onDownloadMp3();
        },
      ),
    );
  }

  static const Color accentColor = Color(0xFFFF5436); // Turuncu-Mercan

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E), // Premium koyu gri/siyah ton
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Sağ üst köşedeki kapatma butonu
            Positioned(
              top: 14,
              right: 14,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ),

            // Dialog Ana İçeriği
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Turuncu-Mercan Daire İçinde Medya İkonu
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.video_library_rounded,
                        color: accentColor,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 'VidSave Algıladı' Başlığı
                  const Text(
                    'VidSave Algıladı',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Dinamik Video Başlığı
                  Text(
                    videoTitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 26),

                  // 'Video İndir' Butonu (Turuncu-Mercan)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: onDownloadVideo,
                      icon: const Icon(
                        Icons.movie_creation_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Video İndir',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 'MP3 İndir' Butonu (OutlinedButton)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: onDownloadMp3,
                      icon: const Icon(
                        Icons.music_note_rounded,
                        size: 20,
                        color: accentColor,
                      ),
                      label: const Text(
                        'MP3 İndir',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accentColor,
                        side: const BorderSide(
                          color: accentColor,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
