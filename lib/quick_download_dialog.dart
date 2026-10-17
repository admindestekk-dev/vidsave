import 'package:flutter/material.dart';

/// VidSave Otomatik Algılama - Hızlı İndirme Dialogu (Quick Download Dialog)
///
/// 4 Büyük Özellik Entegrasyonu:
/// 1. Sadece Nakaratı İndir (RangeSlider)
/// 4. Ses Değiştirici ve Remix Modu (Normal, Nightcore, Bass Boost)
class QuickDownloadDialog extends StatefulWidget {
  /// Dinamik olarak gösterilecek video/medya başlığı veya URL'si
  final String videoTitle;

  /// Toplam süre (saniye cinsinden, varsa RangeSlider için referans)
  final double? maxDurationSeconds;

  /// Video indir butonuna basıldığında tetiklenen callback
  final VoidCallback onDownloadVideo;

  /// MP3 indir butonuna basıldığında tetiklenen callback (trim ve effect opsiyonlarıyla)
  final void Function({
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) onDownloadMp3WithOptions;

  const QuickDownloadDialog({
    super.key,
    required this.videoTitle,
    required this.onDownloadVideo,
    required this.onDownloadMp3WithOptions,
    this.maxDurationSeconds,
  });

  /// Dialogu açmak için statik yardımcı metot
  static Future<void> show({
    required BuildContext context,
    required String videoTitle,
    required VoidCallback onDownloadVideo,
    required void Function({
      double? startTime,
      double? endTime,
      String? audioEffect,
    }) onDownloadMp3,
    double? maxDurationSeconds,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => QuickDownloadDialog(
        videoTitle: videoTitle,
        maxDurationSeconds: maxDurationSeconds,
        onDownloadVideo: () {
          Navigator.of(ctx).pop();
          onDownloadVideo();
        },
        onDownloadMp3WithOptions: ({startTime, endTime, audioEffect}) {
          Navigator.of(ctx).pop();
          onDownloadMp3(
            startTime: startTime,
            endTime: endTime,
            audioEffect: audioEffect,
          );
        },
      ),
    );
  }

  static const Color accentColor = Color(0xFFFF5436); // Turuncu-Mercan

  @override
  State<QuickDownloadDialog> createState() => _QuickDownloadDialogState();
}

class _QuickDownloadDialogState extends State<QuickDownloadDialog> {
  // Nakarat / Audio Trimming Durumu
  bool _enableTrimming = false;
  late double _maxDuration;
  late RangeValues _currentRangeValues;

  // Ses Değiştirici ve Remix Modu: "normal", "nightcore", "bassboost"
  String _selectedEffect = 'normal';

  @override
  void initState() {
    super.initState();
    _maxDuration = (widget.maxDurationSeconds != null && widget.maxDurationSeconds! > 10)
        ? widget.maxDurationSeconds!
        : 300.0; // Varsayılan 5 dakika
    _currentRangeValues = RangeValues(0.0, _maxDuration);
  }

  String _formatSeconds(double sec) {
    final m = sec ~/ 60;
    final s = (sec % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
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
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Turuncu-Mercan Daire İçinde Medya İkonu
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: QuickDownloadDialog.accentColor.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: QuickDownloadDialog.accentColor.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.video_library_rounded,
                          color: QuickDownloadDialog.accentColor,
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 'VidSave Algıladı' Başlığı
                    const Text(
                      'VidSave Algıladı',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Dinamik Video Başlığı
                    Text(
                      widget.videoTitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // =========================================================
                    // ÖZELLİK 4: SES DEĞİŞTİRİCİ VE REMIX MODU (ChoiceChips)
                    // =========================================================
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_fix_high_rounded,
                          size: 16,
                          color: QuickDownloadDialog.accentColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Ses Modu & Efekt',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildEffectChip('Normal', 'normal', Icons.music_note_rounded),
                        _buildEffectChip('Nightcore', 'nightcore', Icons.bolt_rounded),
                        _buildEffectChip('Bass Boost', 'bassboost', Icons.speaker_rounded),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // =========================================================
                    // ÖZELLİK 1: SADECE NAKARATI İNDİR (RangeSlider)
                    // =========================================================
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.content_cut_rounded,
                                size: 16,
                                color: _enableTrimming
                                    ? QuickDownloadDialog.accentColor
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Sadece Nakaratı İndir',
                                  style: TextStyle(
                                    color: _enableTrimming
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _enableTrimming,
                                activeThumbColor: QuickDownloadDialog.accentColor,
                                onChanged: (val) {
                                  setState(() => _enableTrimming = val);
                                },
                              ),
                            ],
                          ),
                          if (_enableTrimming) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Başlangıç: ${_formatSeconds(_currentRangeValues.start)}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 11.5,
                                  ),
                                ),
                                Text(
                                  'Bitiş: ${_formatSeconds(_currentRangeValues.end)}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                            RangeSlider(
                              values: _currentRangeValues,
                              min: 0.0,
                              max: _maxDuration,
                              divisions: (_maxDuration > 0) ? (_maxDuration ~/ 1).clamp(1, 100) : 10,
                              activeColor: QuickDownloadDialog.accentColor,
                              inactiveColor: Colors.white24,
                              labels: RangeLabels(
                                _formatSeconds(_currentRangeValues.start),
                                _formatSeconds(_currentRangeValues.end),
                              ),
                              onChanged: (RangeValues values) {
                                setState(() {
                                  _currentRangeValues = values;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // =========================================================
                    // 3. BUTONLAR: Video İndir & MP3 İndir
                    // =========================================================
                    // 1. Video İndir Butonu (Turuncu-Mercan)
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: widget.onDownloadVideo,
                        icon: const Icon(
                          Icons.movie_creation_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Video İndir',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: QuickDownloadDialog.accentColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 2. MP3 İndir Butonu (Outlined)
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          widget.onDownloadMp3WithOptions(
                            startTime: _enableTrimming ? _currentRangeValues.start : null,
                            endTime: _enableTrimming ? _currentRangeValues.end : null,
                            audioEffect: _selectedEffect,
                          );
                        },
                        icon: const Icon(
                          Icons.music_note_rounded,
                          size: 19,
                          color: QuickDownloadDialog.accentColor,
                        ),
                        label: Text(
                          _enableTrimming
                              ? 'Nakaratı MP3 Olarak İndir'
                              : (_selectedEffect != 'normal'
                                  ? 'MP3 İndir ($_selectedEffect)'
                                  : 'MP3 İndir'),
                          style: const TextStyle(
                            color: QuickDownloadDialog.accentColor,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: QuickDownloadDialog.accentColor,
                          side: const BorderSide(
                            color: QuickDownloadDialog.accentColor,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectChip(String label, String value, IconData icon) {
    final isSelected = _selectedEffect == value;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedEffect = value;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? QuickDownloadDialog.accentColor.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? QuickDownloadDialog.accentColor
                    : Colors.white.withValues(alpha: 0.08),
                width: isSelected ? 1.4 : 1.0,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? QuickDownloadDialog.accentColor
                      : Colors.white70,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? QuickDownloadDialog.accentColor
                        : Colors.white70,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
