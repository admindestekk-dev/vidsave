import 'dart:convert';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import 'backend_settings.dart';

/// VidSave Premium Aylık Abonelik Ekranı
///
/// Psikolojik fiyatlandırma (9,99 TL / $0.99) ve çok dilli yapı barındırır.
/// Ödeme başarılı olduğunda confetti animasyonu oynatılır ve shared_preferences'a kaydedilir.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    this.store,
    this.httpClient,
    this.onSubscribed,
  });

  final BackendSettingsStore? store;
  final http.Client? httpClient;
  final VoidCallback? onSubscribed;

  static const String prefKeyIsPremium = 'vidsave_is_premium';
  static const String prefKeySubscribedAt = 'vidsave_premium_subscribed_at';

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late final ConfettiController _confettiController;
  bool _loading = false;
  bool _isPremiumActive = false;
  String? _receiptMessage;

  static const _accentColor = Color(0xFFFF5436);
  static const _darkBackground = Color(0xFF14191F);
  static const _cardBackground = Color(0xFF1E2630);

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _checkCurrentPremiumStatus();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentPremiumStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isPremium = prefs.getBool(SubscriptionScreen.prefKeyIsPremium) ?? false;
    if (mounted) {
      setState(() {
        _isPremiumActive = isPremium;
      });
    }
  }

  bool _isTurkish(BuildContext context) {
    try {
      final loc = Localizations.maybeLocaleOf(context);
      if (loc != null) {
        return loc.languageCode.toLowerCase() == 'tr';
      }
    } catch (_) {}
    return AppLocalizations.of(context).locale.languageCode.toLowerCase() == 'tr';
  }

  Future<void> _handleSubscribe() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _receiptMessage = null;
    });

    final isTurkish = _isTurkish(context);
    final langCode = isTurkish ? 'tr' : 'en';

    try {
      // 1. Backend settings'ten base URL'i al
      String baseUrl = BackendSettings.defaultBaseUrl;
      String apiKey = '';
      if (widget.store != null) {
        try {
          final settings = await widget.store!.load();
          if (settings.isConfigured) {
            baseUrl = settings.baseUrl;
            apiKey = settings.apiKey;
          }
        } catch (_) {}
      }

      final uri = Uri.parse(baseUrl).resolve('/api/auth/subscribe-monthly');
      final client = widget.httpClient ?? http.Client();

      final response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
            },
            body: jsonEncode({
              'lang': langCode,
              'userId': 'device_user',
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final isSuccess = response.statusCode == 200 && data['success'] == true;

      if (!isSuccess) {
        throw StateError(data['message']?.toString() ?? 'Ödeme onaylanamadı.');
      }

      final sub = data['subscription'] as Map<String, dynamic>?;
      final serverReceipt = sub?['receiptMessage']?.toString();

      final fallbackReceipt = isTurkish
          ? 'Faturanız kesildi: 9,99 TL (KDV Dahil) tahsil edilmiştir. Premium mod aktif!'
          : 'Invoice generated: \$0.99 (All taxes included) charged. Premium active!';

      final finalReceipt = (serverReceipt != null && serverReceipt.isNotEmpty)
          ? serverReceipt
          : fallbackReceipt;

      // 2. Kalıcı hafızaya kaydet
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SubscriptionScreen.prefKeyIsPremium, true);
      await prefs.setString(
        SubscriptionScreen.prefKeySubscribedAt,
        DateTime.now().toIso8601String(),
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _isPremiumActive = true;
        _receiptMessage = finalReceipt;
      });

      // 3. Konfeti patlat (3 saniye boyunca)
      _confettiController.play();

      widget.onSubscribed?.call();

      // Makbuz bildirim snackbar'ı
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(finalReceipt),
          backgroundColor: const Color(0xFF0E7C4B),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTurkish
                ? 'Abonelik işlemi tamamlanamadı: $e'
                : 'Subscription could not be completed: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTurkish = _isTurkish(context);

    // Fiyat etiketleri
    final priceTitle = isTurkish ? 'Aylık Sadece 9,99 TL' : 'Only \$0.99 / Month';
    final taxFootnote = isTurkish
        ? 'Tüm vergiler ve KDV dahildir.'
        : 'All taxes and VAT included.';
    final buttonText = isTurkish
        ? '9,99 TL / Ay - Abone Ol'
        : 'Subscribe - \$0.99 / Mo';

    return Scaffold(
      backgroundColor: _darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isTurkish ? 'VidSave Premium' : 'VidSave Premium',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Konfeti animasyon katmanı
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              emissionFrequency: 0.05,
              numberOfParticles: 35,
              gravity: 0.15,
              colors: const [
                Color(0xFFFF5436),
                Color(0xFFFFB703),
                Color(0xFF2EC4B6),
                Color(0xFFE71D36),
                Colors.white,
              ],
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  // Premium Taç İkonu & Başlık
                  Center(
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            _accentColor,
                            _accentColor.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _accentColor.withValues(alpha: 0.35),
                            blurRadius: 25,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    isTurkish
                        ? 'Sınırsız İndirme ve Hızın Keyfini Çıkarın'
                        : 'Enjoy Unlimited Downloads & Speed',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isTurkish
                        ? 'Reklamsız deneyim, 4K video ve en yüksek kaliteli MP3 dönüştürme'
                        : 'Ad-free experience, 4K video and highest quality MP3 conversion',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF9AA8B4),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Avantajlar Listesi
                  _buildFeatureRow(
                    icon: Icons.bolt_rounded,
                    title: isTurkish ? 'Maksimum İndirme Hızı' : 'Maximum Download Speed',
                    subtitle: isTurkish ? 'Bant genişliği kısıtlaması olmadan ultra hızlı' : 'Ultra-fast without bandwidth caps',
                  ),
                  _buildFeatureRow(
                    icon: Icons.high_quality_rounded,
                    title: isTurkish ? '4K & 1080p Ultra HD Video' : '4K & 1080p Ultra HD Video',
                    subtitle: isTurkish ? 'Tüm platformlardan kristal netliğinde indirin' : 'Download crystal-clear from all platforms',
                  ),
                  _buildFeatureRow(
                    icon: Icons.music_note_rounded,
                    title: isTurkish ? '320 kbps Stüdyo Kalitesinde MP3' : '320 kbps Studio Quality MP3',
                    subtitle: isTurkish ? 'Otomatik şarkı sözü ve kapak resmi gömme' : 'Automatic lyrics and cover artwork embedding',
                  ),
                  _buildFeatureRow(
                    icon: Icons.block_rounded,
                    title: isTurkish ? 'Tamamen Reklamsız' : 'Completely Ad-Free',
                    subtitle: isTurkish ? 'Kesintisiz, sade ve akıcı kullanım' : 'Seamless, clean, uninterrupted usage',
                  ),

                  const SizedBox(height: 30),

                  // Fiyatlandırma Kartı
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: _cardBackground,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _isPremiumActive
                            ? const Color(0xFF0E7C4B)
                            : _accentColor.withValues(alpha: 0.6),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (_isPremiumActive)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E7C4B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF1DB954),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isTurkish ? 'PREMIUM AKTİF' : 'PREMIUM ACTIVE',
                                  style: const TextStyle(
                                    color: Color(0xFF1DB954),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Text(
                          priceTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          taxFootnote,
                          style: const TextStyle(
                            color: Color(0xFF8B9BA7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_receiptMessage != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E7C4B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF1DB954).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.receipt_long_rounded,
                            color: Color(0xFF1DB954),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _receiptMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 26),

                  // Abone Ol Butonu
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _loading ? null : _handleSubscribe,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _accentColor.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 6,
                        shadowColor: _accentColor.withValues(alpha: 0.4),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              buttonText,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    isTurkish
                        ? 'İstediğiniz zaman iptal edebilirsiniz. Otomatik yenilenir.'
                        : 'Cancel anytime. Renews automatically.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6C7C89),
                      fontSize: 12,
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

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8B9BA7),
                    fontSize: 12.5,
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
