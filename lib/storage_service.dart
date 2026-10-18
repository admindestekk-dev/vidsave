import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_item_model.dart';

/// İndirilen dosyaların SharedPreferences üzerinden kalıcı olarak saklanmasını
/// ve anlık olarak dinlenmesini sağlayan yerel veritabanı servisi.
class StorageService {
  StorageService._();

  static const String _storageKey = 'vidsave_download_history_v1';

  /// Arayüzün sayfayı yenilemeye gerek kalmadan anlık güncellenmesini
  /// sağlayan ValueNotifier dinleyicisi.
  static final ValueNotifier<List<DownloadItemModel>> downloadsNotifier =
      ValueNotifier<List<DownloadItemModel>>([]);

  /// SharedPreferences örneğini getirir.
  static Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  /// Yerel veritabanındaki tüm kayıtlı dosyaları çeker ve dinleyiciyi günceller.
  static Future<List<DownloadItemModel>> getItems() async {
    try {
      final prefs = await _getPrefs();
      final List<String> rawList = prefs.getStringList(_storageKey) ?? [];

      final List<DownloadItemModel> items = rawList
          .map((jsonStr) {
            try {
              final map = jsonDecode(jsonStr) as Map<String, dynamic>;
              return DownloadItemModel.fromJson(map);
            } catch (e) {
              debugPrint('DownloadItemModel JSON parse hatası: $e');
              return null;
            }
          })
          .whereType<DownloadItemModel>()
          .toList();

      // En son indirilen en üstte görünsün (kronolojik sıralama)
      items.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));

      downloadsNotifier.value = List.unmodifiable(items);
      return items;
    } catch (e) {
      debugPrint('StorageService.getItems hatası: $e');
      return [];
    }
  }

  /// Yeni indirilen bir dosyayı yerel veritabanına ekler ve listeyi anlık günceller.
  static Future<void> addItem(DownloadItemModel item) async {
    try {
      final prefs = await _getPrefs();
      final items = await getItems();

      // Aynı dosya yolu veya kimliğe sahip mükerrer kayıt varsa temizle
      items.removeWhere(
        (existing) =>
            existing.filePath == item.filePath || existing.id == item.id,
      );

      // Listenin en başına ekle
      items.insert(0, item);

      final List<String> rawList = items
          .map((it) => jsonEncode(it.toJson()))
          .toList();

      await prefs.setStringList(_storageKey, rawList);
      downloadsNotifier.value = List.unmodifiable(items);
      debugPrint(
        'StorageService: Dosya kaydedildi -> ${item.name} (${item.formattedSize})',
      );
    } catch (e) {
      debugPrint('StorageService.addItem hatası: $e');
    }
  }

  /// Belirli bir indirme kaydını kimliğine göre yerel veritabanından siler.
  static Future<void> removeItem(String id) async {
    try {
      final prefs = await _getPrefs();
      final items = await getItems();

      items.removeWhere((item) => item.id == id);

      final List<String> rawList = items
          .map((it) => jsonEncode(it.toJson()))
          .toList();

      await prefs.setStringList(_storageKey, rawList);
      downloadsNotifier.value = List.unmodifiable(items);
    } catch (e) {
      debugPrint('StorageService.removeItem hatası: $e');
    }
  }

  /// Tüm indirme geçmişini temizler.
  static Future<void> clearAll() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_storageKey);
      downloadsNotifier.value = [];
    } catch (e) {
      debugPrint('StorageService.clearAll hatası: $e');
    }
  }
}
