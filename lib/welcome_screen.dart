import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import 'auth_service.dart';
import 'main.dart';

/// VidSave İsteğe Bağlı Giriş ve Karşılama Ekranı (Welcome Screen)
///
/// Google Play Store Giriş Duvarı (Login Wall) politikasına %100 uyumludur.
/// Kullanıcılara zorunlu üyelik dayatılmaz:
/// 1. E-posta / Şifre ile 'Giriş Yap / Üye Ol' butonu
/// 2. Sistemi bypass edip doğrudan indirme merkezine yönlendiren 'Giriş Yapmadan Ücretsiz Devam Et' butonu
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    this.homeBuilder,
    this.animate = true,
    this.authService,
  });

  final WidgetBuilder? homeBuilder;
  final bool animate;
  final AuthService? authService;

  static const String prefKeyHasSeenWelcome = 'vidsave_has_seen_welcome';

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

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

  void _showAuthModal() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final isTurkish =
        AppLocalizations.of(context).locale.languageCode.toLowerCase() == 'tr';
    bool isRegister = false;
    bool isSubmitting = false;
    bool obscurePassword = true;
    String? errorMessage;

    Future<void> showAuthSheet() async {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (modalContext, setModalState) {
              final bottomInset = MediaQuery.of(modalContext).viewInsets.bottom;
              Future<void> submit() async {
                if (isSubmitting) return;
                final email = emailController.text.trim();
                final password = passwordController.text;
                if (email.isEmpty || password.isEmpty) {
                  setModalState(() {
                    errorMessage = isTurkish
                        ? 'E-posta ve şifre alanlarını doldurun.'
                        : 'Enter your email and password.';
                  });
                  return;
                }

                setModalState(() {
                  isSubmitting = true;
                  errorMessage = null;
                });
                try {
                  final service = widget.authService ?? AuthService.instance;
                  if (isRegister) {
                    await service.register(email: email, password: password);
                  } else {
                    await service.login(email: email, password: password);
                  }
                  if (!modalContext.mounted) return;
                  Navigator.of(modalContext).pop();
                  await _proceedToApp();
                } catch (error) {
                  if (!modalContext.mounted) return;
                  setModalState(() {
                    errorMessage = error is AuthException
                        ? error.message
                        : isTurkish
                        ? 'Bağlantı kurulamadı. Lütfen tekrar deneyin.'
                        : 'Could not connect. Please try again.';
                  });
                } finally {
                  if (modalContext.mounted) {
                    setModalState(() => isSubmitting = false);
                  }
                }
              }

              InputDecoration fieldDecoration(String label, IconData icon) {
                return InputDecoration(
                  labelText: label,
                  prefixIcon: Icon(icon, color: _brandColor),
                  filled: true,
                  fillColor: const Color(0xFFF6F8F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                );
              }

              return Container(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        isRegister
                            ? (isTurkish
                                  ? 'Üye Ol / Kayıt Ol'
                                  : 'Create account')
                            : (isTurkish
                                  ? 'Hesabınıza Giriş Yapın'
                                  : 'Sign in'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF172B3A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isRegister
                            ? (isTurkish
                                  ? 'İndirmelerinizi ve tercihlerinizi senkronize edin'
                                  : 'Sync your downloads and preferences')
                            : (isTurkish
                                  ? 'Kayıtlı oturumunuzu açarak devam edin'
                                  : 'Sign in to continue'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF87949D),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: emailController,
                        enabled: !isSubmitting,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: fieldDecoration(
                          isTurkish ? 'E-posta Adresi' : 'Email address',
                          Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: passwordController,
                        enabled: !isSubmitting,
                        obscureText: obscurePassword,
                        maxLength: 128,
                        textInputAction: TextInputAction.done,
                        autofillHints: [
                          isRegister
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        onSubmitted: (_) => submit(),
                        decoration:
                            fieldDecoration(
                              isTurkish ? 'Şifre' : 'Password',
                              Icons.lock_outline_rounded,
                            ).copyWith(
                              counterText: '',
                              suffixIcon: IconButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () => setModalState(
                                        () =>
                                            obscurePassword = !obscurePassword,
                                      ),
                                tooltip: obscurePassword
                                    ? (isTurkish
                                          ? 'Şifreyi göster'
                                          : 'Show password')
                                    : (isTurkish
                                          ? 'Şifreyi gizle'
                                          : 'Hide password'),
                                icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: isSubmitting ? null : submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: _brandColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  isRegister
                                      ? (isTurkish
                                            ? 'Kayıt Ol ve Başla'
                                            : 'Create account')
                                      : (isTurkish
                                            ? 'Giriş Yap ve Başla'
                                            : 'Sign in'),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: isSubmitting
                            ? null
                            : () => setModalState(() {
                                isRegister = !isRegister;
                                errorMessage = null;
                              }),
                        child: Text(
                          isRegister
                              ? (isTurkish
                                    ? 'Zaten hesabınız var mı? Giriş Yapın'
                                    : 'Already have an account? Sign in')
                              : (isTurkish
                                    ? 'Hesabınız yok mu? Hemen Üye Olun'
                                    : 'No account? Create one'),
                          style: const TextStyle(
                            color: _brandColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      emailController.dispose();
      passwordController.dispose();
    }

    unawaited(showAuthSheet());
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

          // 1. BUTON: E-posta/Şifre ile Giriş Yap / Üye Ol
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _showAuthModal,
              style: FilledButton.styleFrom(
                backgroundColor: _brandColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: _brandColor.withValues(alpha: 0.4),
              ),
              icon: const Icon(Icons.login_rounded, size: 20),
              label: Text(
                isTurkish ? 'Giriş Yap / Üye Ol' : 'Sign In / Register',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
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
