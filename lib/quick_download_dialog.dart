import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import 'admob_service.dart';
import 'client_media_resolver.dart';
import 'download_item_model.dart';
import 'download_notification_service.dart';
import 'media_downloader.dart';
import 'storage_service.dart';

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

  /// Toplam süre (saniye cinsinden, varsa RangeSlider için referans)
  final double? maxDurationSeconds;

  /// İsteğe bağlı harici Video indir callback'i (geriye uyumluluk için)
  final VoidCallback? onDownloadVideo;

  /// İsteğe bağlı harici MP3 indir callback'i (geriye uyumluluk için)
  final void Function({
    double? startTime,
    double? endTime,
    String? audioEffect,
  })? onDownloadMp3WithOptions;

  /// Cihaz içi lokal motor resolver'ı
  final MediaResolver? resolver;

  /// Cihaz içi lokal motor downloader'ı
  final MediaDownloader? downloader;

  /// İndirme başarıyla tamamlandığında tetiklenen geri çağırım
  final void Function(File file, DownloadKind kind)? onDownloadCompleted;

  const QuickDownloadDialog({
    super.key,
    required this.videoTitle,
    this.onDownloadVideo,
    this.onDownloadMp3WithOptions,
    this.maxDurationSeconds,
    this.resolver,
    this.downloader,
    this.onDownloadCompleted,
  });

  /// Dialogu açmak için statik yardımcı metot
  static Future<void> show({
    required BuildContext context,
    required String videoTitle,
    VoidCallback? onDownloadVideo,
    void Function({
      double? startTime,
      double? endTime,
      String? audioEffect,
    })? onDownloadMp3,
    MediaResolver? resolver,
    MediaDownloader? downloader,
    void Function(File file, DownloadKind kind)? onDownloadCompleted,
    double? maxDurationSeconds,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => QuickDownloadDialog(
        videoTitle: videoTitle,
        maxDurationSeconds: maxDurationSeconds,
        resolver: resolver,
        downloader: downloader,
        onDownloadCompleted: onDownloadCompleted,
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
  // 1. Dinamik Değişkenler
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadSpeed = '0 MB/s';

  // Hız hesaplama değişkenleri
  DateTime? _lastProgressTime;
  int? _lastReceivedBytes;

  // Nakarat / Audio Trimming Durumu
  bool _enableTrimming = false;
  late double _maxDuration;
  late RangeValues _currentRangeValues;

  // Ses Değiştirici ve Remix Modu: "normal", "nightcore", "bassboost"
  String _selectedEffect = 'normal';

  @override
  void initState() {
    super.initState();
    _maxDuration =
        (widget.maxDurationSeconds != null && widget.maxDurationSeconds! > 10)
            ? widget.maxDurationSeconds!
            : 300.0; // Varsayılan 5 dakika
    _currentRangeValues = RangeValues(0.0, _maxDuration);
  }

  String _formatSeconds(double sec) {
    final m = sec ~/ 60;
    final s = (sec % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Canlı indirme akışını (Video veya MP3) tetikler
  Future<void> _startDownload(DownloadKind kind) async {
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
    if (userAccepted != true || !mounted) {
      return; // Kullanıcı 'Vazgeç' dedi veya pencereyi kapattı
    }

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: const Color(0xFF1E2630),
        title: const Row(
          children: [
            Icon(
              Icons.ondemand_video,
              color: QuickDownloadDialog.accentColor,
              size: 26,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ücretsiz İndirme Hakkı Kazan!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Bu videoyu yüksek hızda ücretsiz indirebilmek için kısa bir reklam izlemek ister misiniz? Reklamı sonuna kadar izlediğinizde indirme işleminiz otomatik olarak başlayacaktır.',
          style: TextStyle(
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
                  child: const Text(
                    'Vazgeç',
                    style: TextStyle(
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
                  child: const Text(
                    'Reklamı İzle ve İndir',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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

    if (widget.resolver == null && widget.downloader == null && hasLegacyCallback) {
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
      _lastProgressTime = DateTime.now();
      _lastReceivedBytes = 0;
    });

    final isAudio = kind == DownloadKind.audio;
    final notificationId =
        DownloadNotificationService.instance.allocateNotificationId();
    final notifTitle =
        isAudio ? 'Otomatik MP3 İndirme' : 'Otomatik Video İndirme';
    int lastNotifPercent = -1;

    try {
      final cleanUrl = evrenselTemizUrl(widget.videoTitle);
      final parsed = Uri.parse(cleanUrl);
      final media = await effectiveResolver.resolve(
        parsed,
        kind,
        startTime: _enableTrimming ? _currentRangeValues.start : null,
        endTime: _enableTrimming ? _currentRangeValues.end : null,
        audioEffect: _selectedEffect,
      );

      if (!mounted) return;

      final displayTitle = media.fileName.trim().isNotEmpty
          ? media.fileName.trim()
          : notifTitle;

      // Üst bildirim çubuğunu başlat
      unawaited(
        DownloadNotificationService.instance.showProgress(
          id: notificationId,
          title: displayTitle,
          percent: null,
        ),
      );

      // Cihaz içi indirme işlemi (youtube_explode_dart / Dio / FFmpeg)
      final file = await effectiveDownloader.download(
        media,
        onProgress: (received, total) {
          if (!mounted) return;

          final percent = downloadPercent(received, total);

          // Anlık indirme hızını hesapla
          final now = DateTime.now();
          if (_lastProgressTime != null && _lastReceivedBytes != null) {
            final diffMs = now.difference(_lastProgressTime!).inMilliseconds;
            if (diffMs >= 500) {
              final bytesDiff = received - _lastReceivedBytes!;
              final bytesPerSec = (bytesDiff * 1000) ~/ diffMs;
              _downloadSpeed = '${formatBytes(bytesPerSec)}/s';
              _lastProgressTime = now;
              _lastReceivedBytes = received;
            }
          }

          // Sayfada _downloadProgress ve _downloadSpeed değerlerini canlı güncelle
          setState(() {
            _downloadProgress = percent != null ? percent.toDouble() : 0.0;
          });

          // Telefonun üst bildirim çubuğunu eş zamanlı güncelle
          if (percent != null && percent != lastNotifPercent) {
            lastNotifPercent = percent;
            unawaited(
              DownloadNotificationService.instance.showProgress(
                id: notificationId,
                title: displayTitle,
                percent: percent,
                speed: _downloadSpeed,
              ),
            );
          }
        },
      );

      final fileName = file.path.split(Platform.pathSeparator).last;
      int fileSize = 0;
      try {
        fileSize = file.lengthSync();
      } catch (_) {}

      // Veritabanına / yerel listeye ekle
      unawaited(
        StorageService.addItem(
          DownloadItemModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: fileName,
            type: isAudio ? 'audio' : 'video',
            sizeInBytes: fileSize,
            filePath: file.path,
            downloadedAt: DateTime.now(),
            sourceUrl: widget.videoTitle,
          ),
        ),
      );

      // 4. Bildirim Entegrasyonu: İndirme Tamamlandı bildirimi fırlat
      unawaited(
        DownloadNotificationService.instance.showCompleted(
          id: notificationId,
          title: displayTitle,
          fileName: fileName,
        ),
      );

      widget.onDownloadCompleted?.call(file, kind);

      if (!mounted) return;

      // İndirme bittiğinde dialog otomatik kapansın
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Başarıyla indirildi: $fileName'),
          backgroundColor: const Color(0xFF20B8C5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, stack) {
      debugPrint('QuickDownloadDialog download error: $e\n$stack');
      final errorMsg = switch (e) {
        MediaResolverException(:final message) => message,
        MediaDownloadException(:final message) => message,
        _ => 'İndirme tamamlanamadı: $e',
      };

      unawaited(
        DownloadNotificationService.instance.showError(
          id: notificationId,
          title: notifTitle,
          error: errorMsg,
        ),
      );

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
                        color: QuickDownloadDialog.accentColor
                            .withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: QuickDownloadDialog.accentColor
                              .withValues(alpha: 0.35),
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

                    // Ses Seçenekleri & Nakarat Ayarları (İndirme başlamadıysa göster)
                    if (!_isDownloading) ...[
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
                          _buildEffectChip(
                              'Normal', 'normal', Icons.music_note_rounded),
                          _buildEffectChip(
                              'Nightcore', 'nightcore', Icons.bolt_rounded),
                          _buildEffectChip(
                              'Bass Boost', 'bassboost', Icons.speaker_rounded),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // =======================================================
                      // ÖZELLİK: SADECE NAKARATI İNDİR (RangeSlider)
                      // =======================================================
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
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
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  Text(
                                    'Bitiş: ${_formatSeconds(_currentRangeValues.end)}',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
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
                            horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: QuickDownloadDialog.accentColor
                                .withValues(alpha: 0.3),
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
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
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
                                      horizontal: 8, vertical: 3),
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
                          onPressed: () => _startDownload(DownloadKind.video),
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
                          onPressed: () => _startDownload(DownloadKind.audio),
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
