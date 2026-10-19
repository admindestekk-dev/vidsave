import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'backend_settings.dart';
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
        title: const Text(
          'VidSave',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              PremiumBanner(
                authService: authService,
                store: store,
                httpClient: httpClient,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
