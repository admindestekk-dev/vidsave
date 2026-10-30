import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../quick_download_dialog.dart';
import '../services/unified_download_engine.dart';

/// VidSave Dahili Sosyal Medya Tarayıcısı (In-App Media Browser)
///
/// Özellikler:
/// - Kullanıcı Instagram, TikTok, YouTube vb. gezinirken arka planda çalışan
///   JavaScript Injection ile DOM'daki `<video src="...">`, `source` ve medya linklerini anlık yakalar.
/// - Video yakalandığında sağ altta parlayan neon turuncu 'VidSave İndir' aksiyon butonu belirir.
/// - Tıklandığında doğrudan uygulamanın Hızlı İndirme diyaloğunu açar.
class InAppMediaBrowserScreen extends StatefulWidget {
  const InAppMediaBrowserScreen({
    super.key,
    this.initialUrl = 'https://www.google.com',
  });

  final String initialUrl;

  @override
  State<InAppMediaBrowserScreen> createState() =>
      _InAppMediaBrowserScreenState();
}

class _InAppMediaBrowserScreenState extends State<InAppMediaBrowserScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlBarController = TextEditingController();

  bool _isLoading = true;
  String? _detectedVideoUrl;
  String _pageTitle = '';
  static const Color _neonOrange = Color(0xFFFF5436);

  // Sayfadaki video ve akış linklerini bulan agresif JavaScript enjeksiyon kodu
  static const String _videoDetectionScript = '''
    (function() {
      function detectMedia() {
        var videos = document.getElementsByTagName('video');
        for (var i = 0; i < videos.length; i++) {
          var src = videos[i].src || videos[i].currentSrc;
          if (src && src.startsWith('http') && !src.startsWith('blob:')) {
            window.VidSaveDetector.postMessage(src);
            return;
          }
          var sources = videos[i].getElementsByTagName('source');
          for (var j = 0; j < sources.length; j++) {
            var s = sources[j].src;
            if (s && s.startsWith('http')) {
              window.VidSaveDetector.postMessage(s);
              return;
            }
          }
        }
      }
      detectMedia();
      setInterval(detectMedia, 2000);
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _urlBarController.text = widget.initialUrl;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF14191F))
      ..addJavaScriptChannel(
        'VidSaveDetector',
        onMessageReceived: (JavaScriptMessage msg) {
          final url = msg.message.trim();
          if (url.isNotEmpty && url.startsWith('http') && mounted) {
            setState(() {
              _detectedVideoUrl = url;
            });
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _urlBarController.text = url;
                _detectedVideoUrl = null;
              });
            }
          },
          onPageFinished: (String url) async {
            if (mounted) {
              setState(() => _isLoading = false);
            }
            final title = await _controller.getTitle();
            if (mounted && title != null) {
              setState(() => _pageTitle = title);
            }
            // Sayfa yüklendiğinde JavaScript Enjeksiyonunu çalıştır
            await _controller.runJavaScript(_videoDetectionScript);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  void dispose() {
    _urlBarController.dispose();
    super.dispose();
  }

  void _loadEnteredUrl() {
    var raw = _urlBarController.text.trim();
    if (raw.isEmpty) return;

    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      if (raw.contains('.') && !raw.contains(' ')) {
        raw = 'https://$raw';
      } else {
        raw = 'https://www.google.com/search?q=${Uri.encodeComponent(raw)}';
      }
    }
    _controller.loadRequest(Uri.parse(raw));
  }

  void _triggerDownload() {
    final targetUrl = _detectedVideoUrl ?? _urlBarController.text.trim();
    if (targetUrl.isEmpty) return;

    QuickDownloadDialog.show(
      context: context,
      videoTitle: _pageTitle.isNotEmpty ? _pageTitle : targetUrl,
      onDownloadVideo: () {
        UnifiedDownloadEngine.instance.download(
          rawUrl: targetUrl,
          type: 'video',
          preferredTitle: _pageTitle,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video indirme kuyruğuna alındı! 🚀'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onDownloadMp3: ({startTime, endTime, audioEffect}) {
        UnifiedDownloadEngine.instance.download(
          rawUrl: targetUrl,
          type: 'mp3',
          preferredTitle: _pageTitle,
          startTime: startTime,
          endTime: endTime,
          audioEffect: audioEffect,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('MP3 indirme kuyruğuna alındı! 🎵'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14191F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2630),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () async {
            final navigator = Navigator.of(context);
            final canGoBack = await _controller.canGoBack();
            if (canGoBack) {
              await _controller.goBack();
            } else if (mounted) {
              navigator.pop();
            }
          },
        ),
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: TextField(
            controller: _urlBarController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Arayın veya link girin...',
              hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: Colors.white38,
                size: 18,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _loadEnteredUrl(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(_neonOrange),
            ),
        ],
      ),
      // Video Yakalandığında Ekranda Parlayan Turuncu Aksiyon Butonu
      floatingActionButton: _detectedVideoUrl != null
          ? FloatingActionButton.extended(
              onPressed: _triggerDownload,
              backgroundColor: _neonOrange,
              icon: const Icon(Icons.bolt_rounded, color: Colors.white),
              label: const Text(
                'VidSave İndir',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            )
          : null,
    );
  }
}
