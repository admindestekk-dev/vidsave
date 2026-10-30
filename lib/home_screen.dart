import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admob_service.dart';
import 'download_exception_handler.dart';
import 'auth_service.dart';
import 'backend_settings.dart';
import 'media_downloader.dart';
import 'subscription_screen.dart';
import 'downloads_screen.dart';
import 'services/api_service.dart';
import 'services/unified_download_engine.dart';
import 'app_localizations.dart';
import 'l10n/l10n_extension.dart';

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
            context.tr('sign_in_pro_title'),
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
            context.tr('sign_in_pro_desc'),
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
                          context.tr('continue_with_google'),
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
              context.tr('maybe_later'),
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
                      Text(
                        _isPremium
                            ? context.tr('vidsave_pro_active')
                            : context.tr('activate_pro_version'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _isPremium
                            ? context.tr('pro_banner_sub_active')
                            : context.tr('pro_banner_sub_inactive'),
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
                        ? context.tr('btn_manage')
                        : context.tr('btn_get'),
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
class HomeScreen extends StatefulWidget {
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
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
                authService: widget.authService,
                store: widget.store,
                httpClient: widget.httpClient,
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
    this.onPreviewResolved,
  });

  final String? initialUrl;
  final void Function(File file, String type)? onDownloadCompleted;
  final void Function(String? title, String? thumbnail, int? duration)? onPreviewResolved;

  @override
  State<QuickDownloadWindow> createState() => _QuickDownloadWindowState();
}

class _QuickDownloadWindowState extends State<QuickDownloadWindow> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  // 1. Dinamik Değişken Tesisatı: Sunucudan dönecek verileri tutar
  String? _videoTitle;
  String? _videoThumbnail;
  int? _videoDuration;

  bool _isAnalyzing = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadSpeed = '0 KB/s';
  String _statusMessage = '';
  String? _errorMessage;
  String? _activeTitle;

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

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final remainingSeconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$remainingSeconds';
    }
    return '$minutes:$remainingSeconds';
  }

  Future<void> _handleDownloadPressed(String type) async {
    final rawUrl = _controller.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _errorMessage = context.tr('quick_download_empty_url');
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
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isAnalyzing = true;
      _isDownloading = false;
      _downloadProgress = 0.0;
      _downloadSpeed = '0 KB/s';
      _statusMessage = l10n.text('quick_download_fetching_info');
      _errorMessage = null;
      _receivedBytes = 0;
      _totalBytes = null;
    });

    // 2. API Veri Eşitlemesi: Sunucumuzdan /api/analyze ile title, thumbnail ve duration verilerini çek ve eşitle
    final normalizedType = (type.toLowerCase() == 'mp3' || type.toLowerCase() == 'audio') ? 'mp3' : 'video';
    try {
      final analyzeResult = await ApiService.instance.analyze(
        url: rawUrl,
        type: normalizedType,
      );

      if (mounted) {
        setState(() {
          _videoTitle = analyzeResult.title.isNotEmpty ? analyzeResult.title : null;
          _videoThumbnail = (analyzeResult.thumbnail != null && analyzeResult.thumbnail!.isNotEmpty)
              ? analyzeResult.thumbnail
              : null;
          _videoDuration = analyzeResult.duration;
          _activeTitle = _videoTitle;
        });
        widget.onPreviewResolved?.call(_videoTitle, _videoThumbnail, _videoDuration);
      }
    } catch (analyzeErr) {
      debugPrint('QuickDownloadWindow analiz ön denemesi: $analyzeErr');
    }

    if (!mounted) return;

    setState(() {
      _isAnalyzing = false;
      _isDownloading = true;
      _statusMessage = (normalizedType == 'mp3')
          ? l10n.text('quick_download_downloading_audio')
          : l10n.text('quick_download_downloading_video');
    });

    try {
      final downloadedFile = await UnifiedDownloadEngine.instance.download(
        rawUrl: rawUrl,
        type: type,
        preferredTitle: _videoTitle,
        onProgress: (received, total, progress, speed, status) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            _downloadProgress =
                progress != null ? (progress * 100).clamp(0.0, 100.0) : 0.0;
            _downloadSpeed = speed;
            _statusMessage = status;
          });
        },
      );

      final targetFileName =
          downloadedFile.path.split(Platform.pathSeparator).last;
      widget.onDownloadCompleted?.call(downloadedFile, type);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('quick_download_success')}$targetFileName'),
          backgroundColor: const Color(0xFF20B8C5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'GÖRÜNTÜLE',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const DownloadsScreen(),
                ),
              );
            },
          ),
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
    } catch (e) {
      debugPrint('QuickDownloadWindow download error: $e');

      if (!mounted) return;

      final errorMsg = DownloadExceptionHandler.getFriendlyMessage(e, context);

      setState(() {
        _isAnalyzing = false;
        _isDownloading = false;
        _errorMessage = errorMsg;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage ?? context.tr('quick_download_error')),
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
                  context.tr('quick_download_title'),
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
              hintText: context.tr('quick_download_hint'),
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
                      tooltip: context.tr('btn_paste'),
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

          // 3. Şık Önizleme Kartı Tasarımı (Media Preview Card)
          if (_videoThumbnail != null) ...[
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF5436).withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Kapak Resmi ve Üzerindeki Video Süresi Rozeti
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            _videoThumbnail!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Icon(
                                  Icons.movie_rounded,
                                  color: Colors.white38,
                                  size: 42,
                                ),
                              ),
                            ),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: Colors.black45,
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFFFF5436),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Sağ altta şık video süresi rozeti
                        if (_videoDuration != null && _videoDuration! > 0)
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.timer_outlined,
                                    color: Colors.white70,
                                    size: 11,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _formatDuration(_videoDuration!),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    // Başlık ve Turuncu İlerleme Çubuğu Bölümü
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_videoTitle != null && _videoTitle!.isNotEmpty) ...[
                            Text(
                              _videoTitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          // Hemen altında parlayan turuncu ilerleme çubuğu
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _downloadProgress > 0
                                  ? (_downloadProgress / 100).clamp(0.0, 1.0)
                                  : (_isDownloading ? null : 0.0),
                              minHeight: 6,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFFF5436),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // İndirme Sırasında Butonlar Gizlenir, Şık ve Parlayan Turuncu LinearProgressIndicator Odaklanır
          if (_isDownloading) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141A22) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF5436).withValues(alpha: 0.25),
                  width: 1.2,
                ),
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
                    const SizedBox(height: 12),
                  ],

                  // Şık, Parlayan Turuncu LinearProgressIndicator (Glow Shadow)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF5436).withValues(alpha: 0.45),
                          blurRadius: 10,
                          spreadRadius: 1,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _downloadProgress > 0 ? _downloadProgress / 100 : null,
                        minHeight: 10,
                        backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF5436)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Canlı İlerleme ve İndirme Hızı
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _downloadProgress > 0
                            ? '%${_downloadProgress.toStringAsFixed(0)} İndiriliyor…'
                            : (_statusMessage.isNotEmpty ? _statusMessage : 'İndiriliyor…'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFF5436),
                        ),
                      ),
                      Text(
                        '${context.tr('quick_download_speed')}$_downloadSpeed',
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
          // Normal Butonlar (Video İndir & MP3 İndir)
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
                      label: Text(
                        context.tr('download_video_btn'),
                        style: const TextStyle(
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
                      label: Text(
                        context.tr('download_audio_btn'),
                        style: const TextStyle(
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

