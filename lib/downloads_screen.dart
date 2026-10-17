import 'dart:io';
import 'package:flutter/material.dart';
import 'app_localizations.dart';
import 'download_item_model.dart';
import 'lyrics_bottom_sheet.dart';
import 'music_player.dart';
import 'storage_service.dart';
import 'video_player_screen.dart';

/// İndirilen dosyaların (Video ve MP3) kalıcı hafızadan listelendiği,
/// yeni bir dosya indiği an sayfayı yenilemeden otomatik güncellenen dinamik ekran.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, this.initialFilter = 'all'});

  final String initialFilter;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late String _selectedFilter = widget.initialFilter;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
    _loadInitialData();
  }

  /// Uygulama/ekran açılır açılmaz SharedPreferences'tan verileri çeker.
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

  void _confirmDelete(BuildContext context, DownloadItemModel item) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.text('delete_dialog_title')),
        content: Text(
          '"${item.name}" ${l10n.text('delete_dialog_content')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.text('btn_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.removeItem(item.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.text('record_removed')),
                    duration: const Duration(seconds: 2),
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
        title: Text(l10n.text('clear_dialog_title')),
        content: Text(
          l10n.text('clear_dialog_content'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.text('btn_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.clearAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.text('all_cleared')),
                    duration: const Duration(seconds: 2),
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
          content: Text(
            '${l10n.text('file_not_found')}:\n${item.filePath}',
          ),
          backgroundColor: const Color(0xFFD32F2F),
        ),
      );
      return;
    }

    if (item.isAudio) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => MusicPlayerScreen(
            file: file,
            title: item.name,
            autoStart: true,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerScreen(
            file: file,
            title: item.name,
          ),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.text('downloads_screen_title'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        actions: [
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
          // Filtre Seçenekleri (Tümü / Video / MP3)
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
          const Divider(height: 1, color: Color(0xFFE5E9EB)),

          // Dinamik Liste Alanı (ValueListenableBuilder ile anlık güncellenir)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ValueListenableBuilder<List<DownloadItemModel>>(
                    valueListenable: StorageService.downloadsNotifier,
                    builder: (context, allItems, _) {
                      final items = _applyFilter(allItems);

                      if (items.isEmpty) {
                        return _buildEmptyState();
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _buildDownloadCard(item);
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
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12.5,
      ),
      backgroundColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFECEFF1),
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? primary : Colors.transparent,
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
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF87949D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadCard(DownloadItemModel item) {
    final isAudio = item.isAudio;
    final gradient = isAudio
        ? const [Color(0xFFFF8A00), Color(0xFFE52E71)]
        : const [Color(0xFF087E8B), Color(0xFF0B4F6C)];
    final icon = isAudio ? Icons.music_note_rounded : Icons.videocam_rounded;

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
              // Sol İkon Kutusu
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
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
                              fontWeight: FontWeight.w700,
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
                    color: Color(0xFFFF5436),
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
                  color: gradient.first,
                  size: 34,
                ),
                tooltip: AppLocalizations.of(context).text('btn_play'),
                onPressed: () => _openFile(context, item),
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
}
