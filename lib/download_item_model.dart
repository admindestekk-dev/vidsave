import 'dart:io';

/// İndirilen medya dosyasını (video veya MP3) temsil eden veri modeli.
class DownloadItemModel {
  final String id;
  final String name;
  final String type; // 'video' veya 'audio'
  final int sizeInBytes;
  final String filePath;
  final DateTime downloadedAt;
  final String? sourceUrl;

  DownloadItemModel({
    required this.id,
    required this.name,
    required this.type,
    required this.sizeInBytes,
    required this.filePath,
    required this.downloadedAt,
    this.sourceUrl,
  });

  /// Dosya boyutunu okunabilir metin formatına (KB, MB, GB) çevirir.
  String get formattedSize {
    if (sizeInBytes <= 0) return '0 B';
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeInBytes < 1024 * 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Ses (MP3) dosyası olup olmadığını döndürür.
  bool get isAudio =>
      type.toLowerCase() == 'audio' || name.toLowerCase().endsWith('.mp3');

  /// Dosyanın cihaz diskinde hâlâ mevcut olup olmadığını kontrol eder.
  bool get fileExists => File(filePath).existsSync();

  /// JSON haritasından model nesnesi üretir.
  factory DownloadItemModel.fromJson(Map<String, dynamic> json) {
    return DownloadItemModel(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Bilinmeyen Dosya',
      type: json['type'] as String? ?? 'video',
      sizeInBytes: (json['sizeInBytes'] as num?)?.toInt() ?? 0,
      filePath: json['filePath'] as String? ?? '',
      downloadedAt: json['downloadedAt'] != null
          ? DateTime.tryParse(json['downloadedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      sourceUrl: json['sourceUrl'] as String?,
    );
  }

  /// Model nesnesini JSON haritasına dönüştürür.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'sizeInBytes': sizeInBytes,
      'filePath': filePath,
      'downloadedAt': downloadedAt.toIso8601String(),
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
    };
  }
}
