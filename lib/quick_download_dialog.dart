import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'admob_service.dart';
import 'client_media_resolver.dart';
import 'download_exception_handler.dart';
import 'media_downloader.dart';
import 'services/unified_download_engine.dart';
import 'l10n/l10n_extension.dart';
import 'youtube_restriction.dart';

/// VidSave Otomatik Algılama - Hızlı İndirme Dialogu (Quick Download Dialog)
///
/// Canlı İlerleme Yapısı (UI Progress):
/// 1. Dinamik Değişkenler: `_isDownloading`, `_downloadProgress`, `_downloadSpeed`.
/// 2. Butonların Dönüşümü: Kullanıcı 'Video İndir' veya 'MP3 İndir' butonuna bastığı an,
///    butonlar gizlenir ve yerlerine kurumsal turuncu renkte `LinearProgressIndicator(value: _downloadProgress / 100)`
///    ve altında 'İndiriliyor... %X' ile anlık hız bilgisi gelir.
/// 3. Lokal Motor Entegrasyonu (Client-Side): youtube_explode_dart / Dio ile cihaz içinde
///    indirilirken bayt akışından canlı hız ve yüzde hesaplanır.
/// 4. Bildirim Entegrasyonu: flutter_local_notifications ilerleme çubuğu eş zamanlı
///    güncellenir, işlem bittiğinde dialog otomatik kapanır ve tamamlandı bildirimi düşer.
class QuickDownloadDialog extends StatefulWidget {
  /// Dinamik olarak gösterilecek video/medya başlığı veya URL'si
  final String videoTitle;
  final bool allowUrlInput;

  /// Toplam süre (saniye cinsinden, varsa RangeSlider için referans)
  final double? maxDurationSeconds;

  /// İsteğe bağlı harici Video indir callback'i (geriye uyumluluk için)
  final VoidCallback? onDownloadVideo;

  /// İsteğe bağlı harici MP3 indir callback'i (geriye uyumluluk için)
  final void Function({
    double? startTime,
    double? endTime,
    String? audioEffect,
  })?
  onDownloadMp3WithOptions;

  /// Cihaz içi lokal motor resolver'ı
  final MediaResolver? resolver;

  /// Cihaz içi lokal motor downloader'ı
  final MediaDownloader? downloader;

  /// İndirme başarıyla tamamlandığında tetiklenen geri çağırım
  final void Function(File file, DownloadKind kind)? onDownloadCompleted;
  final Future<void> Function()? onDownloadStarted;
  final void Function(double progress, String speed)? onDownloadProgress;
  final void Function(String message)? onDownloadFailed;
  final DownloadKind? initialDownloadKind;

  const QuickDownloadDialog({
    super.key,
    required this.videoTitle,
    this.allowUrlInput = false,
    this.onDownloadVideo,
    this.onDownloadMp3WithOptions,
    this.maxDurationSeconds,
    this.resolver,
    this.downloader,
    this.onDownloadCompleted,
    this.onDownloadStarted,
    this.onDownloadProgress,
    this.onDownloadFailed,
    this.initialDownloadKind,
  });

  /// Dialogu açmak için statik yardımcı metot
  static Future<void> show({
    required BuildContext context,
    required String videoTitle,
    bool allowUrlInput = false,
    VoidCallback? onDownloadVideo,
    void Function({double? startTime, double? endTime, String? audioEffect})?
    onDownloadMp3,
    MediaResolver? resolver,
    MediaDownloader? downloader,
    void Function(File file, DownloadKind kind)? onDownloadCompleted,
    Future<void> Function()? onDownloadStarted,
    void Function(double progress, String speed)? onDownloadProgress,
    void Function(String message)? onDownloadFailed,
    double? maxDurationSeconds,
    DownloadKind? initialDownloadKind,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => QuickDownloadDialog(
        videoTitle: videoTitle,
        allowUrlInput: allowUrlInput,
        maxDurationSeconds: maxDurationSeconds,
        resolver: resolver,
        downloader: downloader,
        onDownloadCompleted: onDownloadCompleted,
        onDownloadStarted: onDownloadStarted,
        onDownloadProgress: onDownloadProgress,
        onDownloadFailed: onDownloadFailed,
        initialDownloadKind: initialDownloadKind,
        onDownloadVideo: onDownloadVideo,
        onDownloadMp3WithOptions: onDownloadMp3 != null
            ? ({startTime, endTime, audioEffect}) {
                onDownloadMp3(
                  startTime: startTime,
                  endTime: endTime,
                  audioEffect: audioEffect,
                );
              }
            : null,
      ),
    );
  }

  static const Color accentColor = Color(0xFFFF5436); // Turuncu-Mercan

  @override
  State<QuickDownloadDialog> createState() => _QuickDownloadDialogState();
}

class _QuickDownloadDialogState extends State<QuickDownloadDialog> {
  late final TextEditingController _urlController;
  String? _urlInputError;

  // 1. Dinamik Değişkenler
  bool _isDownloading = false;
  bool _autoStartFailed = false;
  double _downloadProgress = 0.0;
  String _downloadSpeed = '0 MB/s';

  // Hız hesaplama değişkenleri

  // Nakarat / Audio Trimming Durumu
  bool _enableTrimming = false;
  late double _maxDuration;
  late RangeValues _currentRangeValues;

  // Ses Değiştirici ve Remix Modu: "normal", "nightcore", "bassboost"
  String _selectedEffect = 'normal';

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.videoTitle);
    _maxDuration =
        (widget.maxDurationSeconds != null && widget.maxDurationSeconds! > 10)
        ? widget.maxDurationSeconds!
        : 300.0; // Varsayılan 5 dakika
    _currentRangeValues = RangeValues(0.0, _maxDuration);
    final initialDownloadKind = widget.initialDownloadKind;
    if (initialDownloadKind != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _isDownloading = true);
        _startDownload(initialDownloadKind);
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String _formatSeconds(double sec) {
    final m = sec ~/ 60;
    final s = (sec % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Canlı indirme akışını (Video veya MP3) tetikler
  Future<void> _startDownload(DownloadKind kind) async {
    final downloadUrl = widget.allowUrlInput
        ? _urlController.text.trim()
        : widget.videoTitle;
    if (downloadUrl.isEmpty) {
      setState(() {
        _urlInputError = 'Önce video veya gönderi bağlantısını yapıştırın.';
        _autoStartFailed = widget.initialDownloadKind != null;
        _isDownloading = false;
      });
      return;
    }
    if (checkAndShowYouTubeRestriction(context, downloadUrl)) {
      if (widget.initialDownloadKind != null && mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    // 1. Premium Kontrolü: Kullanıcı isPremium == true ise hiçbir şey sorma, reklamı tamamen bypass et
    final isPremium = await AdmobService.instance.checkIsPremium();
    if (isPremium) {
      if (!mounted) return;
      await _executeDownload(kind);
      return;
    }

    // 2 & 3. Ücretsiz Kullanıcı İçin Yasal Pop-up (Rewarded Ad Consent Dialog)
    if (!mounted) return;
    final userAccepted = await _showRewardedConsentDialog();
    if (userAccepted != true) {
      if (mounted && widget.initialDownloadKind != null) {
        Navigator.of(context).pop();
      }
      return; // Kullanıcı 'Vazgeç' dedi veya pencereyi kapattı
    }
    if (!mounted) return;

    // 4. Reklam Tetikleyici: AdMob ödüllü test reklamını oynat
    await AdmobService.instance.showRewardedAdOrBypass(
      onRewardEarned: () async {
        if (!mounted) return;
        await _executeDownload(kind);
      },
    );
  }

  /// Google Play ve AdMob politikalarına %100 uyumlu Ödüllü Reklam İzni ve Onay Diyalogu
  Future<bool?> _showRewardedConsentDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF1E2630),
        title: Row(
          children: [
            const Icon(
              Icons.ondemand_video,
              color: QuickDownloadDialog.accentColor,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('rewarded_ad_title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          context.tr('rewarded_ad_desc'),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              // Gri renkli 'Vazgeç' butonu
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                  child: Text(
                    context.tr('btn_cancel'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Turuncu-mercan renkli 'Reklamı İzle ve İndir' butonu
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: QuickDownloadDialog.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    context.tr('watch_ad_and_download'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _executeDownload(DownloadKind kind) async {
    // Harici callback sağlanmışsa ve resolver/downloader verilmemişse eski callback'e yönlendir
    final hasLegacyCallback = kind == DownloadKind.video
        ? widget.onDownloadVideo != null
        : widget.onDownloadMp3WithOptions != null;

    if (widget.resolver == null &&
        widget.downloader == null &&
        hasLegacyCallback) {
      if (kind == DownloadKind.video) {
        Navigator.of(context).pop();
        widget.onDownloadVideo?.call();
      } else {
        Navigator.of(context).pop();
        widget.onDownloadMp3WithOptions?.call(
          startTime: _enableTrimming ? _currentRangeValues.start : null,
          endTime: _enableTrimming ? _currentRangeValues.end : null,
          audioEffect: _selectedEffect,
        );
      }
      return;
    }

    final effectiveResolver = widget.resolver ?? ClientMediaResolver();
    final effectiveDownloader = widget.downloader ?? MediaDownloader();

    // 2. Butonların Dönüşümü: İndirme başladı, butonlar gizlenip progress bar görüntülenir
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadSpeed = '0 MB/s';
    });

    final isAudio = kind == DownloadKind.audio;

    try {
      await widget.onDownloadStarted?.call();
      final file = await UnifiedDownloadEngine.instance.download(
        rawUrl: widget.allowUrlInput
            ? _urlController.text.trim()
            : widget.videoTitle,
        type: isAudio ? 'mp3' : 'video',
        startTime: _enableTrimming ? _currentRangeValues.start : null,
        endTime: _enableTrimming ? _currentRangeValues.end : null,
        audioEffect: _selectedEffect,
        onProgress: (received, total, progress, speed, status) {
          final pct = ((progress ?? 0) * 100).clamp(0.0, 100.0);
          widget.onDownloadProgress?.call(pct, speed);
          if (!mounted) return;
          setState(() {
            _downloadProgress = pct;
            _downloadSpeed = speed;
          });
        },
        fallbackResolver: effectiveResolver,
        fallbackDownloader: effectiveDownloader,
      );

      final fileName = file.path.split(Platform.pathSeparator).last;
      widget.onDownloadCompleted?.call(file, kind);

      if (!mounted) return;

      // İndirme bittiğinde dialog otomatik kapansın
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Başarıyla indirildi: $fileName'),
          backgroundColor: const Color(0xFF20B8C5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, stack) {
      debugPrint('QuickDownloadDialog download error: $e\n$stack');
      widget.onDownloadFailed?.call(e.toString());
      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _autoStartFailed = widget.initialDownloadKind != null;
        _downloadProgress = 0.0;
        _downloadSpeed = '0 MB/s';
      });

      DownloadExceptionHandler.showErrorSnackBar(context, e);
    }
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
                  key: const ValueKey('quick_download_dialog_close_button'),
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
                        color: QuickDownloadDialog.accentColor.withValues(
                          alpha: 0.16,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: QuickDownloadDialog.accentColor.withValues(
                            alpha: 0.35,
                          ),
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
                    Text(
                      context.tr('vidsave_detected'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Dinamik Video Başlığı
                    Text(
                      widget.allowUrlInput
                          ? 'Bağlantıyı düzenleyin veya video linki yapıştırın'
                          : widget.videoTitle,
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
                    if (widget.allowUrlInput) ...[
                      const SizedBox(height: 14),
                      TextField(
                        key: const ValueKey('quick_dialog_url_field'),
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Instagram, TikTok veya video bağlantısı',
                          hintStyle: const TextStyle(color: Colors.white54),
                          errorText: _urlInputError,
                          prefixIcon: const Icon(
                            Icons.link_rounded,
                            color: QuickDownloadDialog.accentColor,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (_) {
                          if (_urlInputError != null) {
                            setState(() => _urlInputError = null);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 18),

                    // Ses Seçenekleri & Nakarat Ayarları (İndirme başlamadıysa göster)
                    if (!_isDownloading &&
                        (widget.initialDownloadKind == null ||
                            _autoStartFailed)) ...[
                      // =======================================================
                      // ÖZELLİK: SES DEĞİŞTİRİCİ VE REMIX MODU (ChoiceChips)
                      // =======================================================
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_fix_high_rounded,
                            size: 16,
                            color: QuickDownloadDialog.accentColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            context.tr('audio_mode_effect'),
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
                          _buildEffectChip(
                            context.tr('normal'),
                            'normal',
                            Icons.music_note_rounded,
                          ),
                          _buildEffectChip(
                            context.tr('nightcore'),
                            'nightcore',
                            Icons.bolt_rounded,
                          ),
                          _buildEffectChip(
                            context.tr('bass_boost'),
                            'bassboost',
                            Icons.speaker_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // =======================================================
                      // ÖZELLİK: SADECE NAKARATI İNDİR (RangeSlider)
                      // =======================================================
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
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
                                  activeThumbColor:
                                      QuickDownloadDialog.accentColor,
                                  onChanged: (val) {
                                    setState(() => _enableTrimming = val);
                                  },
                                ),
                              ],
                            ),
                            if (_enableTrimming) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Başlangıç: ${_formatSeconds(_currentRangeValues.start)}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  Text(
                                    'Bitiş: ${_formatSeconds(_currentRangeValues.end)}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                              RangeSlider(
                                values: _currentRangeValues,
                                min: 0.0,
                                max: _maxDuration,
                                divisions: (_maxDuration > 0)
                                    ? (_maxDuration ~/ 1).clamp(1, 100)
                                    : 10,
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
                    ],

                    // =========================================================
                    // 2. BUTONLARIN DÖNÜŞÜMÜ (UI Progress / İndirme Butonları)
                    // =========================================================
                    if (_isDownloading) ...[
                      // Canlı İlerleme Alanı
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: QuickDownloadDialog.accentColor.withValues(
                              alpha: 0.3,
                            ),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Kurumsal turuncu renkte LinearProgressIndicator
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: _downloadProgress > 0
                                    ? (_downloadProgress / 100).clamp(0.0, 1.0)
                                    : null, // Boyut henüz bilinmiyorsa indeterminate
                                minHeight: 8,
                                backgroundColor: QuickDownloadDialog.accentColor
                                    .withValues(alpha: 0.18),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  QuickDownloadDialog.accentColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Çubuğun hemen altında sol tarafta yüzde, sağ tarafta anlık hız
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'İndiriliyor... %${_downloadProgress.toStringAsFixed(0)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: QuickDownloadDialog.accentColor
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _downloadSpeed,
                                    style: const TextStyle(
                                      color: QuickDownloadDialog.accentColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // 1. Video İndir Butonu (Turuncu-Mercan)
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          key: const ValueKey('quick_dialog_video_button'),
                          onPressed: () => _startDownload(DownloadKind.video),
                          icon: const Icon(
                            Icons.movie_creation_rounded,
                            size: 19,
                            color: Colors.white,
                          ),
                          label: Text(
                            context.tr('download_video_btn'),
                            style: const TextStyle(
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
                          onPressed: () => _startDownload(DownloadKind.audio),
                          icon: const Icon(
                            Icons.music_note_rounded,
                            size: 19,
                            color: QuickDownloadDialog.accentColor,
                          ),
                          label: Text(
                            _enableTrimming
                                ? context.tr('chorus_trimming')
                                : (_selectedEffect != 'normal'
                                      ? '${context.tr('download_audio_btn')} ($_selectedEffect)'
                                      : context.tr('download_audio_btn')),
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
          onTap: _isDownloading
              ? null
              : () {
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
                    : Colors.white.withValues(alpha: 0.1),
                width: 1.2,
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
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
