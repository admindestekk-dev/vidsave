import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_localizations.dart';
import '../main.dart';

/// VidSave Profesyonel Tanıtım Rehberi (Onboarding Screen)
///
/// 3 Adımlı Geçişli PageView Mimarisi:
///   1. Adım: Linki Kopyala (Desteklenen platformlardan video/müzik linkini kopyalayın)
///   2. Adım: VidSave'e Yapıştır (VidSave linki anında algılar veya kutuya yapıştırın)
///   3. Adım: Formatı Seç ve İndir (İster 4K MP4 video ister 320kbps MP3 olarak cihazınıza kaydedin)
///
/// Tasarım Dili:
///   - Koyu Premium Arka Plan: `Color(0xFF121212)`
///   - Neon Turuncu Vurgular: `Color(0xFFFF5436)`
///   - Sayfa Noktacıkları (Dot Indicators): Seçili sayfa genişler, neon parlar
///   - Butonlar: Sağ üstte 'GEÇ / SKIP', altta dinamik 'İLERİ / BAŞLA'
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    this.onCompleted,
    this.homeBuilder,
  });

  /// Onboarding tamamlandığında (veya geçildiğinde) tetiklenecek opsiyonel callback.
  final VoidCallback? onCompleted;

  /// Özel ana sayfa builder'ı (testler veya özel yönlendirmeler için)
  final WidgetBuilder? homeBuilder;

  /// SharedPreferences anahtarı
  static const String prefKeyIsFirstTime = 'isFirstTime';

  /// Kullanıcının onboarding'i görüp görmediğini kontrol eden statik yardımcı fonksiyon.
  /// İlk kurulumda `true` döner, tamamlanınca `false` olarak kaydedilir.
  static Future<bool> checkIsFirstTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefKeyIsFirstTime) ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Onboarding'in tamamlandığını mühürler: `isFirstTime = false`
  static Future<void> markAsCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKeyIsFirstTime, false);
    } catch (e) {
      debugPrint('OnboardingScreen.markAsCompleted hatası: $e');
    }
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const Color _bgDark = Color(0xFF121212);
  static const Color _cardDark = Color(0xFF1A1A1A);
  static const Color _neonOrange = Color(0xFFFF5436);
  static const Color _neonOrangeSoft = Color(0xFFFF7E40);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    HapticFeedback.lightImpact();
    await OnboardingScreen.markAsCompleted();
    if (!mounted) return;

    if (widget.onCompleted != null) {
      widget.onCompleted!();
      return;
    }

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
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const VidSaveHomePage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  void _nextPage() {
    HapticFeedback.selectionClick();
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == 2;
    final l10n = AppLocalizations.of(context);
    final isTurkish = l10n.locale.languageCode.toLowerCase() == 'tr';

    return Scaffold(
      backgroundColor: _bgDark,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: _bgDark,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Üst Bar: Logo/Marka & GEÇ (Skip) Butonu
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Sol Üst VidSave Logo Rozeti
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _neonOrange.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _neonOrange.withValues(alpha: 0.4),
                              width: 1.2,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.bolt_rounded,
                              color: _neonOrange,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'VidSave',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),

                    // Sağ Üst 'GEÇ' Butonu (Son sayfada kaybolur)
                    AnimatedOpacity(
                      opacity: isLastPage ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: isLastPage,
                        child: TextButton(
                          key: const Key('onboarding_skip_button'),
                          onPressed: _finishOnboarding,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white60,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                          child: Text(
                            isTurkish ? 'GEÇ' : 'SKIP',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Orta Alan: 3 Sayfalık PageView
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  children: [
                    // 1. Adım: Linki Kopyala
                    _buildStepPage(
                      stepNumber: '1',
                      icon: Icons.link_rounded,
                      badgeText: isTurkish ? 'ADIM 1' : 'STEP 1',
                      title: isTurkish ? 'Linki Kopyala' : 'Copy the Link',
                      description: isTurkish
                          ? 'Instagram, TikTok, YouTube veya diğer platformlarda beğendiğin videonun paylaşım bağlantısını panoya kopyala.'
                          : 'Copy the share link of the video or music you want to download from Instagram, TikTok, YouTube or other platforms.',
                      illustration: _buildStepIllustration1(),
                    ),

                    // 2. Adım: VidSave'e Yapıştır
                    _buildStepPage(
                      stepNumber: '2',
                      icon: Icons.content_paste_rounded,
                      badgeText: isTurkish ? 'ADIM 2' : 'STEP 2',
                      title: isTurkish
                          ? 'VidSave\'e Yapıştır'
                          : 'Paste to VidSave',
                      description: isTurkish
                          ? 'VidSave kopyaladığın bağlantıyı anında otomatik algılar veya hızlı indirme kutusuna doğrudan yapıştırabilirsin.'
                          : 'VidSave automatically detects copied links or you can simply paste the URL into the quick download field.',
                      illustration: _buildStepIllustration2(),
                    ),

                    // 3. Adım: Formatı Seç ve İndir
                    _buildStepPage(
                      stepNumber: '3',
                      icon: Icons.download_done_rounded,
                      badgeText: isTurkish ? 'ADIM 3' : 'STEP 3',
                      title: isTurkish
                          ? 'Formatı Seç ve İndir'
                          : 'Select Format & Download',
                      description: isTurkish
                          ? 'İster 4K / HD Video ister 320 kbps stüdyo kalitesinde MP3 ses olarak yüksek hızda cihazına tek dokunuşla kaydet!'
                          : 'Save as 4K / HD Video or 320 kbps studio-grade MP3 audio with blazing fast speed at a single tap!',
                      illustration: _buildStepIllustration3(),
                    ),
                  ],
                ),
              ),

              // Alt Alan: Dot Indicators & İLERİ / BAŞLA Butonu
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Noktacıklar (Dots)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) {
                        final isSelected = _currentPage == index;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 8,
                          width: isSelected ? 28 : 8,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _neonOrange
                                : Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: _neonOrange.withValues(
                                        alpha: 0.45,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),

                    // Ana Aksiyon Butonu: İLERİ / BAŞLA
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [_neonOrange, _neonOrangeSoft],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _neonOrange.withValues(alpha: 0.4),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          key: const Key('onboarding_action_button'),
                          onPressed: _nextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isLastPage
                                    ? (isTurkish ? 'BAŞLA' : 'GET STARTED')
                                    : (isTurkish ? 'İLERİ' : 'NEXT'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                isLastPage
                                    ? Icons.rocket_launch_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 20,
                              ),
                            ],
                          ),
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
    );
  }

  /// Her bir adım sayfasının gövdesi
  Widget _buildStepPage({
    required String stepNumber,
    required IconData icon,
    required String badgeText,
    required String title,
    required String description,
    required Widget illustration,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Özel Görsel / Animasyon İllüstrasyonu
          Expanded(child: Center(child: illustration)),
          const SizedBox(height: 12),

          // Adım Rozeti
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _neonOrange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _neonOrange.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: _neonOrange),
                const SizedBox(width: 6),
                Text(
                  badgeText,
                  style: const TextStyle(
                    color: _neonOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Başlık
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),

          // Açıklama
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9AA8B4),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 1. Adım İllüstrasyonu: Link kopyalama simülasyonu
  Widget _buildStepIllustration1() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 220),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Parlayan Daire ve Link İkonu
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _neonOrange.withValues(alpha: 0.16),
              border: Border.all(
                color: _neonOrange.withValues(alpha: 0.4),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _neonOrange.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.share_rounded,
              size: 38,
              color: _neonOrange,
            ),
          ),
          const SizedBox(height: 20),
          // Link Kopyalandı Bildirimi Simülasyonu
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: Color(0xFF20B8C5),
                ),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'https://... kopyalandı',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 2. Adım İllüstrasyonu: VidSave otomatik algılama & yapıştırma
  Widget _buildStepIllustration2() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 220),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _neonOrange.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: _neonOrange.withValues(alpha: 0.15),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // VidSave Otomatik Algılama Kutusu
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _neonOrange.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bolt_rounded, color: _neonOrange, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'VidSave Algıladı! ✨',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.auto_awesome_rounded, color: _neonOrange, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Hızlı Önizleme Çubuğu
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: Colors.white.withValues(alpha: 0.05),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.movie_rounded,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Medya analiz ediliyor…',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 3. Adım İllüstrasyonu: Video & MP3 indirme butonları
  Widget _buildStepIllustration3() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 220),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Video İndir Butonu (Turuncu)
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _neonOrange,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _neonOrange.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Video İndir (4K / HD)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // MP3 İndir Butonu (Turkuaz)
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF20B8C5),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF20B8C5).withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.music_note_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'MP3 İndir (320 kbps)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
