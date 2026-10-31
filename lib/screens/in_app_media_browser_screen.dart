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
    this.onCloseTab,
  });

  final String initialUrl;
  final VoidCallback? onCloseTab;

  @override
  State<InAppMediaBrowserScreen> createState() =>
      _InAppMediaBrowserScreenState();
}

class _InAppMediaBrowserScreenState extends State<InAppMediaBrowserScreen> {
  WebViewController? _controller;
  final TextEditingController _urlBarController = TextEditingController();

  bool _isLoading = true;
  String? _detectedVideoUrl;
  bool _isVideoActive = false;
  String _pageTitle = '';
  static const Color _neonOrange = Color(0xFFFF5436);

  void _onVideoDetected(String url) {
    if (!mounted) return;
    final clean = url.trim();
    if (clean.isEmpty) return;

    setState(() {
      _detectedVideoUrl = clean;
      _isVideoActive = true;
    });
  }

  // Sayfadaki video ve akış linklerini MutationObserver ve dinamik DOM tarayıcısı ile
  // lazy load / infinite scroll durumlarında bile anında havada yakalayan agresif JavaScript avcısı
  static const String _videoDetectionScript = '''
    (function() {
      if (window.__vidsaveObserverInstalled) return;
      window.__vidsaveObserverInstalled = true;

      function notifyVideo(url) {
        if (!url || typeof url !== 'string') return;
        var clean = url.trim();
        if ((clean.startsWith('http://') || clean.startsWith('https://')) && !clean.startsWith('blob:')) {
          if (window.VidSaveDetector && window.VidSaveDetector.postMessage) {
            window.VidSaveDetector.postMessage(clean);
          }
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('VidSaveVideoYakalandi', clean);
          }
        }
      }

      function scanElements() {
        try {
          var vids = document.querySelectorAll('video');
          for (var i = 0; i < vids.length; i++) {
            var v = vids[i];
            var src = v.currentSrc || v.src || v.getAttribute('src');
            if (src) { notifyVideo(src); }
            var sources = v.querySelectorAll('source');
            for (var j = 0; j < sources.length; j++) {
              var sSrc = sources[j].src || sources[j].getAttribute('src');
              if (sSrc) { notifyVideo(sSrc); }
            }
          }
          var allSources = document.querySelectorAll('source[src*=".mp4"], source[src*="googlevideo"], source[src*="cdn"]');
          for (var k = 0; k < allSources.length; k++) {
            var url = allSources[k].src || allSources[k].getAttribute('src');
            if (url) { notifyVideo(url); }
          }
        } catch(e) {}
      }

      scanElements();

      // MutationObserver: Instagram, TikTok, Shorts gibi lazy-load ve dinamik eklenen videoları havada yakalar
      try {
        var observer = new MutationObserver(function(mutations) {
          for (var i = 0; i < mutations.length; i++) {
            var mut = mutations[i];
            if (mut.addedNodes && mut.addedNodes.length > 0) {
              scanElements();
              break;
            }
          }
        });
        observer.observe(document.body || document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src', 'currentSrc']
        });
      } catch(e) {}

      setInterval(scanElements, 1500);
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _urlBarController.text = widget.initialUrl;

    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF14191F))
        ..addJavaScriptChannel(
          'VidSaveDetector',
          onMessageReceived: (JavaScriptMessage msg) {
            final url = msg.message.trim();
            if (url.isNotEmpty && url.startsWith('http')) {
              _onVideoDetected(url);
            }
          },
        )
        ..addJavaScriptChannel(
          'VidSaveVideoYakalandi',
          onMessageReceived: (JavaScriptMessage msg) {
            final url = msg.message.trim();
            if (url.isNotEmpty && url.startsWith('http')) {
              _onVideoDetected(url);
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
                  _isVideoActive = false;
                });
              }
            },
            onPageFinished: (String url) async {
              if (mounted) {
                setState(() => _isLoading = false);
              }
              final controller = _controller;
              if (controller != null) {
                final title = await controller.getTitle();
                if (mounted && title != null) {
                  setState(() => _pageTitle = title);
                }
                // Sayfa yüklemesi tamamlandığında agresif MutationObserver JavaScript avcısını enjekte et
                await controller.runJavaScript(_videoDetectionScript);
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.initialUrl));
    } catch (e) {
      debugPrint('WebViewController init skipped: $e');
    }
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
    _controller?.loadRequest(Uri.parse(raw));
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
            final controller = _controller;
            final canGoBack = controller != null && await controller.canGoBack();
            if (canGoBack) {
              await controller.goBack();
            } else if (mounted) {
              if (navigator.canPop()) {
                navigator.pop();
              } else if (widget.onCloseTab != null) {
                widget.onCloseTab!();
              }
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
            onPressed: () => _controller?.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null)
            WebViewWidget(controller: _controller!)
          else
            const Center(
              child: Text(
                'Tarayıcı',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          if (_isLoading && _controller != null)
            const LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(_neonOrange),
            ),
        ],
      ),
      // Sayfa açıldığı andan itibaren görünen VidSave İndir butonu:
      // Henüz bir video açılmamışsa (video algılanmamışsa) pasif görünür ve tıklanamaz.
      // Herhangi bir video açıldığında aktifleşir, parlar ve indirmeye hazır olur.
      floatingActionButton: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: _isVideoActive
              ? [
                  BoxShadow(
                    color: _neonOrange.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: FloatingActionButton.extended(
          onPressed: _isVideoActive ? _triggerDownload : null,
          elevation: _isVideoActive ? 6 : 0,
          highlightElevation: _isVideoActive ? 10 : 0,
          backgroundColor: _isVideoActive
              ? _neonOrange
              : const Color(0xFF2C323B).withValues(alpha: 0.85),
          foregroundColor: _isVideoActive ? Colors.white : Colors.white38,
          icon: Icon(
            _isVideoActive ? Icons.bolt_rounded : Icons.videocam_outlined,
            color: _isVideoActive ? Colors.white : Colors.white38,
            size: 22,
          ),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'VidSave İndir',
                style: TextStyle(
                  color: _isVideoActive ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
              if (!_isVideoActive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Video Bekleniyor',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
