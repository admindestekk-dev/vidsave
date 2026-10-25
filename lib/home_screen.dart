import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admob_service.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'backend_settings.dart';
import 'client_media_resolver.dart';
import 'download_item_model.dart';
import 'download_notification_service.dart';
import 'media_downloader.dart';
import 'storage_service.dart';
import 'subscription_screen.dart';

/// Ana sayfadaki 'Pro Sürümü Aktif Et' banner'ına veya 'AL' butonuna
/// tıklandığında çalışan Google giriş şartlı abonelik geçiş fonksiyonu.
///
/// 1. Önce yerel hafızadan (shared_preferences) kullanıcının Google ile giriş
///    yapıp yapmadığını kontrol eder.
/// 2. Eğer giriş yapmadıysa: Ekranda şık bir Google oturum açma penceresi açar
///    ve google_sign_in akışını tetikler. Kullanıcı başarıyla giriş yapıp
///    backend'den JWT Token onayını aldığı an, onu bekletmeden doğrudan
///    Aylık 9,99 TL'lik Abonelik Ekranına yönlendirir.
/// 3. Eğer zaten giriş yaptıysa: Hiçbir şey sormadan doğrudan Abonelik Ekranına geçiş yaptırır.
Future<void> _handlePremiumClick(
  BuildContext context, {
  AuthService? authService,
  GoogleSignIn? googleSignInClient,
  BackendSettingsStore? store,
  http.Client? httpClient,
  VoidCallback? onSubscribed,
  bool? isPlayStoreLive,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final userEmail = prefs.getString(SecureAuthTokenStore.prefKeyUserEmail);
  final auth = authService ?? AuthService.instance;
  final hasSession = await auth.hasStoredSession;

  final bool isLoggedIn =
      (userEmail != null && userEmail.trim().isNotEmpty) || hasSession;

  if (!context.mounted) return;

  if (isLoggedIn) {
    // Kullanıcı zaten giriş yapmış: doğrudan Abonelik Ekranına geç
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionScreen(
          store: store,
          httpClient: httpClient,
          authService: auth,
          onSubscribed: onSubscribed,
          isPlayStoreLive: isPlayStoreLive,
        ),
      ),
    );
    return;
  }

  // Kullanıcı giriş yapmamış: Şık Google oturum açma penceresini aç
  await showGoogleSignInModal(
    context,
    authService: auth,
    googleSignInClient: googleSignInClient,
    onSuccess: () {
      if (!context.mounted) return;
      // Backend'den JWT token onayı alındığı an bekletmeden doğrudan Abonelik Ekranına yönlendir
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SubscriptionScreen(
            store: store,
            httpClient: httpClient,
            authService: auth,
            onSubscribed: onSubscribed,
            isPlayStoreLive: isPlayStoreLive,
          ),
        ),
      );
    },
  );
}

/// Dışa açık genel fonksiyon: handlePremiumClick
Future<void> handlePremiumClick(
  BuildContext context, {
  AuthService? authService,
  GoogleSignIn? googleSignInClient,
  BackendSettingsStore? store,
  http.Client? httpClient,
  VoidCallback? onSubscribed,
  bool? isPlayStoreLive,
}) => _handlePremiumClick(
  context,
  authService: authService,
  googleSignInClient: googleSignInClient,
  store: store,
  httpClient: httpClient,
  onSubscribed: onSubscribed,
  isPlayStoreLive: isPlayStoreLive,
);

/// Kullanıcı Google ile giriş yapmadığında açılan şık Google oturum açma alt sayfası.
Future<void> showGoogleSignInModal(
  BuildContext context, {
  required AuthService authService,
  GoogleSignIn? googleSignInClient,
  required VoidCallback onSuccess,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _GoogleSignInSheet(
      authService: authService,
      googleSignInClient: googleSignInClient,
      onSuccess: () {
        Navigator.of(sheetContext).pop();
        onSuccess();
      },
    ),
  );
}

class _GoogleSignInSheet extends StatefulWidget {
  const _GoogleSignInSheet({
    required this.authService,
    this.googleSignInClient,
    required this.onSuccess,
  });

  final AuthService authService;
  final GoogleSignIn? googleSignInClient;
  final VoidCallback onSuccess;

  @override
  State<_GoogleSignInSheet> createState() => _GoogleSignInSheetState();
}

class _GoogleSignInSheetState extends State<_GoogleSignInSheet> {
  bool _isSigningIn = false;

  Future<void> _performGoogleLogin() async {
    if (_isSigningIn) return;
    setState(() => _isSigningIn = true);

    try {
      await widget.authService.loginWithGoogle(
        googleSignInClient: widget.googleSignInClient,
      );
      if (!mounted) return;
      widget.onSuccess();
    } catch (error) {
      if (!mounted) return;
      if (error is AuthException && error.code == 'auth.cancelled') {
        setState(() => _isSigningIn = false);
        return;
      }
      final msg = error is AuthException
          ? error.message
          : 'Google ile giriş yapılamadı: $error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTurkish =
        Localizations.maybeLocaleOf(context)?.languageCode == 'tr';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E2630),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Çekme tutamacı
          Center(
            child: Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Taç İkonu
          Center(
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5436), Color(0xFFFF7E40)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5436).withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Başlık
          Text(
            isTurkish
                ? 'Pro Sürüme Geçmek İçin Giriş Yapın'
                : 'Sign In to Unlock VidSave Pro',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),

          // Açıklama
          Text(
            isTurkish
                ? 'Aboneliğinizi tüm cihazlarınızda güvenle kullanabilmek ve Premium haklarınızı tanımlamak için Google hesabınızla devam edin.'
                : 'Sign in with your Google account to secure your subscription and access Premium features across all devices.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF9AA8B4),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // Google ile Devam Et Butonu
          SizedBox(
            height: 54,
            child: ElevatedButton(
              key: const Key('google_signin_button'),
              onPressed: _isSigningIn ? null : _performGoogleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1F1F1F),
                elevation: 3,
                shadowColor: Colors.black.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSigningIn
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFFFF5436),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FaIcon(
                          FontAwesomeIcons.google,
                          size: 20,
                          color: Color(0xFFEA4335),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isTurkish
                              ? 'Google ile Devam Et'
                              : 'Continue with Google',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // Vazgeç / Kapat butonu
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              isTurkish ? 'Daha Sonra' : 'Maybe Later',
              style: const TextStyle(
                color: Color(0xFF8B9BA7),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ana sayfada gösterilen 'Pro Sürümü Aktif Et' banner bileşeni.
///
/// İçerisinde belirgin ve göz alıcı 'AL' butonu bulunur. Hem banner'a
/// hem de 'AL' butonuna tıklandığında `_handlePremiumClick` tetiklenir.
class PremiumBanner extends StatefulWidget {
  const PremiumBanner({
    super.key,
    this.authService,
    this.googleSignInClient,
    this.store,
    this.httpClient,
    this.onSubscribed,
    this.isPlayStoreLive,
  });

  final AuthService? authService;
  final GoogleSignIn? googleSignInClient;
  final BackendSettingsStore? store;
  final http.Client? httpClient;
  final VoidCallback? onSubscribed;
  final bool? isPlayStoreLive;

  @override
  State<PremiumBanner> createState() => _PremiumBannerState();
}

class _PremiumBannerState extends State<PremiumBanner> {
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _checkPremium();
  }

  Future<void> _checkPremium() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isPrem =
          prefs.getBool(SubscriptionScreen.prefKeyIsPremium) ?? false;
      if (mounted && isPrem != _isPremium) {
        setState(() => _isPremium = isPrem);
      }
    } catch (_) {
      // SharedPreferences erişilemezse (test/mock eksikliği) sessizce geç
    }
  }

  void _onClick() {
    handlePremiumClick(
      context,
      authService: widget.authService,
      googleSignInClient: widget.googleSignInClient,
      store: widget.store,
      httpClient: widget.httpClient,
      onSubscribed: () {
        _checkPremium();
        widget.onSubscribed?.call();
      },
      isPlayStoreLive: widget.isPlayStoreLive,
    ).then((_) {
      if (mounted) _checkPremium();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTurkish =
        Localizations.maybeLocaleOf(context)?.languageCode == 'tr';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isPremium
              ? const [Color(0xFF0E7C4B), Color(0xFF1DB954)]
              : const [Color(0xFFFF5436), Color(0xFFFF7E40)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: (_isPremium ? const Color(0xFF0E7C4B) : const Color(0xFFFF5436))
                .withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('premium_banner_inkwell'),
          borderRadius: BorderRadius.circular(18),
          onTap: _onClick,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // İkon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPremium
                        ? Icons.check_circle_rounded
                        : Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),

                // Metinler
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _isPremium
                                  ? (isTurkish ? 'VidSave Pro Aktif' : 'VidSave Pro Active')
                                  : (isTurkish ? 'Pro Sürümü Aktif Et' : 'Activate Pro Version'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!_isPremium) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isTurkish ? '9,99 TL' : '\$0.99',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _isPremium
                            ? (isTurkish
                                ? 'Sınırsız hız ve 4K indirme aktif'
                                : 'Unlimited speed & 4K active')
                            : (isTurkish
                                ? 'Sınırsız hız, 4K ve reklamsız'
                                : 'Unlimited speed, 4K & ad-free'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // 'AL' Butonu veya 'YÖNET' Butonu
                ElevatedButton(
                  key: const Key('premium_banner_buy_button'),
                  onPressed: _onClick,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _isPremium
                        ? const Color(0xFF0E7C4B)
                        : const Color(0xFFFF5436),
                    elevation: 3,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    minimumSize: const Size(54, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _isPremium
                        ? (isTurkish ? 'YÖNET' : 'MANAGE')
                        : (isTurkish ? 'AL' : 'GET'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Standart HomeScreen arayüzü
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.authService,
    this.store,
    this.httpClient,
  });

  final AuthService? authService;
  final BackendSettingsStore? store;
  final http.Client? httpClient;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const VidSaveBrandTitle(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PremiumBanner(
                authService: authService,
                store: store,
                httpClient: httpClient,
              ),
              const SizedBox(height: 16),
              const QuickDownloadWindow(),
            ],
          ),
        ),
      ),
    );
  }
}

/// VidSave Otomatik Algılama - Sunucu Tabanlı Hızlı İndirme Penceresi
class QuickDownloadWindow extends StatefulWidget {
  const QuickDownloadWindow({
    super.key,
    this.initialUrl,
    this.onDownloadCompleted,
  });

  final String? initialUrl;
  final void Function(File file, String type)? onDownloadCompleted;

  @override
  State<QuickDownloadWindow> createState() => _QuickDownloadWindowState();
}

class _QuickDownloadWindowState extends State<QuickDownloadWindow> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  bool _isAnalyzing = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadSpeed = '0 KB/s';
  String _statusMessage = '';
  String? _errorMessage;
  String? _activeTitle;

  DateTime? _lastProgressTime;
  int? _lastReceivedBytes;
  int _receivedBytes = 0;
  int? _totalBytes;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      setState(() {
        _controller.text = text;
        _errorMessage = null;
      });
    }
  }

  Future<void> _handleDownloadPressed(String type) async {
    final rawUrl = _controller.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _errorMessage = 'Lütfen geçerli bir video veya ses bağlantısı yapıştırın.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    _focusNode.unfocus();

    // 1. Premium değilse yasal AdMob onay pop-up'ını aç
    await AdmobService.instance.showRewardedAdOrBypass(
      onRewardEarned: () async {
        if (!mounted) return;
        await _executeServerDownload(rawUrl, type);
      },
    );
  }

  Future<void> _executeServerDownload(String rawUrl, String type) async {
    setState(() {
      _isAnalyzing = true;
      _isDownloading = false;
      _downloadProgress = 0.0;
      _downloadSpeed = '0 KB/s';
      _statusMessage = 'Sunucu medyayı analiz ediyor…';
      _errorMessage = null;
      _receivedBytes = 0;
      _totalBytes = null;
      _lastProgressTime = null;
      _lastReceivedBytes = null;
    });

    final notifService = DownloadNotificationService.instance;
    final notificationId = notifService.allocateNotificationId();
    final notifTitle = type == 'mp3' ? 'MP3 İndirme' : 'Video İndirme';
    int lastNotifPercent = -1;

    try {
      // 2. Linki önce api_service.dart üzerinden Python sunucumuza fırlat
      AnalyzeResult? analyzeResult;
      try {
        analyzeResult = await ApiService.instance.analyze(
          url: rawUrl,
          type: type,
        );
      } catch (serverErr) {
        debugPrint(
          'QuickDownloadWindow: Sunucu analizi yapılamadı ($serverErr), cihaz içi lokal motora geçiliyor...',
        );
      }

      if (!mounted) return;

      // DURUM A: Sunucudan temiz download_url adresi başarıyla geldi
      if (analyzeResult != null) {
        setState(() {
          _isAnalyzing = false;
          _isDownloading = true;
          _activeTitle = analyzeResult!.title;
          _statusMessage = 'İndirme başlatılıyor…';
        });

        // Telefonun üst bildirim çubuğunu başlat
        unawaited(
          notifService.showProgress(
            id: notificationId,
            title: analyzeResult.title,
            percent: null,
          ),
        );

        // İndirilecek hedef dosya yolu
        final appDir = await getApplicationDocumentsDirectory();
        final targetFileName = analyzeResult.filename;
        final savePath =
            '${appDir.path}${Platform.pathSeparator}$targetFileName';

        // Dosya indirme işlemi telefonun kendi hafızasına (Dio.download) akarken
        final downloadedFile = await ApiService.instance.downloadFile(
          downloadUrl: analyzeResult.downloadUrl,
          savePath: savePath,
          headers: analyzeResult.headers,
          onProgress: (received, total) {
            if (!mounted) return;

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
            } else {
              _lastProgressTime = now;
              _lastReceivedBytes = received;
            }

            final percent = downloadPercent(received, total);

            setState(() {
              _receivedBytes = received;
              _totalBytes = total > 0 ? total : null;
              _downloadProgress = percent != null ? percent.toDouble() : 0.0;
              _statusMessage = percent != null
                  ? '%$percent İndiriliyor…'
                  : 'İndiriliyor…';
            });

            // Üst bildirim çubuğunu canlı yüzdelerle güncelle
            if (percent != null && percent != lastNotifPercent) {
              lastNotifPercent = percent;
              unawaited(
                notifService.showProgress(
                  id: notificationId,
                  title: analyzeResult!.title,
                  percent: percent,
                  speed: _downloadSpeed,
                ),
              );
            }
          },
        );

        // Veritabanına kaydet
        int fileSize = 0;
        try {
          fileSize = downloadedFile.lengthSync();
        } catch (_) {}

        await StorageService.addItem(
          DownloadItemModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: targetFileName,
            type: type == 'mp3' ? 'audio' : 'video',
            sizeInBytes: fileSize,
            filePath: downloadedFile.path,
            downloadedAt: DateTime.now(),
            sourceUrl: rawUrl,
          ),
        );

        // İndirme bitince sesli onay bildirimi fırlatıp panel kapansın
        await notifService.showCompleted(
          id: notificationId,
          title: analyzeResult.title,
          fileName: targetFileName,
        );

        widget.onDownloadCompleted?.call(downloadedFile, type);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Başarıyla indirildi: $targetFileName'),
            backgroundColor: const Color(0xFF20B8C5),
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Panel durumunu temizle
        setState(() {
          _isDownloading = false;
          _isAnalyzing = false;
          _downloadProgress = 0.0;
          _downloadSpeed = '0 KB/s';
          _statusMessage = '';
          _controller.clear();
        });
      } else {
        // DURUM B: Sunucu kapalı veya ulaşılamazsa Cihaz İçi Motor (ClientMediaResolver) ile indir
        setState(() {
          _statusMessage = 'Cihaz içi motorla çözülüyor…';
        });

        final kind = type == 'mp3' ? DownloadKind.audio : DownloadKind.video;
        final cleanText = evrenselTemizUrl(rawUrl);
        final effectiveUri = Uri.tryParse(cleanText) ?? Uri.parse(rawUrl);

        final resolver = ClientMediaResolver();
        final media = await resolver.resolve(effectiveUri, kind);

        if (!mounted) return;

        setState(() {
          _isAnalyzing = false;
          _isDownloading = true;
          _activeTitle = media.fileName;
          _statusMessage = 'İndirme başlatılıyor…';
        });

        unawaited(
          notifService.showProgress(
            id: notificationId,
            title: media.fileName,
            percent: null,
          ),
        );

        final downloader = MediaDownloader();
        final downloadedFile = await downloader.download(
          media,
          onProgress: (received, total) {
            if (!mounted) return;

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
            } else {
              _lastProgressTime = now;
              _lastReceivedBytes = received;
            }

            final percent = downloadPercent(received, total);

            setState(() {
              _receivedBytes = received;
              _totalBytes = (total != null && total > 0) ? total : null;
              _downloadProgress = percent != null ? percent.toDouble() : 0.0;
              _statusMessage = percent != null
                  ? '%$percent İndiriliyor…'
                  : 'İndiriliyor…';
            });

            if (percent != null && percent != lastNotifPercent) {
              lastNotifPercent = percent;
              unawaited(
                notifService.showProgress(
                  id: notificationId,
                  title: media.fileName,
                  percent: percent,
                  speed: _downloadSpeed,
                ),
              );
            }
          },
        );

        final finalFileName =
            downloadedFile.path.split(Platform.pathSeparator).last;
        int fileSize = 0;
        try {
          fileSize = downloadedFile.lengthSync();
        } catch (_) {}

        await StorageService.addItem(
          DownloadItemModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: finalFileName,
            type: type == 'mp3' ? 'audio' : 'video',
            sizeInBytes: fileSize,
            filePath: downloadedFile.path,
            downloadedAt: DateTime.now(),
            sourceUrl: rawUrl,
          ),
        );

        await notifService.showCompleted(
          id: notificationId,
          title: media.fileName,
          fileName: finalFileName,
        );

        widget.onDownloadCompleted?.call(downloadedFile, type);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Başarıyla indirildi: $finalFileName'),
            backgroundColor: const Color(0xFF20B8C5),
            behavior: SnackBarBehavior.floating,
          ),
        );

        setState(() {
          _isDownloading = false;
          _isAnalyzing = false;
          _downloadProgress = 0.0;
          _downloadSpeed = '0 KB/s';
          _statusMessage = '';
          _controller.clear();
        });
      }
    } catch (e) {
      debugPrint('QuickDownloadWindow download error: $e');

      unawaited(
        notifService.showError(
          id: notificationId,
          title: notifTitle,
          error: e.toString(),
        ),
      );

      if (!mounted) return;

      setState(() {
        _isAnalyzing = false;
        _isDownloading = false;
        _errorMessage = e is ApiException ? e.message : 'Hata: $e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage ?? 'Bir hata oluştu'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2630) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Başlık
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5436).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFFFF5436),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hızlı İndirme Paneli',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: isDark ? Colors.white : const Color(0xFF172B3A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // URL Giriş Alanı
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: !_isAnalyzing && !_isDownloading,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xFF172B3A),
            ),
            decoration: InputDecoration(
              hintText: 'Video veya MP3 bağlantısı yapıştırın…',
              hintStyle: TextStyle(
                fontSize: 13.5,
                color: isDark ? Colors.white38 : const Color(0xFF9AA8B4),
              ),
              prefixIcon: const Icon(
                Icons.link_rounded,
                color: Color(0xFFFF5436),
                size: 20,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_controller.text.isNotEmpty && !_isAnalyzing && !_isDownloading)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        setState(() {
                          _controller.clear();
                          _errorMessage = null;
                        });
                      },
                    ),
                  if (!_isAnalyzing && !_isDownloading)
                    IconButton(
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      tooltip: 'Yapıştır',
                      onPressed: _pasteFromClipboard,
                    ),
                ],
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF141A22) : const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: Color(0xFFFF5436),
                  width: 1.8,
                ),
              ),
            ),
          ),

          // Hata Mesajı
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Durum 1: Sunucu Analiz Yaparken
          if (_isAnalyzing) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.8,
                      color: Color(0xFFFF5436),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ]
          // Durum 2: İndirme Sırasında Butonlar Gizlenir, LinearProgressIndicator ve Hız Paneli Gelir
          else if (_isDownloading) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141A22) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_activeTitle != null) ...[
                    Text(
                      _activeTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // LinearProgressIndicator
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress / 100 : null,
                      minHeight: 8,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF5436)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Anlık İndirme Hızı ve İlerleme Paneli
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFF5436),
                        ),
                      ),
                      Text(
                        'Hız: $_downloadSpeed',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),

                  if (_totalBytes != null && _totalBytes! > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${formatBytes(_receivedBytes)} / ${formatBytes(_totalBytes!)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ]
          // Durum 3: Normal Butonlar (Video İndir & MP3 İndir)
          else ...[
            Row(
              children: [
                // Video İndir Butonu
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: () => _handleDownloadPressed('video'),
                      icon: const Icon(Icons.videocam_rounded, size: 20),
                      label: const Text(
                        'Video İndir',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5436),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // MP3 İndir Butonu
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: () => _handleDownloadPressed('mp3'),
                      icon: const Icon(Icons.music_note_rounded, size: 20),
                      label: const Text(
                        'MP3 İndir',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF20B8C5),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Herhangi bir ekrandan hızlı indirme modal penceresini açar.
Future<void> showQuickDownloadDialog(
  BuildContext context, {
  String? initialUrl,
  void Function(File file, String type)? onDownloadCompleted,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: QuickDownloadWindow(
        initialUrl: initialUrl,
        onDownloadCompleted: (file, type) {
          Navigator.of(ctx).pop();
          onDownloadCompleted?.call(file, type);
        },
      ),
    ),
  );
}

/// VidSave sol üst köşe logo ve çekici marka tipografisi başlığı
class VidSaveBrandTitle extends StatelessWidget {
  const VidSaveBrandTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF087E8B).withValues(alpha: 0.28),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/app_icon.png',
              height: 36,
              width: 36,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Vid',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: isDark ? Colors.white : const Color(0xFF172B3A),
              ),
            ),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF087E8B), Color(0xFF20B8C5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'Save',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

