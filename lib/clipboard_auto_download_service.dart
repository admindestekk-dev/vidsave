import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pano (Clipboard) üzerindeki metinleri kontrol eden ve desteklenen
/// video/müzik bağlantılarını (özellikle Instagram ve TikTok) tespit eden yardımcı servis.
class ClipboardAutoDownloadService {
  ClipboardAutoDownloadService._();

  static const _lastHandledUrlKey = 'clipboard_auto_download_last_handled_url';
  static String? _lastHandledUrl;

  /// Desteklenen bağlantı desenleri (FB, IG, TT, YT, VM, X, DM vb.).
  static final List<RegExp> _supportedUrlPatterns = [
    RegExp(r'https?://(?:www\.)?instagram\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.)?instagr\.am/[^\s]+', caseSensitive: false),
    RegExp(
      r'https?://(?:www\.|vm\.|vt\.)?tiktok\.com/[^\s]+',
      caseSensitive: false,
    ),
    RegExp(r'https?://(?:www\.)?douyin\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.)?youtube\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://youtu\.be/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.)?facebook\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://fb\.watch/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.)?fb\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.)?twitter\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.)?x\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.)?vimeo\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://(?:www\.)?dailymotion\.com/[^\s]+', caseSensitive: false),
    RegExp(r'https?://dai\.ly/[^\s]+', caseSensitive: false),
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
    String? text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    } catch (_) {
      // Pano erişim kısıtlaması vb. durumlarda sessizce geç
      return null;
    }

    final url = extractUrl(text);
    if (url == null || url == _lastHandledUrl) return null;

    final preferences = await SharedPreferences.getInstance();
    if (url == _lastHandledUrl) return null;
    final fingerprint = _fingerprint(url);
    if (fingerprint == preferences.getString(_lastHandledUrlKey)) {
      _lastHandledUrl = url;
      return null;
    }

    _lastHandledUrl = url;
    try {
      if (!await preferences.setString(_lastHandledUrlKey, fingerprint)) {
        throw StateError('Algılanan bağlantı durumu kaydedilemedi.');
      }
    } catch (_) {
      if (_lastHandledUrl == url) _lastHandledUrl = null;
      rethrow;
    }
    return url;
  }

  static String _fingerprint(String url) =>
      sha256.convert(utf8.encode(url)).toString();

  /// Testlerde uygulama belleğinin yeniden başlatılmasını taklit etmek için kullanılır.
  static void resetLastHandled() {
    _lastHandledUrl = null;
  }
}
