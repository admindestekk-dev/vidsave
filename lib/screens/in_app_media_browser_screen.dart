import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;

import '../quick_download_dialog.dart';
import '../services/unified_download_engine.dart';

const List<String> _adBlockUrlFilters = [
  r'.*googleads.*',
  r'.*doubleclick.*',
  r'.*adservice.*',
  r'.*popads.*',
  r'.*adsterra.*',
  r'.*googlesyndication.*',
  r'.*googleadservices.*',
  r'.*googletagmanager.*',
  r'.*google-analytics.*',
  r'.*adnxs.*',
  r'.*adsrvr.*',
  r'.*adform.*',
  r'.*adroll.*',
  r'.*taboola.*',
  r'.*outbrain.*',
  r'.*criteo.*',
  r'.*scorecardresearch.*',
  r'.*doubleverify.*',
  r'.*propellerads.*',
];

final List<inapp.ContentBlocker> initialContentBlockers =
    List<inapp.ContentBlocker>.unmodifiable(
      _adBlockUrlFilters.map(
        (urlFilter) => inapp.ContentBlocker(
          trigger: inapp.ContentBlockerTrigger(
            urlFilter: urlFilter,
            urlFilterIsCaseSensitive: false,
          ),
          action: inapp.ContentBlockerAction(
            type: inapp.ContentBlockerActionType.BLOCK,
          ),
        ),
      ),
    );

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
  final isHttp =
      cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://');

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
    @visibleForTesting this.webViewBuilder,
  });

  final String initialUrl;
  final VoidCallback? onCloseTab;
  final WidgetBuilder? webViewBuilder;

  @override
  State<InAppMediaBrowserScreen> createState() =>
      InAppMediaBrowserScreenState();
}

class InAppMediaBrowserScreenState extends State<InAppMediaBrowserScreen> {
  inapp.InAppWebViewController? _controller;
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
        if (data['type'] == 'video_reset') {
          setState(() {
            _detectedVideoUrl = null;
            _isVideoActive = false;
          });
          return;
        }

        final mediaUrl = data['mediaUrl'] as String?;
        final pageUrl = data['pageUrl'] as String?;
        final title = data['title'] as String?;

        final validMedia =
            (mediaUrl != null &&
                mediaUrl.isNotEmpty &&
                mediaUrl.startsWith('http') &&
                !mediaUrl.startsWith('blob:'))
            ? mediaUrl
            : null;

        final validPage =
            (pageUrl != null &&
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

      var selectedVideo = null;
      var lastReportedMedia = null;
      var lastReportedPage = null;
      var checkScheduled = false;

      function postToFlutter(payload) {
        try {
          var jsonStr = typeof payload === 'string' ? payload : JSON.stringify(payload);
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            return window.flutter_inappwebview.callHandler('VidSaveVideoYakalandi', jsonStr);
          }
          if (window.VidSaveDetector && window.VidSaveDetector.postMessage) {
            window.VidSaveDetector.postMessage(jsonStr);
          }
        } catch(e) {}
        return Promise.resolve();
      }

      function resetReportedVideo() {
        var hadSelection = selectedVideo !== null;
        selectedVideo = null;
        lastReportedMedia = null;
        lastReportedPage = null;
        if (hadSelection) {
          return postToFlutter({ type: 'video_reset' });
        }
        return Promise.resolve();
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
        var selectionChanged = selectedVideo !== videoEl;
        var linkChanged = mediaUrl !== lastReportedMedia ||
            pageUrl !== lastReportedPage;
        var hadPreviousSelection = selectedVideo !== null;

        if (!selectionChanged && !linkChanged) {
          return;
        }

        selectedVideo = videoEl;
        lastReportedMedia = mediaUrl;
        lastReportedPage = pageUrl;

        var report = function() {
          if (selectedVideo !== videoEl ||
              lastReportedMedia !== mediaUrl ||
              lastReportedPage !== pageUrl) {
            return;
          }
          postToFlutter({
            type: 'video_active',
            mediaUrl: mediaUrl || '',
            pageUrl: pageUrl,
            title: title,
            isPlaying: !!isPlaying
          });
        };
        if ((selectionChanged || linkChanged) && hadPreviousSelection) {
          postToFlutter({ type: 'video_reset' }).then(report);
          return;
        }
        report();
      }

      function attachVideoListeners(videoEl) {
        if (!videoEl || videoEl.__vidsaveAttached) return;
        videoEl.__vidsaveAttached = true;

        videoEl.addEventListener('play', scheduleVideoCheck, { passive: true });
        videoEl.addEventListener('playing', scheduleVideoCheck, { passive: true });

        videoEl.addEventListener('timeupdate', function() {
          if (!videoEl.paused && !videoEl.ended) {
            scheduleVideoCheck();
          }
        }, { passive: true });

        videoEl.addEventListener('pause', scheduleVideoCheck, { passive: true });
        videoEl.addEventListener('ended', scheduleVideoCheck, { passive: true });
        videoEl.addEventListener('loadedmetadata', scheduleVideoCheck, { passive: true });
      }

      function getVisibleVideo(videoEl, viewportWidth, viewportHeight) {
        var rect = videoEl.getBoundingClientRect();
        var visibleWidth = Math.max(
          0,
          Math.min(rect.right, viewportWidth) - Math.max(rect.left, 0)
        );
        var visibleHeight = Math.max(
          0,
          Math.min(rect.bottom, viewportHeight) - Math.max(rect.top, 0)
        );
        var visibleArea = visibleWidth * visibleHeight;
        if (visibleWidth < 80 || visibleHeight < 80 || visibleArea < 10000) {
          return null;
        }

        var style = window.getComputedStyle(videoEl);
        if (style.display === 'none' ||
            style.visibility === 'hidden' ||
            Number(style.opacity) === 0) {
          return null;
        }
        return { video: videoEl, area: visibleArea };
      }

      function checkPlayingOrVisibleVideo() {
        var vids = document.querySelectorAll('video');
        var viewportWidth = window.innerWidth ||
            document.documentElement.clientWidth || 800;
        var viewportHeight = window.innerHeight ||
            document.documentElement.clientHeight || 800;
        var bestPlaying = null;
        var bestVisible = null;

        for (var i = 0; i < vids.length; i++) {
          var video = vids[i];
          attachVideoListeners(video);
          var visible = getVisibleVideo(video, viewportWidth, viewportHeight);
          if (!visible) continue;

          if (!bestVisible || visible.area > bestVisible.area) {
            bestVisible = visible;
          }
          if (!video.paused && !video.ended &&
              (!bestPlaying || visible.area > bestPlaying.area)) {
            bestPlaying = visible;
          }
        }

        var active = bestPlaying || bestVisible;
        if (active) {
          reportActiveVideo(active.video, !active.video.paused && !active.video.ended);
        } else {
          resetReportedVideo();
        }
      }

      function scheduleVideoCheck() {
        if (checkScheduled) return;
        checkScheduled = true;
        window.requestAnimationFrame(function() {
          checkScheduled = false;
          checkPlayingOrVisibleVideo();
        });
      }

      window.__vidsaveCheckActiveVideo = checkPlayingOrVisibleVideo;

      // İlk kontrol
      checkPlayingOrVisibleVideo();

      // Kullanıcı sayfayı kaydırdıkça izlenen videoyu anlık güncelle
      window.addEventListener('scroll', scheduleVideoCheck, { passive: true });
      window.addEventListener('resize', scheduleVideoCheck, { passive: true });

      // SPA (Single Page Application) geçişlerinde URL değiştiğinde hemen yeni videoyu tespit et
      function onRouteChanged() {
        resetReportedVideo();
        setTimeout(function() {
          scheduleVideoCheck();
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
            scheduleVideoCheck();
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
      setInterval(scheduleVideoCheck, 1200);
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _urlBarController.text = widget.initialUrl;
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
    _controller?.loadUrl(urlRequest: inapp.URLRequest(url: inapp.WebUri(raw)));
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

  Widget _buildWebView() {
    final testBuilder = widget.webViewBuilder;
    if (testBuilder != null) return testBuilder(context);

    if (inapp.InAppWebViewPlatform.instance == null) {
      return const Center(
        child: Text(
          'Dahili tarayıcı bu platformda kullanılamıyor.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final supportsContentBlockers =
        !kIsWeb &&
        {
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform);

    return inapp.InAppWebView(
      initialUrlRequest: inapp.URLRequest(url: inapp.WebUri(widget.initialUrl)),
      initialSettings: inapp.InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: true,
        useShouldOverrideUrlLoading: true,
        contentBlockers: supportsContentBlockers
            ? initialContentBlockers
            : const [],
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        for (final handlerName in [
          'VidSaveDetector',
          'VidSaveVideoYakalandi',
        ]) {
          controller.addJavaScriptHandler(
            handlerName: handlerName,
            callback: (args) {
              if (args.isNotEmpty && args.first is String) {
                _handleIncomingDetectorMessage(args.first as String);
              }
              return null;
            },
          );
        }
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        if (shouldOverrideUrlLoading(url) == NavigationActionPolicy.CANCEL) {
          return inapp.NavigationActionPolicy.CANCEL;
        }
        return inapp.NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (controller, createWindowAction) async {
        debugPrint('[VidSave Koruma] Açılır pencere engellendi.');
        return false;
      },
      onLoadStart: (controller, url) {
        if (!mounted) return;
        setState(() {
          _isLoading = true;
          _urlBarController.text = url?.toString() ?? '';
          _detectedVideoUrl = null;
          _isVideoActive = false;
        });
      },
      onLoadStop: (controller, url) async {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        final title = await controller.getTitle();
        if (mounted && title != null) {
          setState(() => _pageTitle = title);
        }
        await controller.evaluateJavascript(source: _videoDetectionScript);
      },
      onReceivedError: (controller, request, error) {
        debugPrint(
          '[VidSave Tarayıcı] WebResourceError (${error.type}): ${error.description}',
        );
      },
    );
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
            _buildWebView(),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
