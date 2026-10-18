import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import 'auth_service.dart';
import 'main.dart';

/// VidSave İsteğe Bağlı Giriş ve Karşılama Ekranı (Welcome Screen)
///
/// Google Play Store Giriş Duvarı (Login Wall) politikasına %100 uyumludur.
/// 1. 'Google ile Devam Et' tek tıkla oturum açma mekanizması
/// 2. Sistemi bypass edip doğrudan indirme merkezine yönlendiren 'Giriş Yapmadan Ücretsiz Devam Et' butonu
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    this.homeBuilder,
    this.animate = true,
    this.authService,
    this.googleSignInClient,
  });

  final WidgetBuilder? homeBuilder;
  final bool animate;
  final AuthService? authService;
  final GoogleSignIn? googleSignInClient;

  static const String prefKeyHasSeenWelcome = 'vidsave_has_seen_welcome';

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  bool _isGoogleSigningIn = false;

  static const Color _brandColor = Color(0xFFFF5436);
  static const Color _brandDark = Color(0xFF14191F);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: widget.animate
          ? const Duration(milliseconds: 900)
          : Duration.zero,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    if (widget.animate) {
      unawaited(_animController.forward());
    } else {
      _animController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _proceedToApp({bool asGuest = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(WelcomeScreen.prefKeyHasSeenWelcome, true);
    if (!mounted) return;

    if (widget.homeBuilder != null) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) =>
              widget.homeBuilder!(context),
          transitionDuration: Duration.zero,
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (context) => const VidSaveHomePage()),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isGoogleSigningIn) return;
    setState(() => _isGoogleSigningIn = true);

    final isTurkish =
        AppLocalizations.of(context).locale.languageCode.toLowerCase() == 'tr';

    try {
      final auth = widget.authService ?? AuthService.instance;
      await auth.loginWithGoogle(
        googleSignInClient: widget.googleSignInClient,
      );
      if (!mounted) return;
      await _proceedToApp();
    } catch (error) {
      if (!mounted) return;
      if (error is AuthException && error.code == 'auth.cancelled') {
        return;
      }
      final msg = error is AuthException
          ? error.message
          : isTurkish
              ? 'Google ile giriş başarısız oldu. Lütfen tekrar deneyin.'
              : 'Google sign in failed. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isGoogleSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTurkish = l10n.locale.languageCode.toLowerCase() == 'tr';

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),

          // Logo ve Marka İkonu
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_brandColor, Color(0xFFFF7E40)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _brandColor.withValues(alpha: 0.35),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.download_rounded,
                color: Colors.white,
                size: 54,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Başlık ve Açıklama
          const Text(
            'VidSave',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isTurkish
                ? 'En sevdiğiniz video ve müzikleri yüksek kalitede cihazınıza kaydedin'
                : 'Save your favorite videos and music to your device in high quality',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF9AA8B4),
              height: 1.4,
            ),
          ),

          const Spacer(),

          // 1. BUTON: Beyaz renkli, ortasında Google logolu şık 'Google ile Devam Et' butonu
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isGoogleSigningIn ? null : _handleGoogleSignIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1F1F1F),
                elevation: 3,
                shadowColor: Colors.black.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isGoogleSigningIn
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _brandColor,
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
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. BUTON: Giriş Yapmadan Ücretsiz Devam Et (Google Play Login Wall Bypass)
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: () => _proceedToApp(asGuest: true),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                isTurkish
                    ? 'Giriş Yapmadan Ücretsiz Devam Et'
                    : 'Continue as Guest (Free)',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Yasal Politika Bilgisi
          Text(
            isTurkish
                ? 'Devam ederek Şartlar ve Gizlilik Politikamızı kabul etmiş olursunuz.'
                : 'By continuing, you agree to our Terms & Privacy Policy.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6C7C89), fontSize: 11.5),
          ),
        ],
      ),
    );

    if (widget.animate) {
      content = FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(position: _slideAnim, child: content),
      );
    }

    return Scaffold(
      backgroundColor: _brandDark,
      body: SafeArea(child: content),
    );
  }
}
