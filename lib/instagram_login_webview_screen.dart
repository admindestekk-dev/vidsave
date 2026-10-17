import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import 'backend_settings.dart';

/// Güvenli InAppWebView aracılığıyla Instagram girişi yapıp
/// çerezleri (CookieManager) yakalayan ve backend'e gönderen sayfa.
class InstagramLoginWebViewScreen extends StatefulWidget {
  const InstagramLoginWebViewScreen({super.key, required this.store});

  final BackendSettingsStore store;

  @override
  State<InstagramLoginWebViewScreen> createState() =>
      _InstagramLoginWebViewScreenState();
}

class _InstagramLoginWebViewScreenState
    extends State<InstagramLoginWebViewScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String _statusText = 'Instagram yükleniyor...';

  static const Color accentColor = Color(0xFFFF5436);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Text(
          'Instagram Hesabını Bağla',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Çerezleri Kaydet',
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accentColor,
                    ),
                  )
                : const Icon(Icons.check_circle_rounded, color: accentColor),
            onPressed: _isSaving ? null : _extractAndSaveCookies,
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri('https://www.instagram.com/accounts/login/'),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              userAgent:
                  'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            ),
            onLoadStart: (controller, url) {
              setState(() {
                _isLoading = true;
                _statusText = 'Sayfa yükleniyor...';
              });
            },
            onLoadStop: (controller, url) async {
              setState(() {
                _isLoading = false;
              });
              final urlStr = url?.toString() ?? '';
              // Oturum açıldıktan sonra ana sayfaya veya profile yönlendirildiyse
              if (!urlStr.contains('/accounts/login') &&
                  (urlStr.contains('instagram.com') || urlStr.contains('instagr.am'))) {
                await _checkIfLoggedIn();
              }
            },
          ),
          if (_isLoading)
            LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation<Color>(accentColor),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: const Color(0xFF1E1E1E),
        child: SafeArea(
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusText,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _extractAndSaveCookies,
                icon: const Icon(Icons.sync_rounded, size: 16),
                label: const Text('Bağla', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkIfLoggedIn() async {
    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(
      url: WebUri('https://www.instagram.com/'),
    );
    final hasSession = cookies.any((c) => c.name == 'sessionid' && c.value.isNotEmpty);
    if (hasSession && mounted) {
      setState(() {
        _statusText = 'Oturum algılandı! Çerezler kaydediliyor...';
      });
      await _extractAndSaveCookies();
    }
  }

  Future<void> _extractAndSaveCookies() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _statusText = 'Çerezler okunuyor...';
    });

    try {
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(
        url: WebUri('https://www.instagram.com/'),
      );

      if (cookies.isEmpty) {
        throw Exception('Instagram çerezleri henüz oluşmadı. Lütfen giriş yapın.');
      }

      final cookiePairs = <String>[];
      for (final c in cookies) {
        cookiePairs.add('${c.name}=${c.value}');
      }
      final cookieHeader = cookiePairs.join('; ');

      // Backend API adresini yükle
      final settings = await widget.store.load();
      if (!settings.isConfigured) {
        throw Exception('Backend adresi ayarlanmamış. Lütfen Ayarlar sekmesini kontrol edin.');
      }

      final endpoint = settings.baseUri.resolve('/api/cookies');
      final res = await http.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (settings.apiKey.isNotEmpty) 'X-Api-Key': settings.apiKey,
        },
        body: jsonEncode({
          'platform': 'instagram',
          'cookies': cookieHeader,
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Instagram hesabı başarıyla bağlandı! Gizli profil ve hikayeler indirilebilir.'),
            backgroundColor: Color(0xFF20B8C5),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        throw Exception('Backend çerezleri kaydedemedi: HTTP ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _statusText = 'Hata: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bağlantı hatası: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
