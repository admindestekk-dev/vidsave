import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../backend_media_resolver.dart';
import '../client_media_resolver.dart';
import '../download_item_model.dart';
import '../download_notification_service.dart';
import '../media_downloader.dart';
import '../storage_service.dart';
import 'api_service.dart';
import 'download_manager.dart';

/// VidSave Evrensel Birleşik İndirme Motoru (Unified Download Engine)
///
/// 'HIZLI İNDİRME PANELİ'nin sıfır hata ile çalışan altyapısını
/// (Render Pro API + Dio Direct Download + Fallback Engine)
/// tüm platformlara (FB, IG, TT, VM, X, DM, Pinterest, MP3, Toplu İndirme)
/// ortak bir servis olarak sunar.
class UnifiedDownloadEngine {
  UnifiedDownloadEngine._();
  static final UnifiedDownloadEngine instance = UnifiedDownloadEngine._();

  /// Verilen URL için önizleme veya kalite seçeneklerini çözer.
  ///
  /// Önce Render Pro ApiService üzerinden analiz dener.
  /// Başarısız olursa veya URL değilse yedek [fallbackResolver] veya [ClientMediaResolver]'a geçer.
  Future<MediaPreview> preview(
    String urlOrQuery,
    DownloadKind kind, {
    MediaResolver? fallbackResolver,
  }) async {
    final cleanUrl = evrenselTemizUrl(urlOrQuery);
    final isUrl =
        cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://');

    final isCustomTestResolver = fallbackResolver != null &&
        fallbackResolver is! BackendMediaResolver &&
        fallbackResolver is! ClientMediaResolver;

    if (isUrl && !isCustomTestResolver) {
      try {
        final analyzeResult = await ApiService.instance.analyze(
          url: cleanUrl,
          type: kind == DownloadKind.audio ? 'mp3' : 'video',
        );

        final isAudio = kind == DownloadKind.audio;
        final qualities = isAudio
            ? const [
                VideoQuality(
                  height: 0,
                  label: 'MP3 Ses Dosyası (320 kbps - En Yüksek Kalite)',
                ),
                VideoQuality(
                  height: 192,
                  label: 'MP3 Standart Kalite (192 kbps)',
                ),
                VideoQuality(height: 128, label: 'MP3 Hızlı İndir (128 kbps)'),
              ]
            : const [
                VideoQuality(height: 1080, label: '1080p Full HD'),
                VideoQuality(height: 720, label: '720p HD'),
                VideoQuality(height: 480, label: '480p Standart'),
                VideoQuality(height: 360, label: '360p Hızlı İndir'),
              ];

        return MediaPreview(
          title: analyzeResult.title,
          duration: analyzeResult.duration != null
              ? Duration(seconds: analyzeResult.duration!)
              : null,
          qualities: qualities,
        );
      } catch (e) {
        debugPrint(
          'UnifiedDownloadEngine: Sunucu önizlemesi yapılamadı ($e), yedek motora geçiliyor...',
        );
      }
    }

    final resolver = fallbackResolver ?? ClientMediaResolver();
    final effectiveUri = Uri.tryParse(cleanUrl) ?? Uri.parse(urlOrQuery);
    return resolver.preview(effectiveUri, kind);
  }

  /// Tüm indirme noktalarının kullandığı ortak, kararlı ve hatasız indirme fonksiyonu.
  ///
  /// 'HIZLI İNDİRME PANELİ'nin kanıtlanmış akışını çalıştırır:
  /// 1. [ApiService.instance.analyze] ile Render Pro sunucusunda linki çözer.
  /// 2. Doğrudan akış adresi geldiyse [ApiService.instance.downloadFile] (Dio) ile telefona indirir.
  /// 3. Sunucuya ulaşılamazsa veya manifest (.m3u8) geldiyse cihaz içi motor ile tamamlar.
  /// 4. Telefonun üst bildirim çubuğunu, canlı hızı ve yüzdeyi eş zamanlı günceller.
  /// 5. Veritabanına ([StorageService]) ve Galeri/Medya deposuna otomatik kaydeder.
  Future<File> download({
    required String rawUrl,
    required String type, // 'video' veya 'mp3'
    String? preferredTitle,
    int? height,
    double? startTime,
    double? endTime,
    String? audioEffect,
    void Function(
      int received,
      int? total,
      double? progress,
      String speed,
      String status,
    )?
    onProgress,
    void Function(String status)? onStatus,
    MediaResolver? fallbackResolver,
    MediaDownloader? fallbackDownloader,
  }) async {
    final cleanUrl = evrenselTemizUrl(rawUrl);
    final targetUrl = cleanUrl.isNotEmpty ? cleanUrl : rawUrl.trim();
    final isAudio =
        type.toLowerCase() == 'mp3' || type.toLowerCase() == 'audio';
    final normalizedType = isAudio ? 'mp3' : 'video';

    final notifService = DownloadNotificationService.instance;
    final notificationId = notifService.allocateNotificationId();
    final defaultTitle =
        preferredTitle ?? (isAudio ? 'MP3 İndirme' : 'Video İndirme');
    int lastNotifPercent = -1;

    DateTime? lastProgressTime;
    int? lastReceivedBytes;
    String downloadSpeed = '0 KB/s';

    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    DownloadManager.instance.startTask(
      id: taskId,
      title: defaultTitle,
      url: targetUrl,
      type: normalizedType,
    );

    onStatus?.call('İndiriliyor…');

    try {
      // -----------------------------------------------------------------------
      // 1. AŞAMA: HIZLI İNDİRME PANELİ SUNUCU ALTYAPISI (ApiService Render Pro)
      // -----------------------------------------------------------------------
      final isCustomTestResolver = fallbackResolver != null &&
          fallbackResolver is! BackendMediaResolver &&
          fallbackResolver is! ClientMediaResolver;

      AnalyzeResult? analyzeResult;
      if (!isCustomTestResolver) {
        try {
          analyzeResult = await ApiService.instance.analyze(
            url: targetUrl,
            type: normalizedType,
          );
        } catch (serverErr) {
          debugPrint(
            'UnifiedDownloadEngine: Sunucu analizi yapılamadı ($serverErr), cihaz içi lokal motora geçiliyor...',
          );
        }
      }

      final isSegmentedManifest =
          analyzeResult != null &&
          (analyzeResult.downloadUrl.toLowerCase().contains('.m3u8') ||
              analyzeResult.downloadUrl.toLowerCase().contains('.mpd'));

      // DURUM A: Sunucudan doğrudan oynatılabilir ve indirilebilir MP4/MP3 akış linki geldi
      if (analyzeResult != null && !isSegmentedManifest) {
        try {
          final activeTitle = analyzeResult.title.isNotEmpty
              ? analyzeResult.title
              : defaultTitle;

          unawaited(
            notifService.showProgress(
              id: notificationId,
              title: activeTitle,
              percent: null,
            ),
          );

          final appDir = await getApplicationDocumentsDirectory();
          final rawFileName = analyzeResult.filename;
          final cleanFileName = rawFileName
              .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]+'), '_')
              .trim();
          final safeName = cleanFileName.isNotEmpty
              ? cleanFileName
              : 'vidsave_media.${normalizedType == 'mp3' ? 'mp3' : 'mp4'}';

          var uniqueName = safeName;
          var copyIndex = 1;
          while (File('${appDir.path}${Platform.pathSeparator}$uniqueName')
              .existsSync()) {
            final dot = safeName.lastIndexOf('.');
            uniqueName = dot > 0
                ? '${safeName.substring(0, dot)}_$copyIndex${safeName.substring(dot)}'
                : '${safeName}_$copyIndex';
            copyIndex++;
          }
          final savePath =
              '${appDir.path}${Platform.pathSeparator}$uniqueName';

          final downloadedFile = await ApiService.instance.downloadFile(
            downloadUrl: analyzeResult.downloadUrl,
            savePath: savePath,
            headers: analyzeResult.headers,
            onProgress: (received, total) {
              final now = DateTime.now();
              if (lastProgressTime != null && lastReceivedBytes != null) {
                final diffMs = now.difference(lastProgressTime!).inMilliseconds;
                if (diffMs >= 500) {
                  final bytesDiff = received - lastReceivedBytes!;
                  final bytesPerSec = (bytesDiff * 1000) ~/ diffMs;
                  downloadSpeed = '${formatBytes(bytesPerSec)}/s';
                  lastProgressTime = now;
                  lastReceivedBytes = received;
                }
              } else {
                lastProgressTime = now;
                lastReceivedBytes = received;
              }

              final percent = downloadPercent(received, total);
              final status = percent != null
                  ? '%$percent İndiriliyor…'
                  : 'İndiriliyor…';
              final normProgress = (total > 0)
                  ? (received / total)
                  : (percent != null ? percent / 100.0 : null);

              onProgress?.call(
                received,
                total > 0 ? total : null,
                normProgress,
                downloadSpeed,
                status,
              );

              DownloadManager.instance.updateProgress(
                id: taskId,
                received: received,
                total: total > 0 ? total : null,
                progress: normProgress,
                speed: downloadSpeed,
              );

              if (percent != null && percent != lastNotifPercent) {
                lastNotifPercent = percent;
                unawaited(
                  notifService.showProgress(
                    id: notificationId,
                    title: activeTitle,
                    percent: percent,
                    speed: downloadSpeed,
                  ),
                );
              }
            },
          );

          // Veritabanına kaydet
          int fileSize = 0;
          try {
            fileSize = downloadedFile.lengthSync();
          } catch (_) {}

          await StorageService.addItem(
            DownloadItemModel(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: uniqueName,
              type: normalizedType == 'mp3' ? 'audio' : 'video',
              sizeInBytes: fileSize,
              filePath: downloadedFile.path,
              downloadedAt: DateTime.now(),
              sourceUrl: targetUrl,
              thumbnailUrl: analyzeResult.thumbnail,
            ),
          );

          DownloadManager.instance.completeTask(taskId);

          // Sistem galerisine/medya deposuna güvenle kaydet
          unawaited(MediaDownloader.publishToMediaStore(downloadedFile));

          // İndirme bitince sesli onay bildirimi fırlat
          await notifService.showCompleted(
            id: notificationId,
            title: activeTitle,
            fileName: uniqueName,
          );

          return downloadedFile;
        } catch (serverStreamErr) {
          debugPrint(
            'UnifiedDownloadEngine: Sunucu akış indirmesi başarısız oldu ($serverStreamErr). Cihaz içi emniyet motoruna geçiliyor...',
          );
        }
      }

      // -----------------------------------------------------------------------
      // 2. AŞAMA: CİHAZ İÇİ EMNİYET MOTORU (ClientMediaResolver & MediaDownloader)
      // -----------------------------------------------------------------------
      final kind = isAudio ? DownloadKind.audio : DownloadKind.video;
      final effectiveUri = Uri.tryParse(targetUrl) ?? Uri.parse(rawUrl);

      final resolver = (fallbackResolver != null &&
              fallbackResolver is! BackendMediaResolver)
          ? fallbackResolver
          : ClientMediaResolver();
      final media = await resolver.resolve(
        effectiveUri,
        kind,
        height: height,
        startTime: startTime,
        endTime: endTime,
        audioEffect: audioEffect,
      );

      final displayTitle = media.fileName.trim().isNotEmpty
          ? media.fileName.trim()
          : defaultTitle;

      unawaited(
        notifService.showProgress(
          id: notificationId,
          title: displayTitle,
          percent: null,
        ),
      );

      final downloader = fallbackDownloader ?? MediaDownloader();
      final downloadedFile = await downloader.download(
        media,
        onProgress: (received, total) {
          final now = DateTime.now();
          if (lastProgressTime != null && lastReceivedBytes != null) {
            final diffMs = now.difference(lastProgressTime!).inMilliseconds;
            if (diffMs >= 500) {
              final bytesDiff = received - lastReceivedBytes!;
              final bytesPerSec = (bytesDiff * 1000) ~/ diffMs;
              downloadSpeed = '${formatBytes(bytesPerSec)}/s';
              lastProgressTime = now;
              lastReceivedBytes = received;
            }
          } else {
            lastProgressTime = now;
            lastReceivedBytes = received;
          }

          final percent = downloadPercent(received, total);
          final status = percent != null
              ? '%$percent İndiriliyor…'
              : 'İndiriliyor…';
          final normProgress = (total != null && total > 0)
              ? (received / total)
              : (percent != null ? percent / 100.0 : null);

          onProgress?.call(
            received,
            total,
            normProgress,
            downloadSpeed,
            status,
          );

          DownloadManager.instance.updateProgress(
            id: taskId,
            received: received,
            total: total != null && total > 0 ? total : null,
            progress: normProgress,
            speed: downloadSpeed,
          );

          if (percent != null && percent != lastNotifPercent) {
            lastNotifPercent = percent;
            unawaited(
              notifService.showProgress(
                id: notificationId,
                title: displayTitle,
                percent: percent,
                speed: downloadSpeed,
              ),
            );
          }
        },
      );

      final finalFileName = downloadedFile.path
          .split(Platform.pathSeparator)
          .last;
      int fileSize = 0;
      try {
        fileSize = downloadedFile.lengthSync();
      } catch (_) {}

      await StorageService.addItem(
        DownloadItemModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: finalFileName,
          type: normalizedType == 'mp3' ? 'audio' : 'video',
          sizeInBytes: fileSize,
          filePath: downloadedFile.path,
          downloadedAt: DateTime.now(),
          sourceUrl: targetUrl,
        ),
      );

      DownloadManager.instance.completeTask(taskId);

      unawaited(MediaDownloader.publishToMediaStore(downloadedFile));

      await notifService.showCompleted(
        id: notificationId,
        title: displayTitle,
        fileName: finalFileName,
      );

      return downloadedFile;
    } catch (e) {
      DownloadManager.instance.failTask(taskId);
      debugPrint('UnifiedDownloadEngine download hatası: $e');
      unawaited(
        notifService.showError(
          id: notificationId,
          title: defaultTitle,
          error: e.toString(),
        ),
      );
      rethrow;
    }
  }
}
