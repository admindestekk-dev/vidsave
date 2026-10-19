import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:photo_manager/photo_manager.dart';

import 'app_localizations.dart';
import 'auth_service.dart';
import 'backend_media_resolver.dart';
import 'backend_settings.dart';
import 'bulk_download_screen.dart';
import 'clipboard_auto_download_service.dart';
import 'download_item_model.dart';
import 'download_notification_service.dart';
import 'download_platforms.dart';
import 'downloads_screen.dart';
import 'media_downloader.dart';
import 'media_library.dart';
import 'more_screen.dart';
import 'music_player.dart';
import 'quick_download_dialog.dart';
import 'storage_service.dart';
import 'theme_service.dart';
import 'locale_service.dart';
import 'video_player_screen.dart';
import 'auth_gate.dart';
import 'welcome_screen.dart';
import 'home_screen.dart';
import 'admob_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(AdmobService.instance.initialize());
  unawaited(DownloadNotificationService.instance.initialize());
  unawaited(StorageService.getItems());
  unawaited(ThemeService.initialize());
  unawaited(LocaleService.initialize());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.authService});

  final AuthService? authService;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return ValueListenableBuilder<Locale?>(
          valueListenable: LocaleService.localeNotifier,
          builder: (context, currentLocale, _) {
            return MaterialApp(
              title: 'VidSave',
              debugShowCheckedModeBanner: false,
              themeMode: currentThemeMode,
              theme: ThemeService.lightTheme,
              darkTheme: ThemeService.darkTheme,
              locale: currentLocale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              localeResolutionCallback: (deviceLocale, supportedLocales) {
                if (currentLocale != null) return currentLocale;
                if (deviceLocale == null) return const Locale('en');
                for (final supported in supportedLocales) {
                  if (supported.languageCode == deviceLocale.languageCode) {
                    return supported;
                  }
                }
                // Fallback olarak İngilizce ('en')
                return const Locale('en');
              },
              home: AuthGate(
                authService: authService,
                authenticatedBuilder: (_) => const VidSaveHomePage(),
                guestBuilder: (_) => const WelcomeScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

class VidSaveHomePage extends StatefulWidget {
  const VidSaveHomePage({
    super.key,
    this.library,
    this.videoPlayerControllerFactory,
    this.mediaResolver,
    this.mediaDownloader,
    this.backendSettingsStore,
    this.musicPlayerFactory,
    this.musicSourceResolver,
    this.showPremiumBanner = true,
  });

  final MediaLibrary? library;
  final VideoPlayerControllerFactory? videoPlayerControllerFactory;
  final AudioPlayerFactory? musicPlayerFactory;
  final AudioSourceResolver? musicSourceResolver;
  final MediaResolver? mediaResolver;
  final MediaDownloader? mediaDownloader;
  final BackendSettingsStore? backendSettingsStore;
  final bool showPremiumBanner;

  @override
  State<VidSaveHomePage> createState() => _VidSaveHomePageState();
}

class _VidSaveHomePageState extends State<VidSaveHomePage>
    with WidgetsBindingObserver {
  int _selectedIndex = 2;
  late final MediaLibrary _library =
      widget.library ?? PhotoManagerMediaLibrary();
  late final BackendSettingsStore _backendSettingsStore =
      widget.backendSettingsStore ?? SecureBackendSettingsStore();
  late final BackendMediaResolver _backendResolver = BackendMediaResolver(
    settingsStore: _backendSettingsStore,
  );
  late final MediaResolver _mediaResolver =
      widget.mediaResolver ?? _backendResolver;
  late final MediaDownloader _mediaDownloader =
      widget.mediaDownloader ?? MediaDownloader();
  final _videoLibraryKey = GlobalKey<_MediaLibraryPageState>();
  final _musicLibraryKey = GlobalKey<_MediaLibraryPageState>();
  PermissionState? _permissionState;
  Object? _permissionError;
  bool _permissionLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestMediaPermission();
    // Uygulama açılışında panoyu ilk kez kontrol et
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkClipboard();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kullanıcı Instagram veya TikTok'tan link kopyalayıp uygulamaya geri döndüğünde (resumed)
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  /// Pano içeriğini kontrol edip desteklenen video linki tespit edilirse QuickDownloadDialog açar.
  Future<void> _checkClipboard() async {
    final url =
        await ClipboardAutoDownloadService.checkClipboardForDownloadUrl();
    if (url != null && mounted) {
      _showClipboardPrompt(url);
    }
  }

  /// Kullanıcıya ekran ortasında açılan 'VidSave Algıladı' Quick Download Dialog penceresi.
  void _showClipboardPrompt(String url) {
    ClipboardAutoDownloadService.markAsHandled(url);

    QuickDownloadDialog.show(
      context: context,
      videoTitle: url,
      onDownloadVideo: () {
        _triggerDirectDownload(url, kind: DownloadKind.video);
      },
      onDownloadMp3: ({startTime, endTime, audioEffect}) {
        _triggerDirectDownload(
          url,
          kind: DownloadKind.audio,
          startTime: startTime,
          endTime: endTime,
          audioEffect: audioEffect,
        );
      },
    );
  }

  /// Onaylanan linki doğrudan indirme akışına (video veya MP3) yönlendirir.
  Future<void> _triggerDirectDownload(
    String url, {
    DownloadKind kind = DownloadKind.video,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    await AdmobService.instance.showRewardedAdOrBypass(
      onRewardEarned: () async {
        if (!mounted) return;
        await _executeDirectDownload(
          url,
          kind: kind,
          startTime: startTime,
          endTime: endTime,
          audioEffect: audioEffect,
        );
      },
    );
  }

  Future<void> _executeDirectDownload(
    String url, {
    DownloadKind kind = DownloadKind.video,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    // İndir sekmesine geçiş yap
    _onDestinationSelected(2);

    final isAudio = kind == DownloadKind.audio;
    final notificationId = DownloadNotificationService.instance
        .allocateNotificationId();
    final notifTitle = isAudio
        ? 'Otomatik MP3 İndirme'
        : 'Otomatik Video İndirme';

    try {
      final parsed = Uri.parse(url);
      final media = await _mediaResolver.resolve(
        parsed,
        kind,
        startTime: startTime,
        endTime: endTime,
        audioEffect: audioEffect,
      );
      if (!mounted) return;

      final displayTitle = media.fileName.trim().isNotEmpty
          ? media.fileName.trim()
          : notifTitle;

      unawaited(
        DownloadNotificationService.instance.showProgress(
          id: notificationId,
          title: displayTitle,
          percent: null,
        ),
      );

      final file = await _mediaDownloader.download(
        media,
        onProgress: (received, total) {
          final percent = downloadPercent(received, total);
          if (percent != null) {
            unawaited(
              DownloadNotificationService.instance.showProgress(
                id: notificationId,
                title: displayTitle,
                percent: percent,
              ),
            );
          }
        },
      );

      final fileName = file.path.split(Platform.pathSeparator).last;
      int fileSize = 0;
      try {
        fileSize = file.lengthSync();
      } catch (_) {}

      unawaited(
        StorageService.addItem(
          DownloadItemModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: fileName,
            type: isAudio ? 'audio' : 'video',
            sizeInBytes: fileSize,
            filePath: file.path,
            downloadedAt: DateTime.now(),
            sourceUrl: url,
          ),
        ),
      );

      unawaited(
        DownloadNotificationService.instance.showCompleted(
          id: notificationId,
          title: displayTitle,
          fileName: fileName,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Başarıyla indirildi: $fileName'),
          backgroundColor: const Color(0xFF20B8C5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      final errorMsg = switch (e) {
        MediaResolverException(:final message) => message,
        MediaDownloadException(:final message) => message,
        _ => 'İndirme tamamlanamadı: $e',
      };

      unawaited(
        DownloadNotificationService.instance.showError(
          id: notificationId,
          title: notifTitle,
          error: errorMsg,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _requestMediaPermission() async {
    setState(() {
      _permissionLoading = true;
      _permissionError = null;
    });

    try {
      final permissionState = await _library.requestPermission();
      if (!mounted) return;
      setState(() {
        _permissionState = permissionState;
        _permissionLoading = false;
      });
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'VidSave media access',
          context: ErrorDescription('while requesting media library access'),
        ),
      );
      if (!mounted) return;
      setState(() {
        _permissionError = error;
        _permissionLoading = false;
      });
    }
  }

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  /// Jumps to the Videolar (0) or Müzik (1) tab, used by the İndirilenler cards.
  void _openLibrary(int index) {
    _onDestinationSelected(index);
  }

  /// The tab the app starts on; the back button returns here before exiting.
  static const int _homeIndex = 2;

  /// Handles the Android hardware/gesture back button.
  ///
  /// Without this the app exits as soon as the user presses back from any tab,
  /// because the home page is the only route on the stack. Instead we walk the
  /// user back to the İndir tab first and only leave the app when they are
  /// already there.
  void _handlePop(bool didPop, Object? result) {
    if (didPop) return;
    if (_selectedIndex != _homeIndex) {
      _onDestinationSelected(_homeIndex);
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == _homeIndex,
      onPopInvokedWithResult: _handlePop,
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const VidSaveBrandTitle(),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _MediaLibraryPage(
            key: _videoLibraryKey,
            title: l10n.text('nav_videos'),
            type: RequestType.video,
            library: _library,
            permissionState: _permissionState,
            permissionLoading: _permissionLoading,
            permissionError: _permissionError,
            onRetryPermission: _requestMediaPermission,
            videoPlayerControllerFactory: widget.videoPlayerControllerFactory,
            musicPlayerFactory: widget.musicPlayerFactory,
            musicSourceResolver: widget.musicSourceResolver,
          ),
          _MediaLibraryPage(
            key: _musicLibraryKey,
            title: l10n.text('nav_music'),
            type: RequestType.audio,
            library: _library,
            permissionState: _permissionState,
            permissionLoading: _permissionLoading,
            permissionError: _permissionError,
            onRetryPermission: _requestMediaPermission,
            videoPlayerControllerFactory: null,
            musicPlayerFactory: widget.musicPlayerFactory,
            musicSourceResolver: widget.musicSourceResolver,
          ),
          _DownloadPage(
            resolver: _mediaResolver,
            downloader: _mediaDownloader,
            showPremiumBanner: widget.showPremiumBanner,
            onDownloaded: (kind) {
              if (kind == DownloadKind.audio) {
                _musicLibraryKey.currentState?.reload();
                _onDestinationSelected(1);
              } else {
                _videoLibraryKey.currentState?.reload();
                _onDestinationSelected(0);
              }
            },
            onOpenLibrary: _openLibrary,
          ),
          MoreScreen(store: _backendSettingsStore, resolver: _backendResolver),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onDestinationSelected,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: const Color(0xFF87949D),
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.video_library_outlined),
            activeIcon: const Icon(Icons.video_library_rounded),
            label: l10n.text('nav_videos'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.headphones_outlined),
            activeIcon: const Icon(Icons.headphones_rounded),
            label: l10n.text('nav_music'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.download_outlined),
            activeIcon: const Icon(Icons.download_rounded),
            label: l10n.text('nav_download'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.grid_view_rounded),
            activeIcon: const Icon(Icons.grid_view_rounded),
            label: l10n.text('nav_more'),
          ),
        ],
      ),
    );
  }
}

/// Mutable per-square download state: a square resolves and downloads its own
/// link without touching the shared İndir button or the other squares.
class _TileDownloadState {
  bool busy = false;
  double? progress;
  String? status;
}

class _DownloadPage extends StatefulWidget {
  const _DownloadPage({
    required this.resolver,
    required this.downloader,
    this.onDownloaded,
    this.onOpenLibrary,
    this.showPremiumBanner = true,
  });

  final MediaResolver resolver;
  final MediaDownloader downloader;
  final ValueChanged<DownloadKind>? onDownloaded;
  final bool showPremiumBanner;

  /// Called with the tab index (0 = Videolar, 1 = Müzik) when a category card
  /// in the İndirilenler section is tapped.
  final ValueChanged<int>? onOpenLibrary;

  @override
  State<_DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<_DownloadPage> {
  DownloadPlatform? _selectedPlatform;
  String? _message;
  bool _messageIsError = false;

  // --- Per-tile (square) downloads -----------------------------------------
  //
  // Every square downloads independently: its own URL, its own progress and its
  // own status line.
  final _tileUrlControllers = <String, TextEditingController>{};
  final _tileFocusNodes = <String, FocusNode>{};
  final _tileState = <String, _TileDownloadState>{};

  @override
  void initState() {
    super.initState();
    for (final platform in kDownloadPlatforms) {
      _tileUrlControllers[platform.label] = TextEditingController();
      _tileFocusNodes[platform.label] = FocusNode();
    }
  }

  @override
  void dispose() {
    for (final controller in _tileUrlControllers.values) {
      controller.dispose();
    }
    for (final node in _tileFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  _TileDownloadState _stateOf(DownloadPlatform platform) =>
      _tileState.putIfAbsent(platform.label, _TileDownloadState.new);

  /// Downloads whatever URL was typed into [platform]'s own field.
  ///
  /// The tile's kind (video/MP3) is taken from [DownloadPlatform.isAudio], so a
  /// square never depends on the Video/Ses selector above.
  Future<void> _downloadFromTile(DownloadPlatform platform) async {
    final controller = _tileUrlControllers[platform.label];
    final text = controller?.text.trim() ?? '';
    if (text.isEmpty) {
      setState(() {
        _stateOf(platform).status = 'Bağlantı girin';
      });
      _tileFocusNodes[platform.label]?.requestFocus();
      return;
    }

    final parsed = Uri.tryParse(text);
    final looksLikeUrl =
        parsed != null &&
        parsed.host.isNotEmpty &&
        (parsed.isScheme('http') || parsed.isScheme('https'));

    // Platform doğrulama kontrolü: Her platform yalnızca kendi linkini indirebilir
    if (looksLikeUrl && !platform.matchesUrl(text)) {
      setState(() {
        _stateOf(platform).status =
            '${platform.label} sadece kendi bağlantılarını destekler!';
      });
      _tileFocusNodes[platform.label]?.requestFocus();
      return;
    }

    final source = looksLikeUrl ? parsed : Uri(path: text);
    final kind = platform.isAudio ? DownloadKind.audio : DownloadKind.video;

    _tileFocusNodes[platform.label]?.unfocus();

    await AdmobService.instance.showRewardedAdOrBypass(
      onRewardEarned: () async {
        if (!mounted) return;
        await _executeDownloadFromTile(
          platform: platform,
          source: source,
          kind: kind,
        );
      },
    );
  }

  Future<void> _executeDownloadFromTile({
    required DownloadPlatform platform,
    required Uri source,
    required DownloadKind kind,
  }) async {
    setState(() {
      _stateOf(platform)
        ..busy = true
        ..progress = null
        ..status = 'Çözülüyor…';
    });

    final notificationId = DownloadNotificationService.instance
        .allocateNotificationId();
    final notifTitle = '${platform.label} İndirme';
    int lastNotifPercent = -1;

    try {
      final media = await widget.resolver.resolve(source, kind);
      if (!mounted) return;
      setState(() {
        _stateOf(platform).status = 'İndiriliyor…';
      });

      final displayTitle = media.fileName.trim().isNotEmpty
          ? media.fileName.trim()
          : notifTitle;

      unawaited(
        DownloadNotificationService.instance.showProgress(
          id: notificationId,
          title: displayTitle,
          percent: null,
        ),
      );

      final file = await widget.downloader.download(
        media,
        onProgress: (received, total) {
          if (!mounted) return;
          final percent = downloadPercent(received, total);
          setState(() {
            _stateOf(platform)
              ..progress = (total == null || total <= 0)
                  ? null
                  : received / total
              ..status = percent == null
                  ? 'İndiriliyor…'
                  : 'İndiriliyor… %$percent';
          });
          if (percent != null && percent != lastNotifPercent) {
            lastNotifPercent = percent;
            unawaited(
              DownloadNotificationService.instance.showProgress(
                id: notificationId,
                title: displayTitle,
                percent: percent,
              ),
            );
          }
        },
      );
      widget.onDownloaded?.call(kind);
      final fileName = file.path.split(Platform.pathSeparator).last;
      int fileSize = 0;
      try {
        fileSize = file.lengthSync();
      } catch (_) {}
      unawaited(
        StorageService.addItem(
          DownloadItemModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: fileName,
            type: kind == DownloadKind.audio ? 'audio' : 'video',
            sizeInBytes: fileSize,
            filePath: file.path,
            downloadedAt: DateTime.now(),
            sourceUrl: source.toString(),
          ),
        ),
      );
      unawaited(
        DownloadNotificationService.instance.showCompleted(
          id: notificationId,
          title: displayTitle,
          fileName: fileName,
        ),
      );
      if (!mounted) return;
      setState(() {
        _stateOf(platform)
          ..busy = false
          ..progress = null
          ..status = 'İndirildi: $fileName';
      });
    } catch (error) {
      final errorMsg = switch (error) {
        MediaResolverException(:final message) => message,
        MediaDownloadException(:final message) => message,
        _ => 'İndirilemedi',
      };
      unawaited(
        DownloadNotificationService.instance.showError(
          id: notificationId,
          title: notifTitle,
          error: errorMsg,
        ),
      );
      if (!mounted) return;
      setState(() {
        _stateOf(platform)
          ..busy = false
          ..progress = null
          ..status = errorMsg;
      });
    }
  }

  void _openPlatformModal(DownloadPlatform platform) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PlatformSearchDownloadModal(
        platform: platform,
        resolver: widget.resolver,
        downloader: widget.downloader,
        onDownloaded: widget.onDownloaded,
      ),
    );
  }

  /// Highlights the tapped platform tile and fills the URL field.
  ///
  /// A tile only labels the field: the backend resolves whatever URL is pasted,
  /// so tapping a tile can never send a request on its own. Tapping the tile a
  /// second time clears the selection.
  void _selectPlatform(DownloadPlatform platform) {
    _openPlatformModal(platform);
    final isSamePlatform = _selectedPlatform?.label == platform.label;
    setState(() {
      _selectedPlatform = isSamePlatform ? null : platform;
      _message = isSamePlatform
          ? 'Platform seçimi kaldırıldı.'
          : '${platform.label} seçildi · ${platform.hint} bağlantısını yapıştırın veya arayın';
      _messageIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showPremiumBanner) ...[
              const PremiumBanner(),
              const SizedBox(height: 14),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.text('section_which_platform'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF172B3A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.text('section_tap_hint'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF87949D),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BulkDownloadScreen(
                          resolver: widget.resolver,
                          downloader: widget.downloader,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.layers_rounded, size: 18),
                  label: const Text('Toplu İndir'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _PlatformGrid(
              selected: _selectedPlatform,
              enabled: true,
              onSelected: _selectPlatform,
              controllers: _tileUrlControllers,
              focusNodes: _tileFocusNodes,
              states: _tileState,
              onDownload: _downloadFromTile,
            ),
            if (_message != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _messageIsError
                      ? const Color(0xFFFFF0EF)
                      : const Color(0xFFE5F3F4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _messageIsError
                        ? const Color(0xFF9C2F29)
                        : const Color(0xFF17656D),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.text('section_downloads'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Color(0xFF172B3A),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DownloadsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.download_done_rounded, size: 18),
                  label: Text(l10n.text('section_downloads')),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.text('section_downloads_hint'),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF87949D)),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SizedBox(
                    height: 168,
                    child: DownloadCategoryCard(
                      category: kVideoCategory,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const DownloadsScreen(initialFilter: 'video'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SizedBox(
                    height: 168,
                    child: DownloadCategoryCard(
                      category: kAudioCategory,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const DownloadsScreen(initialFilter: 'audio'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Backend adresi ve API anahtarı Ayarlar sekmesinden ayarlanır.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF87949D), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackendSettingsPage extends StatefulWidget {
  const _BackendSettingsPage({required this.store, required this.resolver});

  final BackendSettingsStore store;
  final BackendMediaResolver resolver;

  @override
  State<_BackendSettingsPage> createState() => _BackendSettingsPageState();
}

class _BackendSettingsPageState extends State<_BackendSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  bool _obscureApiKey = true;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await widget.store.load();
      if (!mounted) return;
      _baseUrlController.text = settings.baseUrl;
      _apiKeyController.text = settings.apiKey;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Ayarlar okunamadı: $error';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  BackendSettings? _settingsFromForm() {
    if (!_formKey.currentState!.validate()) return null;
    try {
      return BackendSettings.fromInput(
        baseUrl: _baseUrlController.text,
        apiKey: _apiKeyController.text,
      );
    } on FormatException catch (error) {
      setState(() {
        _message = error.message;
        _messageIsError = true;
      });
      return null;
    }
  }

  Future<void> _saveSettings({bool testConnection = false}) async {
    final settings = _settingsFromForm();
    if (settings == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = testConnection ? 'Backend bağlantısı sınanıyor…' : null;
      _messageIsError = false;
    });
    try {
      if (testConnection) {
        await widget.resolver.testConnection(settings: settings);
      }
      await widget.store.save(settings);
      if (!mounted) return;
      _baseUrlController.text = settings.baseUrl;
      setState(() {
        _message = testConnection
            ? 'Bağlantı başarılı; ayarlar güvenli biçimde kaydedildi.'
            : 'Ayarlar güvenli biçimde kaydedildi.';
        _messageIsError = false;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error is MediaResolverException
            ? error.message
            : 'Ayarlar kaydedilemedi: $error';
        _messageIsError = true;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Backend bağlantısı',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF172B3A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'VidSave sunucunun adresini ve gerekiyorsa API anahtarını kullanır.',
                style: TextStyle(color: Color(0xFF74838D)),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _baseUrlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Backend adresi',
                  hintText: 'https://sunucu-adresi:8787',
                  prefixIcon: Icon(Icons.dns_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Backend adresini girin.';
                  }
                  try {
                    BackendSettings.fromInput(
                      baseUrl: value,
                      apiKey: _apiKeyController.text,
                    );
                  } on FormatException catch (error) {
                    return error.message;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _apiKeyController,
                obscureText: _obscureApiKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'API anahtarı (isteğe bağlı)',
                  prefixIcon: const Icon(Icons.key_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscureApiKey
                        ? 'Anahtarı göster'
                        : 'Anahtarı gizle',
                    onPressed: () =>
                        setState(() => _obscureApiKey = !_obscureApiKey),
                    icon: Icon(
                      _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Emülatör: http://10.0.2.2:8787 · Gerçek telefon: '
                'http://bilgisayarın-LAN-IP:8787. Android yayın sürümünde '
                'HTTP yerine HTTPS gerekir.',
                style: TextStyle(color: Color(0xFF74838D), fontSize: 12),
              ),
              const SizedBox(height: 10),
              const Text(
                'API anahtarı cihazın şifreli güvenli deposunda tutulur. Uygulama sahibinin cihaz erişimi varsa anahtar yine çıkarılabilir; üretimde kullanıcıya özel kısa ömürlü kimlik bilgisi tercih edin.',
                style: TextStyle(color: Color(0xFF74838D), fontSize: 12),
              ),
              if (_message != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _messageIsError
                        ? const Color(0xFFFFF0EF)
                        : const Color(0xFFE5F3F4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      color: _messageIsError
                          ? const Color(0xFF9C2F29)
                          : const Color(0xFF17656D),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _saveSettings(testConnection: true),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_rounded),
                label: const Text('Bağlantıyı Sına ve Kaydet'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _saveSettings,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Sadece Kaydet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaLibraryPage extends StatefulWidget {
  const _MediaLibraryPage({
    super.key,
    required this.title,
    required this.type,
    required this.library,
    required this.permissionState,
    required this.permissionLoading,
    required this.permissionError,
    required this.onRetryPermission,
    required this.videoPlayerControllerFactory,
    required this.musicPlayerFactory,
    required this.musicSourceResolver,
  });

  final String title;
  final RequestType type;
  final MediaLibrary library;
  final PermissionState? permissionState;
  final bool permissionLoading;
  final Object? permissionError;
  final VoidCallback onRetryPermission;
  final VideoPlayerControllerFactory? videoPlayerControllerFactory;
  final AudioPlayerFactory? musicPlayerFactory;
  final AudioSourceResolver? musicSourceResolver;

  @override
  State<_MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<_MediaLibraryPage> {
  static const _pageSize = 60;

  final _scrollController = ScrollController();
  final List<AssetEntity> _assets = [];
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  Object? _loadError;

  bool get _hasPermission => widget.permissionState?.hasAccess ?? false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadWhenNearEnd);
  }

  @override
  void didUpdateWidget(covariant _MediaLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previouslyAuthorized = oldWidget.permissionState?.hasAccess ?? false;
    if (_hasPermission && !previouslyAuthorized) {
      _resetAndLoad();
    } else if (!_hasPermission && previouslyAuthorized) {
      setState(() {
        _assets.clear();
        _page = 0;
        _hasMore = true;
        _loadError = null;
      });
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadWhenNearEnd)
      ..dispose();
    super.dispose();
  }

  void _loadWhenNearEnd() {
    if (_scrollController.position.extentAfter < 320) {
      _loadNextPage();
    }
  }

  void _resetAndLoad() {
    setState(() {
      _assets.clear();
      _page = 0;
      _hasMore = true;
      _loadError = null;
    });
    _loadNextPage();
  }

  void reload() {
    widget.library.invalidateCache();
    if (!_hasPermission) return;
    _resetAndLoad();
    // A just-downloaded file may need a moment to appear in the media store.
    // Re-scan shortly after so the İndirilenler list stays in sync.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted && _hasPermission) {
        widget.library.invalidateCache();
        _resetAndLoad();
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _hasPermission) {
        widget.library.invalidateCache();
        _resetAndLoad();
      }
    });
  }

  void _openVideo(AssetEntity asset) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoPlayerScreen(
          asset: asset,
          controllerFactory: widget.videoPlayerControllerFactory,
        ),
      ),
    );
  }

  void _openMusic(AssetEntity asset) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MusicPlayerScreen(
          asset: asset,
          playerFactory: widget.musicPlayerFactory,
          sourceResolver: widget.musicSourceResolver,
        ),
      ),
    );
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore || !_hasPermission) return;

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final nextAssets = await widget.library.loadPage(
        type: widget.type,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _assets.addAll(nextAssets);
        _page++;
        _hasMore = nextAssets.length == _pageSize;
        _loading = false;
      });
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'VidSave media library',
          context: ErrorDescription('while loading ${widget.title}'),
        ),
      );
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.permissionLoading) {
      return const _LibraryStatus(
        icon: Icons.lock_outline_rounded,
        message: 'Galeri erişim izni bekleniyor…',
        showProgress: true,
      );
    }

    if (widget.permissionError case final error?) {
      return _LibraryStatus(
        icon: Icons.error_outline_rounded,
        message: 'Galeri izni alınamadı: $error',
        actionLabel: 'Tekrar Dene',
        onAction: widget.onRetryPermission,
      );
    }

    if (!_hasPermission) {
      return _LibraryStatus(
        icon: Icons.photo_library_outlined,
        message:
            'Cihazınızdaki ${widget.title.toLowerCase()}ı göstermek için '
            'galeri erişim izni gerekiyor.',
        actionLabel: 'İzin Ver',
        onAction: widget.onRetryPermission,
        secondaryActionLabel: 'Ayarları Aç',
        onSecondaryAction: PhotoManager.openSetting,
      );
    }

    if (_assets.isEmpty && _loading) {
      return const _LibraryStatus(
        icon: Icons.photo_library_outlined,
        message: 'Cihaz medyası taranıyor…',
        showProgress: true,
      );
    }

    if (_assets.isEmpty && _loadError != null) {
      return _LibraryStatus(
        icon: Icons.error_outline_rounded,
        message: 'Medya yüklenemedi: $_loadError',
        actionLabel: 'Tekrar Dene',
        onAction: _loadNextPage,
      );
    }

    if (_assets.isEmpty && !_hasMore) {
      return _LibraryStatus(
        icon: widget.type == RequestType.video
            ? Icons.video_library_outlined
            : Icons.music_off_rounded,
        message:
            'Cihazda gösterilecek ${widget.title.toLowerCase()} bulunamadı.',
      );
    }

    final rows = _buildRows();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: rows.length + (_loading || _loadError != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == rows.length) {
          if (_loadError != null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text('Daha fazla medya yüklenemedi: $_loadError'),
                  TextButton(
                    onPressed: _loadNextPage,
                    child: const Text('Tekrar Dene'),
                  ),
                ],
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final row = rows[index];
        if (row.dateLabel != null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
            child: Text(
              row.dateLabel!,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: const Color(0xFF52636E),
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }
        return _MediaAssetTile(
          asset: row.asset!,
          isVideo: widget.type == RequestType.video,
          onTap: () {
            if (widget.type == RequestType.video) {
              _openVideo(row.asset!);
            } else {
              _openMusic(row.asset!);
            }
          },
        );
      },
    );
  }

  List<_MediaListRow> _buildRows() {
    final groups = <DateTime, List<AssetEntity>>{};
    for (final asset in _assets) {
      final createdAt = asset.createDateTime.toLocal();
      final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
      groups.putIfAbsent(date, () => []).add(asset);
    }

    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final date in dates) ...[
        _MediaListRow.header(_formatDate(date)),
        for (final asset in groups[date]!) _MediaListRow.media(asset),
      ],
    ];
  }

  String _formatDate(DateTime date) {
    const months = [
      'Ocak',
      '�?ubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    final today = DateTime.now();
    final localToday = DateTime(today.year, today.month, today.day);
    if (date == localToday) return 'Bugün';
    if (date == localToday.subtract(const Duration(days: 1))) return 'Dün';
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _MediaListRow {
  const _MediaListRow.header(this.dateLabel) : asset = null;
  const _MediaListRow.media(this.asset) : dateLabel = null;

  final String? dateLabel;
  final AssetEntity? asset;
}

class _MediaAssetTile extends StatefulWidget {
  const _MediaAssetTile({
    required this.asset,
    required this.isVideo,
    this.onTap,
  });

  final AssetEntity asset;
  final bool isVideo;
  final VoidCallback? onTap;

  @override
  State<_MediaAssetTile> createState() => _MediaAssetTileState();
}

class _MediaAssetTileState extends State<_MediaAssetTile> {
  late final Future<String> _titleFuture = widget.asset.titleAsync;
  late final Future<int> _fileSizeFuture = widget.asset.fileSize;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE7ECEF)),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5F3F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.isVideo
                      ? Icons.play_circle_outline_rounded
                      : Icons.music_note_rounded,
                  color: const Color(0xFF087E8B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<String>(
                      future: _titleFuture,
                      builder: (context, snapshot) {
                        final title = snapshot.hasError
                            ? 'Ad okunamadı: ${snapshot.error}'
                            : snapshot.data ??
                                  (snapshot.connectionState ==
                                          ConnectionState.waiting
                                      ? 'Medya adı yükleniyor…'
                                      : 'Adsız medya');
                        return Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF263943),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _MetadataText(_formatDuration(widget.asset.duration)),
                        if (widget.isVideo)
                          _MetadataText(
                            '${widget.asset.width} × ${widget.asset.height}',
                          ),
                        FutureBuilder<int>(
                          future: _fileSizeFuture,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return _MetadataText(
                                'Boyut okunamadı: ${snapshot.error}',
                              );
                            }
                            if (!snapshot.hasData) {
                              return const _MetadataText('Boyut yükleniyor…');
                            }
                            return _MetadataText(
                              '${(snapshot.data! / (1024 * 1024)).toStringAsFixed(2)} MB',
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final remainingSeconds = duration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$remainingSeconds';
    }
    return '$minutes:$remainingSeconds';
  }
}

class _MetadataText extends StatelessWidget {
  const _MetadataText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Color(0xFF74838D), fontSize: 12),
    );
  }
}

class _LibraryStatus extends StatelessWidget {
  const _LibraryStatus({
    required this.icon,
    required this.message,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String message;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 48, color: const Color(0xFF087E8B)),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
            if (secondaryActionLabel != null)
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rounded-square shortcut tiles for the supported platforms.
///
/// Every square owns a URL field and an İNDİR button, so each one downloads on
/// its own.
class _PlatformGrid extends StatelessWidget {
  const _PlatformGrid({
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.controllers,
    required this.focusNodes,
    required this.states,
    required this.onDownload,
  });

  final DownloadPlatform? selected;
  final bool enabled;
  final ValueChanged<DownloadPlatform> onSelected;
  final Map<String, TextEditingController> controllers;
  final Map<String, FocusNode> focusNodes;
  final Map<String, _TileDownloadState> states;
  final ValueChanged<DownloadPlatform> onDownload;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: kDownloadPlatforms.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, index) {
        final platform = kDownloadPlatforms[index];
        final tileState = states[platform.label];
        return _PlatformTile(
          platform: platform,
          enabled: enabled,
          selected: platform == selected,
          downloading: tileState?.busy ?? false,
          progress: tileState?.progress,
          statusLabel: tileState?.status,
          onTap: () => onSelected(platform),
          onDownload: () => onSelected(platform),
        );
      },
    );
  }
}

/// One square in the platform grid: a logo, label and its own İNDİR button.
class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.platform,
    required this.onDownload,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.downloading = false,
    this.progress,
    this.statusLabel,
  });

  final DownloadPlatform platform;
  final VoidCallback onDownload;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;
  final bool downloading;
  final double? progress;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    return PlatformButton(
      platform: platform,
      enabled: enabled,
      selected: selected,
      downloading: downloading,
      progress: progress,
      statusLabel: statusLabel,
      onTap: onTap,
      onDownload: onDownload,
    );
  }
}

/// Platform search & download bottom sheet modal:
/// Opens when a platform card (FB, IG, TT, etc.) is tapped.
/// Users can search or paste a link specifically for that platform,
/// fetch preview, and see all available qualities each with an INDIR button.
class PlatformSearchDownloadModal extends StatefulWidget {
  const PlatformSearchDownloadModal({
    super.key,
    required this.platform,
    required this.resolver,
    required this.downloader,
    this.onDownloaded,
  });

  final DownloadPlatform platform;
  final MediaResolver resolver;
  final MediaDownloader downloader;
  final ValueChanged<DownloadKind>? onDownloaded;

  @override
  State<PlatformSearchDownloadModal> createState() =>
      _PlatformSearchDownloadModalState();
}

class _PlatformSearchDownloadModalState
    extends State<PlatformSearchDownloadModal> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _searching = false;
  bool _downloading = false;
  int? _downloadingHeight;
  List<SearchResultItem> _searchResults = [];
  String? _downloadingUrl;
  double? _downloadProgress;
  String? _downloadSpeed;
  DateTime? _lastProgressTime;
  int? _lastReceivedBytes;
  String? _statusMessage;
  bool _statusIsError = false;
  MediaPreview? _preview;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  List<VideoQuality> _qualitiesFor(MediaPreview preview) {
    if (widget.platform.isAudio) {
      return const [
        VideoQuality(
          height: 0,
          label: 'MP3 Ses Dosyası (320 kbps - En Yüksek Kalite)',
        ),
        VideoQuality(height: 192, label: 'MP3 Standart Kalite (192 kbps)'),
        VideoQuality(height: 128, label: 'MP3 Hızlı İndir (128 kbps)'),
      ];
    }
    if (preview.qualities.isNotEmpty) {
      return [
        const VideoQuality(height: 0, label: 'En İyi Kalite (Önerilen)'),
        ...preview.qualities,
      ];
    }
    return const [
      VideoQuality(height: 0, label: 'En İyi Kalite (Önerilen)'),
      VideoQuality(height: 1080, label: '1080p Full HD'),
      VideoQuality(height: 720, label: '720p HD'),
      VideoQuality(height: 480, label: '480p Standart'),
      VideoQuality(height: 360, label: '360p Düşük'),
    ];
  }

  Future<void> _handleSearch() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _statusMessage = 'Arama yapmak veya indirmek için bir şey yazın.';
        _statusIsError = true;
      });
      return;
    }

    final parsed = Uri.tryParse(text);
    final isUrl =
        parsed != null &&
        parsed.host.isNotEmpty &&
        (parsed.isScheme('http') || parsed.isScheme('https'));

    _focusNode.unfocus();
    setState(() {
      _searching = true;
      _statusMessage = isUrl
          ? 'Bağlantı inceleniyor…'
          : (widget.platform.isAudio
                ? 'Şarkılar aranıyor…'
                : 'İçerik ve çözünürlük seçenekleri aranıyor…');
      _statusIsError = false;
      _preview = null;
      _searchResults = [];
    });

    // Platform doğrulama kontrolü: Her platform yalnızca kendi linkini indirebilir
    if (isUrl && !widget.platform.matchesUrl(text)) {
      setState(() {
        _searching = false;
        _statusMessage =
            'Bu bağlantı ${widget.platform.label} platformuna ait değil! Lütfen ${widget.platform.hint} bağlantısı yapıştırın.';
        _statusIsError = true;
      });
      return;
    }

    final source = isUrl ? parsed : Uri(path: text);
    final kind = widget.platform.isAudio
        ? DownloadKind.audio
        : DownloadKind.video;

    // MP3 aramasında bir URL değilse önce /api/ara üzerinden liste araması yap
    if (widget.platform.isAudio && !isUrl) {
      try {
        final results = await widget.resolver.search(text);
        if (!mounted) return;
        if (results.isNotEmpty) {
          setState(() {
            _searching = false;
            _searchResults = results;
            _statusMessage = null;
            _statusIsError = false;
          });
          return;
        }
      } catch (_) {
        // Doğrudan preview'a fallback yap
      }
    }

    try {
      final preview = await widget.resolver.preview(source, kind);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _preview = preview;
        _statusMessage = null;
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      final errMsg = switch (e) {
        MediaResolverException(:final message) => message,
        _ => 'Arama başarısız oldu veya video bulunamadı: $e',
      };
      setState(() {
        _searching = false;
        _statusMessage = errMsg;
        _statusIsError = true;
        // Eğer doğrudan bir URL girildiyse ve MP3 indirilmek isteniyorsa,
        // önizleme başarısız olsa bile doğrudan MP3 indirme butonlarını göster.
        if (isUrl && widget.platform.isAudio) {
          _preview = MediaPreview(
            title: text,
            qualities: const [
              VideoQuality(
                height: 0,
                label: 'MP3 Ses Dosyası (320 kbps - En Yüksek Kalite)',
              ),
              VideoQuality(
                height: 192,
                label: 'MP3 Standart Kalite (192 kbps)',
              ),
              VideoQuality(height: 128, label: 'MP3 Hızlı İndir (128 kbps)'),
            ],
          );
        }
      });
    }
  }

  Future<void> _startDownloadMusicItem(SearchResultItem item) async {
    // Ödüllü reklam filtresi: isPremium == true ise bypass eder, false ise reklam izletir
    await AdmobService.instance.showRewardedAdOrBypass(
      onRewardEarned: () async {
        await _executeDownloadMusicItem(item);
      },
    );
  }

  Future<void> _executeDownloadMusicItem(SearchResultItem item) async {
    final parsed = Uri.tryParse(item.url);
    final isUrl =
        parsed != null &&
        parsed.host.isNotEmpty &&
        (parsed.isScheme('http') || parsed.isScheme('https'));
    final source = isUrl
        ? parsed
        : Uri(path: item.url.isNotEmpty ? item.url : item.baslik);

    setState(() {
      _downloading = true;
      _downloadingUrl = item.id.isNotEmpty ? item.id : item.url;
      _downloadProgress = null;
      _downloadSpeed = null;
      _lastProgressTime = DateTime.now();
      _lastReceivedBytes = 0;
      _statusMessage = '${item.baslik} MP3 olarak indiriliyor…';
      _statusIsError = false;
    });

    final notificationId = DownloadNotificationService.instance
        .allocateNotificationId();
    final itemTitle = item.baslik.isNotEmpty ? item.baslik : 'MP3 İndirme';
    int lastNotifPercent = -1;

    try {
      final media = await widget.resolver.resolve(source, DownloadKind.audio);
      if (!mounted) return;

      final effectiveTitle = media.fileName.trim().isNotEmpty
          ? media.fileName.trim()
          : itemTitle;

      unawaited(
        DownloadNotificationService.instance.showProgress(
          id: notificationId,
          title: effectiveTitle,
          percent: null,
        ),
      );

      final file = await widget.downloader.download(
        media,
        onProgress: (received, total) {
          if (!mounted) return;
          final percent = downloadPercent(received, total);

          // Canlı indirme hızını hesapla
          final now = DateTime.now();
          if (_lastProgressTime != null && _lastReceivedBytes != null) {
            final diffMs = now.difference(_lastProgressTime!).inMilliseconds;
            if (diffMs >= 500) {
              final bytesDiff = received - _lastReceivedBytes!;
              final bytesPerSec = (bytesDiff * 1000) ~/ diffMs;
              _downloadSpeed = '${formatBytes(bytesPerSec)}/s';
              _lastProgressTime = now;
              _lastReceivedBytes = received;
            }
          }

          final speedText = _downloadSpeed != null ? ' ($_downloadSpeed)' : '';
          setState(() {
            _downloadProgress = (total == null || total <= 0)
                ? null
                : received / total;
            _statusMessage = percent == null
                ? '${item.baslik} indiriliyor…$speedText'
                : '%$percent İndiriliyor…$speedText';
          });
          if (percent != null && percent != lastNotifPercent) {
            lastNotifPercent = percent;
            unawaited(
              DownloadNotificationService.instance.showProgress(
                id: notificationId,
                title: effectiveTitle,
                percent: percent,
                speed: _downloadSpeed,
              ),
            );
          }
        },
      );
      widget.onDownloaded?.call(DownloadKind.audio);
      final fileName = file.path.split(Platform.pathSeparator).last;
      int fileSize = 0;
      try {
        fileSize = file.lengthSync();
      } catch (_) {}
      unawaited(
        StorageService.addItem(
          DownloadItemModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: fileName,
            type: 'audio',
            sizeInBytes: fileSize,
            filePath: file.path,
            downloadedAt: DateTime.now(),
            sourceUrl: source.toString(),
          ),
        ),
      );
      unawaited(
        DownloadNotificationService.instance.showCompleted(
          id: notificationId,
          title: effectiveTitle,
          fileName: fileName,
        ),
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadingUrl = null;
        _downloadProgress = null;
        _statusMessage = 'Başarıyla indirildi: $fileName';
        _statusIsError = false;
      });

      // İndirme başarıyla tamamlandığında paneli otomatik kapat
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    } catch (error) {
      final errorMsg = switch (error) {
        MediaResolverException(:final message) => message,
        MediaDownloadException(:final message) => message,
        _ => 'İndirme tamamlanamadı: $error',
      };
      unawaited(
        DownloadNotificationService.instance.showError(
          id: notificationId,
          title: itemTitle,
          error: errorMsg,
        ),
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadingUrl = null;
        _downloadProgress = null;
        _statusMessage = errorMsg;
        _statusIsError = true;
      });
    }
  }

  Future<void> _startDownloadQuality(VideoQuality quality) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final parsed = Uri.tryParse(text);
    final isUrl =
        parsed != null &&
        parsed.host.isNotEmpty &&
        (parsed.isScheme('http') || parsed.isScheme('https'));

    // Platform doğrulama kontrolü: Her platform yalnızca kendi linkini indirebilir
    if (isUrl && !widget.platform.matchesUrl(text)) {
      setState(() {
        _statusMessage =
            'Bu bağlantı ${widget.platform.label} platformuna ait değil! Lütfen ${widget.platform.hint} bağlantısı yapıştırın.';
        _statusIsError = true;
      });
      return;
    }

    await AdmobService.instance.showRewardedAdOrBypass(
      onRewardEarned: () async {
        await _executeDownloadQuality(quality, text, parsed, isUrl);
      },
    );
  }

  Future<void> _executeDownloadQuality(
    VideoQuality quality,
    String text,
    Uri? parsed,
    bool isUrl,
  ) async {
    final source = isUrl ? parsed! : Uri(path: text);
    final kind = widget.platform.isAudio
        ? DownloadKind.audio
        : DownloadKind.video;

    setState(() {
      _downloading = true;
      _downloadingHeight = quality.height;
      _downloadProgress = null;
      _downloadSpeed = null;
      _lastProgressTime = DateTime.now();
      _lastReceivedBytes = 0;
      _statusMessage = '${quality.label} hazırlanıyor…';
      _statusIsError = false;
    });

    final notificationId = DownloadNotificationService.instance
        .allocateNotificationId();
    final modalDisplayTitle = _preview?.title.trim().isNotEmpty == true
        ? _preview!.title.trim()
        : '${widget.platform.label} (${quality.label})';
    int lastNotifPercent = -1;

    try {
      final height = quality.height > 0 ? quality.height : null;
      final media = await widget.resolver.resolve(source, kind, height: height);
      if (!mounted) return;
      setState(() {
        _statusMessage = '${quality.label} indiriliyor…';
      });

      final effectiveTitle = media.fileName.trim().isNotEmpty
          ? media.fileName.trim()
          : modalDisplayTitle;

      unawaited(
        DownloadNotificationService.instance.showProgress(
          id: notificationId,
          title: effectiveTitle,
          percent: null,
        ),
      );

      final file = await widget.downloader.download(
        media,
        onProgress: (received, total) {
          if (!mounted) return;
          final percent = downloadPercent(received, total);

          // Canlı indirme hızını hesapla
          final now = DateTime.now();
          if (_lastProgressTime != null && _lastReceivedBytes != null) {
            final diffMs = now.difference(_lastProgressTime!).inMilliseconds;
            if (diffMs >= 500) {
              final bytesDiff = received - _lastReceivedBytes!;
              final bytesPerSec = (bytesDiff * 1000) ~/ diffMs;
              _downloadSpeed = '${formatBytes(bytesPerSec)}/s';
              _lastProgressTime = now;
              _lastReceivedBytes = received;
            }
          }

          final speedText = _downloadSpeed != null ? ' ($_downloadSpeed)' : '';
          setState(() {
            _downloadProgress = (total == null || total <= 0)
                ? null
                : received / total;
            _statusMessage = percent == null
                ? '${quality.label} indiriliyor…$speedText'
                : '%$percent İndiriliyor…$speedText';
          });
          if (percent != null && percent != lastNotifPercent) {
            lastNotifPercent = percent;
            unawaited(
              DownloadNotificationService.instance.showProgress(
                id: notificationId,
                title: effectiveTitle,
                percent: percent,
                speed: _downloadSpeed,
              ),
            );
          }
        },
      );
      widget.onDownloaded?.call(kind);
      final fileName = file.path.split(Platform.pathSeparator).last;
      int fileSize = 0;
      try {
        fileSize = file.lengthSync();
      } catch (_) {}
      unawaited(
        StorageService.addItem(
          DownloadItemModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: fileName,
            type: kind == DownloadKind.audio ? 'audio' : 'video',
            sizeInBytes: fileSize,
            filePath: file.path,
            downloadedAt: DateTime.now(),
            sourceUrl: source.toString(),
          ),
        ),
      );
      unawaited(
        DownloadNotificationService.instance.showCompleted(
          id: notificationId,
          title: effectiveTitle,
          fileName: fileName,
        ),
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadingHeight = null;
        _downloadProgress = null;
        _statusMessage = 'Başarıyla indirildi: $fileName';
        _statusIsError = false;
      });

      // İndirme başarıyla tamamlandığında paneli otomatik kapat
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    } catch (error) {
      final errorMsg = switch (error) {
        MediaResolverException(:final message) => message,
        MediaDownloadException(:final message) => message,
        _ => 'İndirme tamamlanamadı: $error',
      };
      unawaited(
        DownloadNotificationService.instance.showError(
          id: notificationId,
          title: modalDisplayTitle,
          error: errorMsg,
        ),
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadingHeight = null;
        _downloadProgress = null;
        _statusMessage = errorMsg;
        _statusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.platform.gradient;
    final primaryColor = colors.last;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                PlatformLogo(platform: widget.platform, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.platform.label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF172B3A),
                        ),
                      ),
                      Text(
                        widget.platform.isAudio
                            ? 'Şarkı arayın veya video linki yapıştırın (MP3 dönüştürülür)'
                            : '${widget.platform.hint} linki yapıştırın veya arayın',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF87949D),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF87949D),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Search / Link Input
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: !_downloading,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: true,
              onSubmitted: (_) =>
                  _searching || _downloading ? null : _handleSearch(),
              decoration: InputDecoration(
                labelText: widget.platform.isAudio
                    ? 'Müzik ara veya Video linki yapıştırın (YouTube, TikTok, IG vb.)'
                    : 'Video ara veya bağlantı yapıştırın',
                hintText: widget.platform.isAudio
                    ? 'Şarkı adı veya video linki yapıştırın'
                    : widget.platform.hint,
                prefixIcon: Icon(Icons.search_rounded, color: primaryColor),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_controller.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _preview = null;
                            _statusMessage = null;
                          });
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilledButton(
                        onPressed: _searching || _downloading
                            ? null
                            : _handleSearch,
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _searching
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'ARA',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                filled: true,
                fillColor: const Color(0xFFF6F8F9),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE7ECEF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: primaryColor, width: 1.5),
                ),
              ),
            ),
            if (_searching) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'İçerik ve çözünürlükler alınıyor…',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  minHeight: 6,
                  backgroundColor: primaryColor.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
            ],
            if (_statusMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusIsError
                      ? const Color(0xFFFFF0EF)
                      : primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _statusIsError
                        ? const Color(0xFF9C2F29)
                        : primaryColor,
                  ),
                ),
              ),
            ],
            // Multi-item Search Results (e.g. MP3 /api/ara response list)
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ARAMA SONUÇLARI',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Color(0xFF74838D),
                    ),
                  ),
                  Text(
                    '${_searchResults.length} sonuç',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF87949D),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'İndirmek istediğiniz şarkının kartına veya İNDİR butonuna dokunun',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF87949D)),
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final item = _searchResults[index];
                  final isItemDownloading =
                      _downloading &&
                      (_downloadingUrl == item.id ||
                          _downloadingUrl == item.url);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isItemDownloading
                            ? primaryColor
                            : const Color(0xFFE2E8EC),
                        width: isItemDownloading ? 1.5 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _downloading
                          ? null
                          : () => _startDownloadMusicItem(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: isItemDownloading
                                  ? Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: primaryColor,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      Icons.music_note_rounded,
                                      size: 24,
                                      color: primaryColor,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.baslik,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF172B3A),
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if (item.kanal.isNotEmpty) ...[
                                        const Icon(
                                          Icons.person_outline_rounded,
                                          size: 13,
                                          color: Color(0xFF87949D),
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            item.kanal,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: Color(0xFF87949D),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      if (item.sure.isNotEmpty) ...[
                                        const Icon(
                                          Icons.timer_outlined,
                                          size: 13,
                                          color: Color(0xFF87949D),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          item.sure,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFF87949D),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            isItemDownloading
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 80,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: _downloadProgress,
                                            minHeight: 6,
                                            backgroundColor: primaryColor.withValues(alpha: 0.2),
                                            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _downloadProgress != null
                                            ? '%${(_downloadProgress! * 100).round()}'
                                            : '…',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: primaryColor,
                                        ),
                                      ),
                                    ],
                                  )
                                : FilledButton.icon(
                                    onPressed: _downloading
                                        ? null
                                        : () => _startDownloadMusicItem(item),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: primaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.download_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'İNDİR',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
            // Content Preview & Resolutions with INDIR buttons beside each
            if (_preview != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8EC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _preview!.title.isEmpty
                          ? 'İçerik bulundu'
                          : _preview!.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF172B3A),
                      ),
                    ),
                    if (_preview!.duration != null ||
                        _preview!.uploader != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (_preview!.duration != null) ...[
                            const Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: Color(0xFF87949D),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(_preview!.duration),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF87949D),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (_preview!.uploader != null) ...[
                            const Icon(
                              Icons.person_outline,
                              size: 14,
                              color: Color(0xFF87949D),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _preview!.uploader!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF87949D),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    if (widget.platform.isAudio) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.audiotrack_rounded,
                              size: 15,
                              color: Color(0xFF0E7C4B),
                            ),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Video algılandı · Otomatik olarak MP3 sese dönüştürülüp indirilecek',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0E7C4B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.platform.isAudio
                    ? 'MP3 SES DÖNÜŞTÜRME SEÇENEKLERİ'
                    : 'ÇÖZÜNÜRLÜK SEÇENEKLERİ',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Color(0xFF74838D),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.platform.isAudio
                    ? 'Video içeriği doğrudan MP3 ses dosyası olarak dönüştürülüp indirilir'
                    : 'İstediğiniz kalitenin yanındaki İNDİR butonuna basarak indirebilirsiniz',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF87949D),
                ),
              ),
              const SizedBox(height: 12),
              ..._qualitiesFor(_preview!).map((quality) {
                final isCurrentDownloading =
                    _downloading && _downloadingHeight == quality.height;
                final sizeStr =
                    quality.sizeInBytes != null && quality.sizeInBytes! > 0
                    ? ' · ${formatBytes(quality.sizeInBytes!)}'
                    : '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCurrentDownloading
                          ? primaryColor
                          : const Color(0xFFE2E8EC),
                      width: isCurrentDownloading ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.platform.isAudio
                              ? Icons.music_note_rounded
                              : (quality.isBest
                                    ? Icons.star_rounded
                                    : Icons.video_settings_rounded),
                          size: 20,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    quality.label,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF172B3A),
                                    ),
                                  ),
                                ),
                                if (quality.isBest) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: primaryColor,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'ÖNERİLEN',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (sizeStr.isNotEmpty)
                              Text(
                                'Yaklaşık boyut$sizeStr',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF87949D),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      isCurrentDownloading
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _downloadProgress,
                                      minHeight: 6,
                                      backgroundColor: primaryColor.withValues(alpha: 0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _downloadProgress != null
                                      ? '%${(_downloadProgress! * 100).round()}'
                                      : '…',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ],
                            )
                          : FilledButton.icon(
                              key: ValueKey('quality_${quality.height}'),
                              onPressed: _downloading
                                  ? null
                                  : () => _startDownloadQuality(quality),
                              style: FilledButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.download_rounded, size: 16),
                              label: Text(
                                widget.platform.isAudio
                                    ? 'MP3 İNDİR'
                                    : 'İNDİR',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
