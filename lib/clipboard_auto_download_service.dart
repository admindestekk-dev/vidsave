import 'package:flutter/services.dart';

/// Pano (Clipboard) üzerindeki metinleri kontrol eden ve desteklenen
/// video/müzik bağlantılarını (özellikle Instagram ve TikTok) tespit eden yardımcı servis.
class ClipboardAutoDownloadService {
  ClipboardAutoDownloadService._();

  static String? _lastHandledUrl;

  /// Desteklenen bağlantı desenleri.
  static final List<RegExp> _supportedUrlPatterns = [
    RegExp(r'https?://(?:www\.)?instagram\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.)?instagr\.am/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.|vm\.|vt\.)?tiktok\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.)?douyin\.com/[^\s]+', caseSensitive: false),
  ];

  /// Verilen metnin bir Instagram veya TikTok video linki olup olmadığını kontrol eder.
  static bool isSupportedUrl(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final trimmed = text.trim();
    return _supportedUrlPatterns.any((pattern) => pattern.hasMatch(trimmed));
  }

  /// Metin içerisinden ilk geçerli URL'yi ayıklar.
  static String? extractUrl(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final trimmed = text.trim();
    for (final pattern in _supportedUrlPatterns) {
      final match = pattern.firstMatch(trimmed);
      if (match != null) {
        return match.group(0);
      }
    }
    return null;
  }

  /// Panoyu kontrol eder. Eğer yeni ve desteklenen bir URL varsa döndürür,
  /// daha önce işlenmişse veya desteklenmiyorsa null döndürür.
  static Future<String?> checkClipboardForDownloadUrl() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      final url = extractUrl(text);

      if (url != null && url != _lastHandledUrl) {
        return url;
      }
    } catch (_) {
      // Pano erişim kısıtlaması vb. durumlarda sessizce geç
    }
    return null;
  }

  /// Verilen URL'yi "işlendi" olarak işaretler; böylece aynı link arka arkaya tekrar sorulmaz.
  static void markAsHandled(String url) {
    _lastHandledUrl = url;
  }

  /// Testler veya sıfırlama için son işlenen linki temizler.
  static void resetLastHandled() {
    _lastHandledUrl = null;
  }
}
