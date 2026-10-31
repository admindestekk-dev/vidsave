import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../quick_download_dialog.dart';
import '../services/unified_download_engine.dart';

/// Web tarayıcısı yönlendirme politikası (Navigation Policy)
enum NavigationActionPolicy {
  /// İsteği iptal eder, tarayıcının harici şemaya geçmesini engeller.
  CANCEL,

  /// İsteğe izin verir, sayfanın normal akışında yüklenmesini sağlar.
  ALLOW,
}

/// Harici şemaları (fb://, whatsapp://, intent:// vb.) havada yakalayan ve
/// net::ERR_UNKNOWN_URL_SCHEME beyaz ekran hatasını önleyen güvenlik filtresi.
NavigationActionPolicy shouldOverrideUrlLoading(String url) {
  final cleanUrl = url.trim().toLowerCase();
  final isHttp = cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://');

  if (!isHttp) {
    debugPrint('[VidSave Koruma] Harici uygulama linki engellendi: $url');
    return NavigationActionPolicy.CANCEL;
  }

  return NavigationActionPolicy.ALLOW;
}

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
      InAppMediaBrowserScreenState();
}

class InAppMediaBrowserScreenState extends State<InAppMediaBrowserScreen> {
  WebViewController? _controller;
  final TextEditingController _urlBarController = TextEditingController();

  bool _isLoading = true;
  String? _detectedVideoUrl;
  bool _isVideoActive = false;
  String _pageTitle = '';
  static const Color _neonOrange = Color(0xFFFF5436);

  @visibleForTesting
  String? get detectedVideoUrl => _detectedVideoUrl;

  @visibleForTesting
  bool get isVideoActive => _isVideoActive;

  @visibleForTesting
  String get pageTitle => _pageTitle;

  @visibleForTesting
  void handleIncomingDetectorMessage(String message) =>
      _handleIncomingDetectorMessage(message);

  void _onVideoDetected(String url) {
    if (!mounted) return;
    final clean = url.trim();
    if (clean.isEmpty) return;

    setState(() {
      _detectedVideoUrl = clean;
      _isVideoActive = true;
    });
  }

  void _handleIncomingDetectorMessage(String rawMsg) {
    if (!mounted) return;
    final message = rawMsg.trim();
    if (message.isEmpty) return;

    try {
      if (message.startsWith('{') && message.endsWith('}')) {
        final data = jsonDecode(message) as Map<String, dynamic>;
        final mediaUrl = data['mediaUrl'] as String?;
        final pageUrl = data['pageUrl'] as String?;
        final title = data['title'] as String?;

        final validMedia = (mediaUrl != null &&
                mediaUrl.isNotEmpty &&
                mediaUrl.startsWith('http') &&
                !mediaUrl.startsWith('blob:'))
            ? mediaUrl
            : null;

        final validPage = (pageUrl != null &&
                pageUrl.isNotEmpty &&
                pageUrl.startsWith('http'))
            ? pageUrl
            : null;

        final target = validMedia ?? validPage;
        if (target != null) {
          setState(() {
            _detectedVideoUrl = target;
            _isVideoActive = true;
            if (title != null && title.trim().isNotEmpty) {
              _pageTitle = title.trim();
            }
            if (validPage != null && validPage.isNotEmpty) {
              _urlBarController.text = validPage;
            }
          });
          return;
        }
      }
    } catch (_) {
      // Düz URL formatı desteği
    }

    _onVideoDetected(message);
  }

  // Sayfada o an aktif olarak izlenen/oynatılan videoyu anlık tespit eden ve
  // kullanıcı video değiştirdiğinde (Instagram Reels, TikTok, Facebook Watch, YouTube)
  // buton hedefini otomatik güncelleyen akıllı JavaScript avcısı
  static const String _videoDetectionScript = '''
    (function() {
      if (window.__vidsaveObserverInstalled) {
        if (window.__vidsaveCheckActiveVideo) {
          window.__vidsaveCheckActiveVideo();
        }
        return;
      }
      window.__vidsaveObserverInstalled = true;

      var lastReportedMedia = null;
      var lastReportedPage = null;

      function postToFlutter(payload) {
        try {
          var jsonStr = typeof payload === 'string' ? payload : JSON.stringify(payload);
          if (window.VidSaveDetector && window.VidSaveDetector.postMessage) {
            window.VidSaveDetector.postMessage(jsonStr);
          }
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('VidSaveVideoYakalandi', jsonStr);
          }
        } catch(e) {}
      }

      function extractMediaSrc(videoEl) {
        if (!videoEl) return null;
        var src = videoEl.currentSrc || videoEl.src || videoEl.getAttribute('src');
        if (src && typeof src === 'string') {
          var s = src.trim();
          if ((s.startsWith('http://') || s.startsWith('https://')) && !s.startsWith('blob:')) {
            return s;
          }
        }
        var sources = videoEl.querySelectorAll('source');
        for (var i = 0; i < sources.length; i++) {
          var sSrc = sources[i].src || sources[i].getAttribute('src');
          if (sSrc && typeof sSrc === 'string') {
            var clean = sSrc.trim();
            if ((clean.startsWith('http://') || clean.startsWith('https://')) && !clean.startsWith('blob:')) {
              return clean;
            }
          }
        }
        return null;
      }

      function findPostUrl(videoEl) {
        if (!videoEl) return window.location.href;
        try {
          var anchor = videoEl.closest('a[href*="/reel/"], a[href*="/p/"], a[href*="/watch"], a[href*="/video/"], a[href*="/shorts/"]');
          if (anchor && anchor.href) {
            return anchor.href;
          }
        } catch(e) {}
        return window.location.href;
      }

      function reportActiveVideo(videoEl, isPlaying) {
        if (!videoEl) return;
        var mediaUrl = extractMediaSrc(videoEl);
        var pageUrl = findPostUrl(videoEl);
        var title = document.title || '';

        // Aynı video ve aynı sayfa URL'si ise gereksiz tekrar gönderme
        if (mediaUrl === lastReportedMedia && pageUrl === lastReportedPage) {
          return;
        }

        lastReportedMedia = mediaUrl;
        lastReportedPage = pageUrl;

        postToFlutter({
          type: 'video_active',
          mediaUrl: mediaUrl || '',
          pageUrl: pageUrl,
          title: title,
          isPlaying: !!isPlaying
        });
      }

      function attachVideoListeners(videoEl) {
        if (!videoEl || videoEl.__vidsaveAttached) return;
        videoEl.__vidsaveAttached = true;

        // Video oynatılmaya başladığı an 'aktif izlenen video' olarak bildir
        videoEl.addEventListener('play', function() {
          reportActiveVideo(videoEl, true);
        }, { passive: true });

        videoEl.addEventListener('playing', function() {
          reportActiveVideo(videoEl, true);
        }, { passive: true });

        videoEl.addEventListener('timeupdate', function() {
          if (!videoEl.paused && !videoEl.ended) {
            var currentMedia = extractMediaSrc(videoEl);
            if (currentMedia && currentMedia !== lastReportedMedia) {
              reportActiveVideo(videoEl, true);
            }
          }
        }, { passive: true });
      }

      // O an oynatılan (playing) veya kullanıcının ekranında en görünür olan videoyu tespit et
      function checkPlayingOrVisibleVideo() {
        var vids = document.querySelectorAll('video');
        if (!vids || vids.length === 0) return;

        // 1. Önce aktif olarak çalan (paused == false) videoyu ara
        var playingVid = null;
        for (var i = 0; i < vids.length; i++) {
          attachVideoListeners(vids[i]);
          if (!vids[i].paused && !vids[i].ended && vids[i].currentTime > 0) {
            playingVid = vids[i];
            break;
          }
        }

        if (playingVid) {
          reportActiveVideo(playingVid, true);
          return;
        }

        // 2. Çalan yoksa ekranın ortasındaki (viewport) en görünür videoyu bul
        var bestVideo = null;
        var maxVisibility = 0;
        var windowHeight = window.innerHeight || document.documentElement.clientHeight || 800;

        for (var j = 0; j < vids.length; j++) {
          var v = vids[j];
          attachVideoListeners(v);
          var rect = v.getBoundingClientRect();
          var visibleHeight = Math.max(0, Math.min(rect.bottom, windowHeight) - Math.max(rect.top, 0));
          if (visibleHeight > maxVisibility) {
            maxVisibility = visibleHeight;
            bestVideo = v;
          }
        }

        if (bestVideo && maxVisibility > 120) {
          reportActiveVideo(bestVideo, false);
        } else if (vids.length > 0 && !lastReportedMedia) {
          reportActiveVideo(vids[0], false);
        }
      }

      window.__vidsaveCheckActiveVideo = checkPlayingOrVisibleVideo;

      // İlk kontrol
      checkPlayingOrVisibleVideo();

      // Kullanıcı sayfayı kaydırdıkça izlenen videoyu anlık güncelle
      window.addEventListener('scroll', checkPlayingOrVisibleVideo, { passive: true });

      // SPA (Single Page Application) geçişlerinde URL değiştiğinde hemen yeni videoyu tespit et
      function onRouteChanged() {
        setTimeout(function() {
          lastReportedMedia = null;
          lastReportedPage = null;
          checkPlayingOrVisibleVideo();
        }, 350);
      }

      var origPushState = history.pushState;
      if (origPushState) {
        history.pushState = function() {
          var res = origPushState.apply(this, arguments);
          onRouteChanged();
          return res;
        };
      }

      var origReplaceState = history.replaceState;
      if (origReplaceState) {
        history.replaceState = function() {
          var res = origReplaceState.apply(this, arguments);
          onRouteChanged();
          return res;
        };
      }

      window.addEventListener('popstate', onRouteChanged, { passive: true });

      // MutationObserver: Dinamik eklenen (lazy-load) videoları yakala ve dinleyicileri bağla
      try {
        var observer = new MutationObserver(function(mutations) {
          var hasNewNodes = false;
          for (var i = 0; i < mutations.length; i++) {
            if (mutations[i].addedNodes && mutations[i].addedNodes.length > 0) {
              hasNewNodes = true;
              break;
            }
          }
          if (hasNewNodes) {
            checkPlayingOrVisibleVideo();
          }
        });
        observer.observe(document.body || document.documentElement, {
          childList: true,
          subtree: true
        });
      } catch(e) {}

      // Harici şemaları (fb://, intent:// vb.) DOM tıklamalarında da havada yakala ve sustur
      try {
        document.addEventListener('click', function(e) {
          var target = e.target;
          while (target && target.tagName !== 'A') {
            target = target.parentElement;
          }
          if (target && target.href) {
            var href = target.href.toLowerCase();
            if (!href.startsWith('http://') && !href.startsWith('https://') && !href.startsWith('javascript:')) {
              e.preventDefault();
              e.stopPropagation();
              console.log('[VidSave Koruma] Harici uygulama linki engellendi: ' + target.href);
            }
          }
        }, true);
      } catch(e) {}

      // Periyodik kontrol
      setInterval(checkPlayingOrVisibleVideo, 1200);
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
            _handleIncomingDetectorMessage(msg.message);
          },
        )
        ..addJavaScriptChannel(
          'VidSaveVideoYakalandi',
          onMessageReceived: (JavaScriptMessage msg) {
            _handleIncomingDetectorMessage(msg.message);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              final policy = shouldOverrideUrlLoading(request.url);
              if (policy == NavigationActionPolicy.CANCEL) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint(
                '[VidSave Tarayıcı] WebResourceError (${error.errorCode}): ${error.description}',
              );
            },
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

  /// Geri tuşu aksiyonunu yönetir.
  /// Tarayıcı geçmişinde geri gidilebiliyorsa bir önceki sayfaya döner ve `true` döner.
  /// Sayfa geçmişi bittiğinde modal/sekme kapanır ve `true` döner.
  Future<bool> handleBackAction() async {
    final controller = _controller;
    final canGoBack = controller != null && await controller.canGoBack();
    if (canGoBack) {
      await controller.goBack();
      return true;
    }
    if (!mounted) return false;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return true;
    } else if (widget.onCloseTab != null) {
      widget.onCloseTab!();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await handleBackAction();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF14191F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E2630),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: handleBackAction,
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
    ),
  );
}
}
