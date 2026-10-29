import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backend_settings.dart';
import 'bulk_download_service.dart';
import 'download_exception_handler.dart';
import 'downloads_screen.dart';
import 'media_downloader.dart';
import 'admob_service.dart';
import 'batch_download_screen.dart';
import 'services/unified_download_engine.dart';

enum BulkItemStatus { pending, downloading, completed, error }

class BulkDownloadItemState {
  final String url;
  BulkItemStatus status;
  String? title;
  double? progress;
  String? error;

  BulkDownloadItemState({
    required this.url,
    this.status = BulkItemStatus.pending,
    this.title,
    this.progress,
    this.error,
  });
}

/// Kullanıcının alt alta birden fazla bağlantı yapıştırıp tek tıkla toplu olarak
/// indirebildiği, anlık 'X/Y İndiriliyor...' durumunu gösteren ekran.
class BulkDownloadScreen extends StatefulWidget {
  const BulkDownloadScreen({
    super.key,
    required this.resolver,
    required this.downloader,
    this.settingsStore,
  });

  final MediaResolver resolver;
  final MediaDownloader downloader;
  final BackendSettingsStore? settingsStore;

  @override
  State<BulkDownloadScreen> createState() => _BulkDownloadScreenState();
}

class _BulkDownloadScreenState extends State<BulkDownloadScreen> {
  final TextEditingController _urlsController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  DownloadKind _selectedKind = DownloadKind.video;
  bool _isProcessing = false;
  int _currentIndex = 0;
  int _totalCount = 0;
  List<BulkDownloadItemState> _items = [];
  String? _overallStatusText;

  @override
  void initState() {
    super.initState();
    _urlsController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _urlsController.removeListener(_onTextChanged);
    _urlsController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  List<String> get _detectedUrls =>
      BulkDownloadService.parseBulkUrls(_urlsController.text);

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.trim().isNotEmpty) {
      final current = _urlsController.text.trim();
      final newContent = current.isEmpty
          ? text.trim()
          : '$current\n${text.trim()}';
      _urlsController.text = newContent;
    }
  }

  Future<void> _startBulkDownload() async {
    final urls = _detectedUrls;
    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen geçerli en az bir indirme bağlantısı girin.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    _focusNode.unfocus();

    await AdmobService.instance.showRewardedAdOrBypass(
      onRewardEarned: () async {
        if (!mounted) return;
        await _executeBulkDownload(urls);
      },
    );
  }

  Future<void> _executeBulkDownload(List<String> urls) async {
    setState(() {
      _isProcessing = true;
      _totalCount = urls.length;
      _currentIndex = 0;
      _items = urls.map((u) => BulkDownloadItemState(url: u)).toList();
      _overallStatusText =
          '1/$_totalCount ${_selectedKind == DownloadKind.audio ? "MP3" : "Video"} İndiriliyor…';
    });

    // İsteğe bağlı backend /api/toplu-indir çağrısı
    if (widget.settingsStore != null) {
      try {
        final settings = await widget.settingsStore!.load();
        if (settings.isConfigured) {
          unawaited(
            BulkDownloadService.sendBulkDownloadRequest(
              urls: urls,
              kind: _selectedKind,
              settings: settings,
            ).catchError((_) => <String, dynamic>{}),
          );
        }
      } catch (_) {}
    }

    // Her URL için sırayla indirme döngüsü
    for (int i = 0; i < _items.length; i++) {
      if (!mounted) return;

      final currentItem = _items[i];
      final currentNum = i + 1;
      final typeLabel = _selectedKind == DownloadKind.audio ? 'MP3' : 'Video';

      setState(() {
        _currentIndex = currentNum;
        currentItem.status = BulkItemStatus.downloading;
        _overallStatusText = '$currentNum/$_totalCount $typeLabel İndiriliyor…';
      });

      try {
        final cleanUrl = evrenselTemizUrl(currentItem.url);
        final file = await UnifiedDownloadEngine.instance.download(
          rawUrl: cleanUrl,
          type: _selectedKind == DownloadKind.audio ? 'mp3' : 'video',
          preferredTitle: 'Toplu $typeLabel İndirme ($currentNum/$_totalCount)',
          onProgress: (received, total, progress, speed, status) {
            if (!mounted) return;
            setState(() {
              currentItem.progress = progress;
            });
          },
          fallbackResolver: widget.resolver,
          fallbackDownloader: widget.downloader,
        );

        final fileName = file.path.split(Platform.pathSeparator).last;
        currentItem.title = fileName;

        if (!mounted) return;
        setState(() {
          currentItem.status = BulkItemStatus.completed;
          currentItem.progress = 1.0;
        });
      } catch (err) {
        final errorMsg =
            DownloadExceptionHandler.getFriendlyMessage(err, context);

        if (!mounted) return;
        setState(() {
          currentItem.status = BulkItemStatus.error;
          currentItem.error = errorMsg;
        });
      }
    }

    if (!mounted) return;
    final successCount = _items
        .where((it) => it.status == BulkItemStatus.completed)
        .length;

    setState(() {
      _isProcessing = false;
      _overallStatusText =
          'Toplu İndirme Tamamlandı! ($successCount/$_totalCount Başarılı)';
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final detected = _detectedUrls;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Toplu İndirme (Bulk Download)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Dinamik Satır Modu (Batch)',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BatchDownloadScreen(
                    resolver: widget.resolver,
                    downloader: widget.downloader,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Açıklama Kutusu
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.layers_rounded, color: primaryColor, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Birden fazla video veya şarkı bağlantısını alt alta yapıştırın. Sistem tümünü sırayla indirecektir.',
                        style: TextStyle(fontSize: 12.5, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Tür Seçimi (Video / MP3)
              Row(
                children: [
                  const Text(
                    'İndirme Türü:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(width: 14),
                  ChoiceChip(
                    label: const Text('Video (MP4)'),
                    selected: _selectedKind == DownloadKind.video,
                    onSelected: _isProcessing
                        ? null
                        : (val) {
                            if (val) {
                              setState(
                                () => _selectedKind = DownloadKind.video,
                              );
                            }
                          },
                    selectedColor: primaryColor,
                    labelStyle: TextStyle(
                      color: _selectedKind == DownloadKind.video
                          ? Colors.white
                          : null,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Müzik (MP3)'),
                    selected: _selectedKind == DownloadKind.audio,
                    onSelected: _isProcessing
                        ? null
                        : (val) {
                            if (val) {
                              setState(
                                () => _selectedKind = DownloadKind.audio,
                              );
                            }
                          },
                    selectedColor: primaryColor,
                    labelStyle: TextStyle(
                      color: _selectedKind == DownloadKind.audio
                          ? Colors.white
                          : null,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 1. Çok Satırlı Büyük Metin Kutusu: TextField(maxLines: 6)
              TextField(
                controller: _urlsController,
                focusNode: _focusNode,
                maxLines: 6,
                enabled: !_isProcessing,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'İndirilecek Bağlantılar (Her Satıra Bir Link)',
                  hintText: 'https://www.instagram.com/reel/...\nhttps://www.tiktok.com/@user/...\nhttps://youtube.com/watch?v=...',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: primaryColor, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Pano Yapıştır ve Temizle Butonları + Algılanan Sayı
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Algılanan Bağlantı: ${detected.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: detected.isNotEmpty ? primaryColor : Colors.grey,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _isProcessing ? null : _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste_rounded, size: 16),
                        label: const Text('Panodan Yapıştır'),
                      ),
                      if (_urlsController.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Temizle',
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: _isProcessing
                              ? null
                              : () => _urlsController.clear(),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Başlat Butonu
              FilledButton.icon(
                onPressed: _isProcessing || detected.isEmpty
                    ? null
                    : _startBulkDownload,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _isProcessing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(
                  _isProcessing
                      ? 'Toplu İndirme Devam Ediyor…'
                      : 'Toplu İndirmeyi Başlat (${detected.length} Link)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 4. Dinamik İlerleme Çubuğu ve Durum Paneli
              if (_items.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _overallStatusText ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: primaryColor,
                              ),
                            ),
                          ),
                          Text(
                            '$_currentIndex/$_totalCount',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _totalCount > 0
                              ? _currentIndex / _totalCount
                              : 0,
                          minHeight: 8,
                          backgroundColor: primaryColor.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Her bir bağlantının durum listesi
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final it = _items[idx];
                    return _buildItemTile(it, idx + 1, primaryColor);
                  },
                ),
                const SizedBox(height: 16),

                if (!_isProcessing)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DownloadsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('İndirilen Dosyaları Aç'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemTile(
    BulkDownloadItemState item,
    int index,
    Color primaryColor,
  ) {
    Widget trailing;
    switch (item.status) {
      case BulkItemStatus.pending:
        trailing = const Text(
          'Bekliyor',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        );
        break;
      case BulkItemStatus.downloading:
        trailing = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: item.progress,
            color: primaryColor,
          ),
        );
        break;
      case BulkItemStatus.completed:
        trailing = const Icon(Icons.check_circle_rounded, color: Colors.green);
        break;
      case BulkItemStatus.error:
        trailing = const Icon(Icons.error_outline_rounded, color: Colors.red);
        break;
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: primaryColor.withValues(alpha: 0.15),
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
        ),
        title: Text(
          item.title ?? item.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: item.error != null
            ? Text(
                item.error!,
                style: const TextStyle(color: Colors.red, fontSize: 11),
              )
            : Text(
                item.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
        trailing: trailing,
      ),
    );
  }
}
