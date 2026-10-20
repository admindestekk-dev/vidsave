import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admob_service.dart';
import 'app_dio.dart';
import 'client_media_resolver.dart';
import 'download_item_model.dart';
import 'download_notification_service.dart';
import 'downloads_screen.dart';
import 'media_downloader.dart';
import 'storage_service.dart';
import 'theme_service.dart';

/// Toplu indirme satırının anlık durumunu belirten durum enum'u
enum BatchItemStatus { idle, downloading, completed, error }

/// Her bir satırın indirme durumu, ilerleme yüzdesi ve hata detayını saklayan model
class BatchRowState {
  BatchItemStatus status;
  double? progress;
  String? error;
  String? fileName;

  BatchRowState({
    this.status = BatchItemStatus.idle,
    this.progress,
    this.error,
    this.fileName,
  });
}

/// Kullanıcıların dinamik olarak link satırları ekleyip silebildiği,
/// Premium AdMob ödüllü reklam onaylı ve Dio 403 tarayıcı başlıklarıyla
/// tüm medyaları cihaz içinde (Client-Side) sırayla indiren Toplu İndirme Ekranı.
class BatchDownloadScreen extends StatefulWidget {
  const BatchDownloadScreen({
    super.key,
    this.resolver,
    this.downloader,
  });

  final MediaResolver? resolver;
  final MediaDownloader? downloader;

  @override
  State<BatchDownloadScreen> createState() => _BatchDownloadScreenState();
}

class _BatchDownloadScreenState extends State<BatchDownloadScreen> {
  /// 1. DİNAMİK DURUM YÖNETİMİ: Varsayılan olarak 1 adet boş URL satırı
  final List<TextEditingController> _controllers = [TextEditingController()];
  final List<BatchRowState> _rowStates = [BatchRowState()];

  DownloadKind _selectedKind = DownloadKind.video;
  bool _isDownloading = false;
  int _completedCount = 0;
  int _totalActiveCount = 0;
  String? _overallStatusText;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Yeni boş link satırı ekler (OutlinedButton tıklandığında)
  void _addNewRow() {
    if (_isDownloading) return;
    setState(() {
      _controllers.add(TextEditingController());
      _rowStates.add(BatchRowState());
    });
  }

  /// Belirtilen satırı listeden tamamen siler
  void _removeRow(int index) {
    if (_isDownloading) return;
    setState(() {
      final removed = _controllers.removeAt(index);
      removed.dispose();
      if (index < _rowStates.length) {
        _rowStates.removeAt(index);
      }
      // Liste tamamen boş kalmasın, en az 1 boş satır bulunsun
      if (_controllers.isEmpty) {
        _controllers.add(TextEditingController());
        _rowStates.add(BatchRowState());
      }
    });
  }

  /// Panodaki geçerli metni aktif veya son boş satıra yapıştırır
  Future<void> _pasteToLastEmptyRow() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;

    setState(() {
      // Önce boş bir satır ara
      int targetIndex = _controllers.indexWhere((c) => c.text.trim().isEmpty);
      if (targetIndex != -1) {
        _controllers[targetIndex].text = text;
      } else {
        // Hepsi doluysa yeni satır açıp yapıştır
        final newController = TextEditingController(text: text);
        _controllers.add(newController);
        _rowStates.add(BatchRowState());
      }
    });
  }

  /// Toplu İndirmeyi Başlat butonuna tıklandığında tetiklenir
  Future<void> _handleStartBatchDownload() async {
    FocusScope.of(context).unfocus();

    // 1. Dolu ve geçerli satırları tespit et
    final filledIndices = <int>[];
    for (int i = 0; i < _controllers.length; i++) {
      if (_controllers[i].text.trim().isNotEmpty) {
        filledIndices.add(i);
      }
    }

    if (filledIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen indirmek için en az bir geçerli video veya müzik linki girin.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // 2. PREMİUM KONTROLÜ
    final isPremium = await AdmobService.instance.checkIsPremium();

    if (!isPremium) {
      // Premium değilse: Önce yasal AdMob ödüllü reklam onay diyalogunu aç
      final accepted = await _showRewardedConsentDialog();
      if (accepted != true || !mounted) {
        return; // Kullanıcı vazgeçti veya diyalog kapatıldı
      }

      // Kullanıcı onayladı -> AdMob Ödüllü Reklamını Oynat
      await AdmobService.instance.showRewardedAdOrBypass(
        onRewardEarned: () async {
          if (!mounted) return;
          await _executeQueueDownload(filledIndices);
        },
        onAdDismissedWithoutReward: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reklam tamamlanmadığı için toplu indirme başlatılamadı.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        },
      );
    } else {
      // Premium üye -> AdMob bypass, doğrudan kuyruğu başlat
      await _executeQueueDownload(filledIndices);
    }
  }

  /// Google Play & AdMob politikalarına %100 uyumlu yasal Ödüllü Reklam Onay Diyalogu
  Future<bool?> _showRewardedConsentDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: isDark ? const Color(0xFF1E2630) : Colors.white,
        title: const Row(
          children: [
            Icon(
              Icons.ondemand_video,
              color: ThemeService.primaryColor,
              size: 26,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ücretsiz İndirme Hakkı Kazan!',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Toplu indirme kuyruğunu başlatmak için kısa bir ödüllü reklam izlemek ister misiniz? Reklamı sonuna kadar izlediğinizde tüm bağlantılarınız sırayla otomatik olarak indirilecektir.',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? Colors.white60 : Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.grey.shade300,
                      ),
                    ),
                  ),
                  child: const Text(
                    'Vazgeç',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: ThemeService.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Reklamı İzle ve Başlat',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
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

  /// 2. KUYRUK MEKANİZMASI:
  /// Evrensel URL temizleme kalkanını ve Dio 403 engelleyici tarayıcı başlıklarını kullanarak
  /// tüm linkleri sırayla (biri bitince diğeri başlayacak şekilde await yapısıyla) indirir.
  Future<void> _executeQueueDownload(List<int> activeIndices) async {
    setState(() {
      _isDownloading = true;
      _completedCount = 0;
      _totalActiveCount = activeIndices.length;
      _overallStatusText =
          '1/$_totalActiveCount ${_selectedKind == DownloadKind.audio ? "MP3" : "Video"} İndiriliyor…';

      for (final idx in activeIndices) {
        _rowStates[idx] = BatchRowState(status: BatchItemStatus.idle);
      }
    });

    final effectiveResolver =
        widget.resolver ?? ClientMediaResolver(dioClient: AppDio.instance);
    final effectiveDownloader =
        widget.downloader ?? MediaDownloader(dioClient: AppDio.instance);

    for (int step = 0; step < activeIndices.length; step++) {
      if (!mounted) return;

      final rowIndex = activeIndices[step];
      final currentNum = step + 1;
      final rawUrl = _controllers[rowIndex].text.trim();
      final typeLabel = _selectedKind == DownloadKind.audio ? 'MP3' : 'Video';

      // İndirilen satırı işaretle
      setState(() {
        _overallStatusText = '$currentNum/$_totalActiveCount $typeLabel İndiriliyor…';
        _rowStates[rowIndex].status = BatchItemStatus.downloading;
        _rowStates[rowIndex].progress = null;
        _rowStates[rowIndex].error = null;
      });

      final notificationId =
          DownloadNotificationService.instance.allocateNotificationId();
      final defaultNotifTitle = 'Toplu $typeLabel İndirme ($currentNum/$_totalActiveCount)';

      try {
        // A) EVRENSEL URL TEMİZLEME KALKANI
        final cleanUrl = evrenselTemizUrl(rawUrl);
        if (cleanUrl.isEmpty) {
          throw const FormatException('Geçerli bir URL bulunamadı.');
        }

        final targetUri = Uri.parse(cleanUrl);

        // B) CLIENT-SIDE MEDYA ÇÖZÜMLEME (DİO BROWSER SPOOFING DESTEKLİ)
        final media = await effectiveResolver.resolve(targetUri, _selectedKind);
        if (!mounted) return;

        final displayTitle = media.fileName.trim().isNotEmpty
            ? media.fileName.trim()
            : defaultNotifTitle;

        _rowStates[rowIndex].fileName = displayTitle;

        unawaited(
          DownloadNotificationService.instance.showProgress(
            id: notificationId,
            title: displayTitle,
            percent: null,
          ),
        );

        // C) MEDYA İNDİRME: DİO 403 ENGELLEYİCİ BAŞLIKLAR & ÇEREZ HAVUZU
        final downloadedFile = await effectiveDownloader.download(
          media,
          onProgress: (received, total) {
            if (!mounted) return;
            final pct = downloadPercent(received, total);
            setState(() {
              _rowStates[rowIndex].progress =
                  (total == null || total <= 0) ? null : received / total;
            });
            if (pct != null) {
              unawaited(
                DownloadNotificationService.instance.showProgress(
                  id: notificationId,
                  title: displayTitle,
                  percent: pct,
                ),
              );
            }
          },
        );

        final fileName = downloadedFile.path.split(Platform.pathSeparator).last;
        int fileSize = 0;
        try {
          fileSize = downloadedFile.lengthSync();
        } catch (_) {}

        // Kalıcı depolamaya kaydet
        unawaited(
          StorageService.addItem(
            DownloadItemModel(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: fileName,
              type: _selectedKind == DownloadKind.audio ? 'audio' : 'video',
              sizeInBytes: fileSize,
              filePath: downloadedFile.path,
              downloadedAt: DateTime.now(),
              sourceUrl: rawUrl,
            ),
          ),
        );

        unawaited(
          DownloadNotificationService.instance.showCompleted(
            id: notificationId,
            title: displayTitle,
            fileName: fileName,
          ),
        );

        if (!mounted) return;
        setState(() {
          _rowStates[rowIndex].status = BatchItemStatus.completed;
          _rowStates[rowIndex].progress = 1.0;
          _completedCount++;
        });
      } catch (err) {
        final errorMsg = switch (err) {
          MediaResolverException(:final message) => message,
          MediaDownloadException(:final message) => message,
          _ => 'İndirme başarısız oldu.',
        };

        unawaited(
          DownloadNotificationService.instance.showError(
            id: notificationId,
            title: defaultNotifTitle,
            error: errorMsg,
          ),
        );

        if (!mounted) return;
        setState(() {
          _rowStates[rowIndex].status = BatchItemStatus.error;
          _rowStates[rowIndex].error = errorMsg;
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _overallStatusText =
          'Toplu İndirme Tamamlandı! ($_completedCount/$_totalActiveCount Başarılı)';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Toplu İndirme Tamamlandı: $_completedCount/$_totalActiveCount dosya başarıyla indirildi.',
        ),
        backgroundColor: _completedCount > 0 ? Colors.green : Colors.redAccent,
        action: SnackBarAction(
          label: 'İndirilenler',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DownloadsScreen()),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Toplu İndirme',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Panodan Yapıştır',
            icon: const Icon(Icons.content_paste_rounded),
            onPressed: _isDownloading ? null : _pasteToLastEmptyRow,
          ),
          IconButton(
            tooltip: 'İndirilen Dosyalar',
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Üst Bölüm: Bilgi kartı ve İndirme Türü Seçimi
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderInfoCard(isDark),
                  const SizedBox(height: 12),
                  _buildTypeChoiceRow(),
                  if (_overallStatusText != null) ...[
                    const SizedBox(height: 10),
                    _buildOverallProgressCard(isDark),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Dinamik Satırlar ve 'Yeni Link Satırı Ekle' Butonu
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                itemCount: _controllers.length + 1, // Satırlar + Ekle Butonu
                itemBuilder: (context, index) {
                  // Listenin en son elemanı: "Yeni Link Satırı Ekle" butonu
                  if (index == _controllers.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
                      child: _buildAddRowButton(),
                    );
                  }
                  return _buildRowItem(index, isDark);
                },
              ),
            ),

            // Ekranın En Altı: Oval, Canlı Turuncu 'Toplu İndirmeyi Başlat' Butonu
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _buildStartBulkDownloadButton(),
            ),
          ],
        ),
      ),
    );
  }

  /// Üst Bilgilendirme Kutusu
  Widget _buildHeaderInfoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeService.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeService.primaryColor.withValues(alpha: 0.22),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.layers_rounded, color: ThemeService.primaryColor, size: 26),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aşağıdaki alanlara dilediğiniz kadar video/müzik linki ekleyin. '
              'Tüm medyalar cihaz içinde sırayla ve güvenle indirilecektir.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  /// Video / MP3 Seçim Çipleri
  Widget _buildTypeChoiceRow() {
    return Row(
      children: [
        const Text(
          'İndirme Türü:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
        ),
        const SizedBox(width: 12),
        ChoiceChip(
          label: const Text('Video (MP4)'),
          selected: _selectedKind == DownloadKind.video,
          selectedColor: ThemeService.primaryColor,
          labelStyle: TextStyle(
            color: _selectedKind == DownloadKind.video ? Colors.white : null,
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
          ),
          onSelected: _isDownloading
              ? null
              : (val) {
                  if (val) setState(() => _selectedKind = DownloadKind.video);
                },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Müzik (MP3)'),
          selected: _selectedKind == DownloadKind.audio,
          selectedColor: ThemeService.primaryColor,
          labelStyle: TextStyle(
            color: _selectedKind == DownloadKind.audio ? Colors.white : null,
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
          ),
          onSelected: _isDownloading
              ? null
              : (val) {
                  if (val) setState(() => _selectedKind = DownloadKind.audio);
                },
        ),
      ],
    );
  }

  /// Genel İlerleme Paneli (İndirme esnasında aktif)
  Widget _buildOverallProgressCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeService.primaryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _overallStatusText ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: ThemeService.primaryColor,
                  ),
                ),
              ),
              if (_isDownloading)
                Text(
                  '$_completedCount/$_totalActiveCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          if (_isDownloading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _totalActiveCount > 0 ? _completedCount / _totalActiveCount : 0,
                minHeight: 6,
                backgroundColor: ThemeService.primaryColor.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(ThemeService.primaryColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Tek Bir Link Satırı Widget'ı
  /// Sol: Numara (Örn: '1.')
  /// Merkez: Link yapıştırma kutusu (TextField)
  /// Sağ: Canlı CircularProgressIndicator, Durum İkonu veya Kırmızı Silme Butonu
  Widget _buildRowItem(int index, bool isDark) {
    final controller = _controllers[index];
    final rowState = index < _rowStates.length ? _rowStates[index] : BatchRowState();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Sol: Numara (Örn: '1.')
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ThemeService.primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}.',
              style: const TextStyle(
                color: ThemeService.primaryColor,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Merkez: Link yapıştırma kutusu (TextField)
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !_isDownloading,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                  fontSize: 12.5,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey.shade300,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(
                    color: ThemeService.primaryColor,
                    width: 1.5,
                  ),
                ),
                suffixIcon: controller.text.isNotEmpty && !_isDownloading
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          controller.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 6),

          // Sağ: İndirme esnasında canlı CircularProgressIndicator,
          // bitince onay/hata ikonu veya kırmızı silme butonu
          SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: _buildRowTrailing(index, rowState),
            ),
          ),
        ],
      ),
    );
  }

  /// Satırın sağındaki durum/silme widget'ı
  Widget _buildRowTrailing(int index, BatchRowState state) {
    switch (state.status) {
      case BatchItemStatus.downloading:
        // İndirme esnasında hangi satırdaki videonun indirildiği canlı döngüyle belli olur
        return SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: state.progress,
            valueColor: const AlwaysStoppedAnimation<Color>(ThemeService.primaryColor),
          ),
        );
      case BatchItemStatus.completed:
        return const Icon(
          Icons.check_circle_rounded,
          color: Colors.green,
          size: 24,
        );
      case BatchItemStatus.error:
        return Tooltip(
          message: state.error ?? 'İndirme hatası',
          child: const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 24,
          ),
        );
      case BatchItemStatus.idle:
        // Kırmızı renkli küçük silme butonu (Icons.delete_outline)
        return IconButton(
          icon: const Icon(
            Icons.delete_outline,
            color: Colors.redAccent,
            size: 22,
          ),
          tooltip: 'Satırı Sil',
          onPressed: _isDownloading ? null : () => _removeRow(index),
        );
    }
  }

  /// Listenin hemen altındaki turuncu-mercan çizgili şık 'Yeni Link Satırı Ekle' (OutlinedButton)
  Widget _buildAddRowButton() {
    return OutlinedButton.icon(
      onPressed: _isDownloading ? null : _addNewRow,
      icon: const Icon(Icons.add, color: ThemeService.primaryColor, size: 20),
      label: const Text(
        'Yeni Link Satırı Ekle',
        style: TextStyle(
          color: ThemeService.primaryColor,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: ThemeService.primaryColor, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  /// Ekranın en altındaki büyük, oval ve canlı turuncu renkli 'Toplu İndirmeyi Başlat' (ElevatedButton)
  Widget _buildStartBulkDownloadButton() {
    final activeCount = _controllers.where((c) => c.text.trim().isNotEmpty).length;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isDownloading ? null : _handleStartBatchDownload,
        icon: _isDownloading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.download_rounded, color: Colors.white, size: 22),
        label: Text(
          _isDownloading
              ? 'Toplu İndirme Devam Ediyor… ($_completedCount/$_totalActiveCount)'
              : (activeCount > 0
                  ? 'Toplu İndirmeyi Başlat ($activeCount Link)'
                  : 'Toplu İndirmeyi Başlat'),
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeService.primaryColor,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: const StadiumBorder(), // Büyük ve oval form
          shadowColor: ThemeService.primaryColor.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
