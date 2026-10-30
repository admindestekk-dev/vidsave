import 'dart:io';

import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'download_item_model.dart';
import 'lyrics_bottom_sheet.dart';
import 'music_player.dart';
import 'screens/private_vault_screen.dart';
import 'services/download_manager.dart';
import 'services/private_vault_service.dart';
import 'storage_service.dart';
import 'video_player_screen.dart';

/// VidSave Profesyonel İndirme Yöneticisi Ekranı (Downloads Manager Screen)
///
/// Özellikler:
/// 1. Aktif İndirmeler Bölümü: Canlı ilerleme çubuğu, gerçek zamanlı MB/boyut bilgisi,
///    hız sayacı, duraklat (pause) / devam ettir (resume) ve iptal butonları.
/// 2. Tamamlanan İndirmeler Bölümü: Şık kapak resmi / thumbnail desteği, format rozetleri
///    (MP4/MP3), dosya boyutu, oynatma, şarkı sözleri (karaoke) ve silme kontrolleri.
/// 3. Filtreleme: Tümü, Videolar, Müzikler (MP3).
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, this.initialFilter = 'all'});

  final String initialFilter;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late String _selectedFilter = widget.initialFilter;
  bool _isLoading = true;

  static const Color _primaryOrange = Color(0xFFFF5436);
  static const Color _tealAccent = Color(0xFF20B8C5);

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await StorageService.getItems();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<DownloadItemModel> _applyFilter(List<DownloadItemModel> items) {
    if (_selectedFilter == 'video') {
      return items.where((it) => !it.isAudio).toList();
    } else if (_selectedFilter == 'audio') {
      return items.where((it) => it.isAudio).toList();
    }
    return items;
  }

  List<ActiveDownloadTask> _applyActiveFilter(List<ActiveDownloadTask> tasks) {
    if (_selectedFilter == 'video') {
      return tasks.where((t) => !t.isAudio).toList();
    } else if (_selectedFilter == 'audio') {
      return tasks.where((t) => t.isAudio).toList();
    }
    return tasks;
  }

  void _confirmDelete(BuildContext context, DownloadItemModel item) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.text('delete_dialog_title')),
        content: Text('"${item.name}" ${l10n.text('delete_dialog_content')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.text('btn_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.removeItem(item.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.text('record_removed')),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text(l10n.text('btn_delete')),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.text('clear_dialog_title')),
        content: Text(l10n.text('clear_dialog_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.text('btn_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.clearAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.text('all_cleared')),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text(l10n.text('btn_clear_all')),
          ),
        ],
      ),
    );
  }

  void _openFile(BuildContext context, DownloadItemModel item) {
    final file = File(item.filePath);
    if (!file.existsSync()) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.text('file_not_found')}:\n${item.filePath}'),
          backgroundColor: const Color(0xFFD32F2F),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (item.isAudio) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              MusicPlayerScreen(file: file, title: item.name, autoStart: true),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerScreen(file: file, title: item.name),
        ),
      );
    }
  }

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.text('downloads_screen_title'),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'Gizli Kasa',
            icon: const Icon(Icons.shield_rounded, color: _primaryOrange),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const PrivateVaultScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: l10n.text('filter_all'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadInitialData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              if (val == 'clear') _confirmClearAll(context);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    const Icon(Icons.delete_sweep_rounded, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(l10n.text('btn_clear_all')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtre Butonları (Tümü / Video / MP3)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                _buildFilterChip(l10n.text('filter_all'), 'all'),
                const SizedBox(width: 8),
                _buildFilterChip(l10n.text('filter_videos'), 'video'),
                const SizedBox(width: 8),
                _buildFilterChip(l10n.text('filter_music'), 'audio'),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? Colors.white12 : const Color(0xFFE5E9EB),
          ),

          // Liste Alanı (Aktif İndirmeler + Geçmiş İndirmeler)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ValueListenableBuilder<List<ActiveDownloadTask>>(
                    valueListenable:
                        DownloadManager.instance.activeTasksNotifier,
                    builder: (context, allActiveTasks, _) {
                      final activeTasks = _applyActiveFilter(allActiveTasks);

                      return ValueListenableBuilder<List<DownloadItemModel>>(
                        valueListenable: StorageService.downloadsNotifier,
                        builder: (context, allStoredItems, _) {
                          final storedItems = _applyFilter(allStoredItems);

                          if (activeTasks.isEmpty && storedItems.isEmpty) {
                            return _buildEmptyState();
                          }

                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              // 1. AKTİF İNDİRMELER BÖLÜMÜ
                              if (activeTasks.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: _primaryOrange,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'AKTİF İNDİRMELER',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                        color: _primaryOrange,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '(${activeTasks.length})',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _primaryOrange,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                for (final task in activeTasks) ...[
                                  _buildActiveDownloadCard(task),
                                  const SizedBox(height: 12),
                                ],
                                const SizedBox(height: 12),
                              ],

                              // 2. TAMAMLANAN GEÇMİŞ İNDİRMELER
                              if (storedItems.isNotEmpty) ...[
                                if (activeTasks.isNotEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      'TAMAMLANAN DOSYALAR',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                        color: Color(0xFF87949D),
                                      ),
                                    ),
                                  ),
                                for (
                                  var i = 0;
                                  i < storedItems.length;
                                  i++
                                ) ...[
                                  _buildDownloadCard(context, storedItems[i]),
                                  if (i < storedItems.length - 1)
                                    const SizedBox(height: 12),
                                ],
                              ],
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilter = value);
        }
      },
      selectedColor: primary,
      labelStyle: TextStyle(
        color: isSelected
            ? Colors.white
            : (isDark ? Colors.white70 : const Color(0xFF263943)),
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        fontSize: 12.5,
      ),
      backgroundColor: isDark
          ? const Color(0xFF2A2A2A)
          : const Color(0xFFECEFF1),
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? primary : Colors.transparent),
      ),
    );
  }

  /// Aktif indirme kartı (Canlı ilerleme, MB boyutu, hız ve Duraklat/Devam Et butonu)
  Widget _buildActiveDownloadCard(ActiveDownloadTask task) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2630) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryOrange.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryOrange.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Kapak Resmi veya Format İkonu
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 52,
                  height: 52,
                  color: isDark ? Colors.black38 : const Color(0xFFF1F5F7),
                  child:
                      task.thumbnailUrl != null && task.thumbnailUrl!.isNotEmpty
                      ? Image.network(
                          task.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildFallbackThumbnail(task.isAudio),
                        )
                      : _buildFallbackThumbnail(task.isAudio),
                ),
              ),
              const SizedBox(width: 12),

              // Başlık ve İlerleme Detayı
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          task.formattedSizeInfo,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF546E7A),
                          ),
                        ),
                        if (task.speed.isNotEmpty &&
                            task.speed != '0 KB/s') ...[
                          const SizedBox(width: 6),
                          const Text(
                            '•',
                            style: TextStyle(color: Color(0xFFB0BEC5)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            task.speed,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _primaryOrange,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Sağ Taraftaki Duraklat / Devam Et Durum Butonu
              Container(
                decoration: BoxDecoration(
                  color: _primaryOrange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    task.isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    color: _primaryOrange,
                    size: 26,
                  ),
                  tooltip: task.isPaused ? 'Devam Ettir' : 'Duraklat',
                  onPressed: () {
                    if (task.isPaused) {
                      DownloadManager.instance.resumeTask(task.id);
                    } else {
                      DownloadManager.instance.pauseTask(task.id);
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),
              // İptal Butonu
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Color(0xFF90A4AE),
                ),
                tooltip: 'İptal Et',
                onPressed: () => DownloadManager.instance.cancelTask(task.id),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Şık Canlı İlerleme Çubuğu ve Yüzde Yazısı
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: task.progress > 0 ? task.progress : null,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? Colors.white12
                        : const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      _primaryOrange,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                task.formattedProgress,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _primaryOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Geçmiş indirme kartı (Kapak resmi, format etiketi, MB, oynat ve sil)
  Widget _buildDownloadCard(BuildContext cardContext, DownloadItemModel item) {
    final isAudio = item.isAudio;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient = isAudio
        ? const [Color(0xFFFF8A00), Color(0xFFE52E71)]
        : const [Color(0xFF087E8B), Color(0xFF0B4F6C)];

    return Card(
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openFile(context, item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Sol Kapak Resmi / İkon Kutusu
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: item.thumbnailUrl == null
                        ? LinearGradient(
                            colors: gradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isDark ? Colors.black26 : const Color(0xFFF1F5F7),
                  ),
                  child:
                      item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty
                      ? Image.network(
                          item.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildFallbackThumbnail(isAudio),
                        )
                      : _buildFallbackThumbnail(isAudio),
                ),
              ),
              const SizedBox(width: 12),

              // Bilgi Alanı
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isAudio
                                ? const Color(0xFFFFF3E0)
                                : const Color(0xFFE0F7FA),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isAudio ? 'MP3' : 'Video',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isAudio
                                  ? const Color(0xFFE65100)
                                  : const Color(0xFF006064),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.formattedSize,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF546E7A),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '•',
                          style: TextStyle(color: Color(0xFFB0BEC5)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _formatDate(item.downloadedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF87949D),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Sağ İşlem Butonları (Şarkı Sözü, Oynat ve Sil)
              if (isAudio)
                IconButton(
                  icon: const Icon(
                    Icons.lyrics_rounded,
                    color: _primaryOrange,
                    size: 24,
                  ),
                  tooltip: 'Şarkı Sözleri (Karaoke)',
                  onPressed: () {
                    LyricsBottomSheet.show(
                      context: context,
                      songTitle: item.name,
                      filePath: item.filePath,
                    );
                  },
                ),
              IconButton(
                icon: Icon(
                  Icons.play_circle_fill_rounded,
                  color: isAudio ? _primaryOrange : _tealAccent,
                  size: 34,
                ),
                tooltip: AppLocalizations.of(context).text('btn_play'),
                onPressed: () => _openFile(context, item),
              ),
              IconButton(
                icon: const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF90A4AE),
                ),
                tooltip: 'Gizli Klasöre Taşı',
                onPressed: () async {
                  final source = File(item.filePath);
                  if (source.existsSync()) {
                    final messenger = ScaffoldMessenger.maybeOf(cardContext);
                    await PrivateVaultService.instance.importFileToVault(
                      sourceFile: source,
                      originalName: item.name,
                      type: item.type,
                    );
                    await StorageService.removeItem(item.id);
                    messenger?.showSnackBar(
                      const SnackBar(
                        content: Text('Dosya şifrelenerek Gizli Klasöre taşındı! 🔒'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFF90A4AE),
                ),
                tooltip: AppLocalizations.of(context).text('btn_delete'),
                onPressed: () => _confirmDelete(context, item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackThumbnail(bool isAudio) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAudio
              ? const [Color(0xFFFF8A00), Color(0xFFE52E71)]
              : const [Color(0xFF087E8B), Color(0xFF0B4F6C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          isAudio ? Icons.music_note_rounded : Icons.videocam_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFE0F2F1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_download_outlined,
                size: 40,
                color: Color(0xFF087E8B),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.text('empty_downloads_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF172B3A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.text('empty_downloads_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF87949D)),
            ),
          ],
        ),
      ),
    );
  }
}
