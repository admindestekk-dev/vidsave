import 'package:flutter/material.dart';

/// One of the social platforms the home screen offers as a shortcut.
///
/// Each tile is independent: it has its own download button and resolves the
/// link typed in its own field, so the user never has to share a URL between
/// tiles. A wrong tap costs nothing — nothing is sent until a tile's İNDİR
/// button is pressed.
class DownloadPlatform {
  const DownloadPlatform({
    required this.label,
    required this.hint,
    required this.assetPath,
    required this.letter,
    required this.gradient,
    this.isAudio = false,
    this.allowedDomains = const [],
  });

  final String label;
  final String hint;
  final String assetPath;
  final String letter;
  final List<Color> gradient;

  /// When true the tile represents the standalone "MP3 İNDİR" shortcut: its
  /// download button resolves [DownloadKind.audio] so the resulting file lands
  /// in the "MP3" box of the İndirilenler section.
  final bool isAudio;

  /// Specific domains this platform allows. Empty list means any domain is allowed (e.g. general MP3).
  final List<String> allowedDomains;

  /// Checks if a given URL belongs to this platform.
  bool matchesUrl(String input) {
    if (allowedDomains.isEmpty) return true;
    final trimmed = input.trim().toLowerCase();
    final uri = Uri.tryParse(trimmed);
    final host = uri?.host.toLowerCase() ?? '';

    for (final domain in allowedDomains) {
      final d = domain.toLowerCase();
      if (host == d || host.endsWith('.$d') || trimmed.contains(d)) {
        return true;
      }
    }
    return false;
  }
}

/// Tiles shown on the download screen, in display order.
const List<DownloadPlatform> kDownloadPlatforms = [
  DownloadPlatform(
    label: 'FB VİDEO İNDİR',
    hint: 'facebook.com veya fb.watch',
    assetPath: 'assets/logos/facebook.png',
    letter: 'f',
    gradient: [Color(0xFF1877F2), Color(0xFF3B5998)],
    allowedDomains: ['facebook.com', 'fb.watch', 'fb.com'],
  ),
  DownloadPlatform(
    label: 'İG VİDEO İNDİR',
    hint: 'instagram.com veya instagr.am',
    assetPath: 'assets/logos/instagram.png',
    letter: 'I',
    gradient: [Color(0xFFF58529), Color(0xFFDD2A7B)],
    allowedDomains: ['instagram.com', 'instagr.am'],
  ),
  DownloadPlatform(
    label: 'TT VİDEO İNDİR',
    hint: 'tiktok.com',
    assetPath: 'assets/logos/tiktok.png',
    letter: 't',
    gradient: [Color(0xFF25F4EE), Color(0xFF010101)],
    allowedDomains: ['tiktok.com', 'douyin.com'],
  ),
  DownloadPlatform(
    label: 'VM VİDEO İNDİR',
    hint: 'vimeo.com',
    assetPath: 'assets/logos/vimeo.png',
    letter: 'V',
    gradient: [Color(0xFF1AB7EA), Color(0xFF162221)],
    allowedDomains: ['vimeo.com'],
  ),
  DownloadPlatform(
    label: 'X VİDEO İNDİR',
    hint: 'x.com veya twitter.com',
    assetPath: 'assets/logos/x.png',
    letter: 'X',
    gradient: [Color(0xFF2F3336), Color(0xFF000000)],
    allowedDomains: ['x.com', 'twitter.com', 't.co'],
  ),
  DownloadPlatform(
    label: 'DM VİDEO İNDİR',
    hint: 'dailymotion.com veya dai.ly',
    assetPath: 'assets/logos/dailymotion.png',
    letter: 'd',
    gradient: [Color(0xFF00AFF0), Color(0xFF0066CC)],
    allowedDomains: ['dailymotion.com', 'dai.ly'],
  ),
  DownloadPlatform(
    label: 'MP3 İNDİR',
    hint: 'Ses dosyası veya müzik bağlantısı',
    assetPath: 'assets/logos/mp3.png',
    letter: 'M',
    gradient: [Color(0xFF1DB954), Color(0xFF0E7C4B)],
    isAudio: true,
    allowedDomains: [],
  ),
];

/// A category shown in the "İndirilenler" section: either videos or MP3s.
class DownloadCategory {
  const DownloadCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
}

/// The two boxes that split the İndirilenler section: Video and MP3.
const DownloadCategory kVideoCategory = DownloadCategory(
  title: 'Video',
  subtitle: 'MP4 / hareketli görüntü',
  icon: Icons.video_library_rounded,
  gradient: [Color(0xFF087E8B), Color(0xFF0A5B63)],
);

const DownloadCategory kAudioCategory = DownloadCategory(
  title: 'MP3',
  subtitle: 'Ses / müzik dosyaları',
  icon: Icons.graphic_eq_rounded,
  gradient: [Color(0xFF1DB954), Color(0xFF0E7C4B)],
);

/// A rounded square card holding a platform logo image, its label and its own
/// download button.
///
/// The logo lives in `assets/logos/`. If the file is missing (or fails to
/// decode) we paint the brand colour plus the platform initial instead, so the
/// grid never shows an empty box.
///
/// [onDownload] is the tile's own download action: every square downloads
/// independently of the URL field and of the other squares.
class PlatformButton extends StatelessWidget {
  const PlatformButton({
    super.key,
    required this.platform,
    this.onTap,
    this.onDownload,
    this.linkField,
    this.enabled = true,
    this.selected = false,
    this.downloading = false,
    this.progress,
    this.statusLabel,
  });

  final DownloadPlatform platform;
  final VoidCallback? onTap;

  /// Starts this tile's own download. When null the tile shows no button.
  final VoidCallback? onDownload;

  /// Optional per-tile URL field rendered under the label, so the square can be
  /// filled in without using the shared link field on the page.
  final Widget? linkField;
  final bool enabled;
  final bool selected;

  /// True while this very tile is resolving/downloading its own link.
  final bool downloading;

  /// 0..1 when the server reported a total size, null while unknown.
  final double? progress;

  /// Short status line shown under the button (e.g. "%42", "Çözülüyor…").
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final colors = platform.gradient;
    final tap = enabled ? onTap : null;
    final active = selected || downloading;
    final borderColor = active ? colors.last : const Color(0xFFE7ECEF);

    return Material(
      color: Colors.white,
      elevation: active ? 6 : 2.5,
      shadowColor: colors.last.withValues(alpha: active ? 0.45 : 0.28),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: active ? 2 : 1),
          ),
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PlatformLogo(platform: platform, size: 42),
              const SizedBox(height: 8),
              Text(
                platform.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: Color(0xFF172B3A),
                ),
              ),
              if (linkField != null) ...[
                const SizedBox(height: 5),
                linkField!,
              ],
              if (onDownload != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: FilledButton(
                    onPressed: enabled && !downloading ? onDownload : null,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: colors.last,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: colors.last.withValues(
                        alpha: 0.35,
                      ),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: downloading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download_rounded, size: 15),
                              SizedBox(width: 3),
                              Text(
                                'İNDİR',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                if (downloading) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: colors.last.withValues(alpha: 0.18),
                      valueColor: AlwaysStoppedAnimation<Color>(colors.last),
                    ),
                  ),
                ],
                if (statusLabel != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    statusLabel!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      height: 1.1,
                      color: Color(0xFF74838D),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A large square card for one İndirilenler category (Video or MP3).
///
/// Tapping it opens the matching media library tab, so the user lands directly
/// on the folder that holds the files they just downloaded.
class DownloadCategoryCard extends StatelessWidget {
  const DownloadCategoryCard({
    super.key,
    required this.category,
    this.onTap,
  });

  final DownloadCategory category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = category.gradient;
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: colors.last.withValues(alpha: 0.30),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE7ECEF)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: colors.last.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(category.icon, color: Colors.white, size: 28),
                ),
                const Spacer(),
                Text(
                  category.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172B3A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category.subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF87949D),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The square logo badge itself: image when available, brand-colour fallback
/// with the platform initial when it is not.
class PlatformLogo extends StatelessWidget {
  const PlatformLogo({super.key, required this.platform, this.size = 44});

  final DownloadPlatform platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = platform.gradient;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        platform.letter,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1,
        ),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          platform.assetPath,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      ),
    );
  }
}
