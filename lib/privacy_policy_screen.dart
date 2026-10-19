import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'locale_service.dart';

/// VidSave Gizlilik Politikası Ekranı
///
/// Google Play Store Veri Güvenliği (Data Safety) ve Geliştirici Politikaları ile
/// %100 uyumlu, hem Türkçe hem İngilizce destekli, çevrimdışı da okunabilir
/// modern arayüz ekranı.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  static const String publicPolicyUrl =
      'https://admindestekk-dev.github.io/vidsave/privacy-policy.html';
  static const String supportEmail = 'admindestekk@gmail.com';

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  late bool _isTurkish = LocaleService.currentLanguageCode == 'tr';

  void _toggleLanguage() {
    setState(() {
      _isTurkish = !_isTurkish;
    });
  }

  Future<void> _launchWebPolicy() async {
    final uri = Uri.parse(PrivacyPolicyScreen.publicPolicyUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _launchEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: PrivacyPolicyScreen.supportEmail,
      queryParameters: {
        'subject': _isTurkish
            ? '[VidSave Gizlilik ve Destek]'
            : '[VidSave Privacy & Support]',
      },
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accentColor = Color(0xFF006673);
    final cardBg = isDark ? const Color(0xFF1E262B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2C353D) : const Color(0xFFEDF2F7);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isTurkish ? 'Gizlilik Politikası' : 'Privacy Policy',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: _toggleLanguage,
            icon: Text(_isTurkish ? '🇺🇸' : '🇹🇷', style: const TextStyle(fontSize: 16)),
            label: Text(
              _isTurkish ? 'EN' : 'TR',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: _isTurkish ? 'Web\'de Aç' : 'Open in Web',
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: _launchWebPolicy,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Üst Rozet & Bilgilendirme
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1B2A32), const Color(0xFF162128)]
                        : [const Color(0xFFE5F3F4), const Color(0xFFD6EEF1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF10B981)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_user_rounded, size: 14, color: Color(0xFF10B981)),
                              SizedBox(width: 5),
                              Text(
                                'Google Play Data Safety Compliant',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isTurkish
                          ? 'VidSave Gizlilik ve Veri Güvenliği Politikası'
                          : 'VidSave Privacy & Data Safety Policy',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isTurkish
                          ? 'Son Güncelleme: 19 Ekim 2026 · Sürüm: 1.0.0+1'
                          : 'Last Updated: October 19, 2026 · Version: 1.0.0+1',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : const Color(0xFF718096),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Politikalar Listesi
              ..._buildSections(
                context,
                isDark: isDark,
                cardBg: cardBg,
                borderColor: borderColor,
                accentColor: accentColor,
              ),

              const SizedBox(height: 20),

              // Resmi Web Sitesi & İletişim Butonları
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.mail_outline_rounded, color: accentColor, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          _isTurkish ? 'Resmi Destek ve İletişim' : 'Official Support & Contact',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isTurkish
                          ? 'Gizlilik politikamız, kişisel verileriniz veya hesap silme taleplerinizle ilgili her zaman bize ulaşabilirsiniz:'
                          : 'For any inquiries regarding our privacy policy, personal data, or account deletion, reach out to us anytime:',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : const Color(0xFF4A5568),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _launchEmail,
                      icon: const Icon(Icons.email_rounded, size: 18),
                      label: const Text(
                        PrivacyPolicyScreen.supportEmail,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _launchWebPolicy,
                      icon: const Icon(Icons.language_rounded, size: 18),
                      label: Text(
                        _isTurkish ? 'Resmi Web Sayfasında Aç' : 'Open Official Web Page',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Text(
                _isTurkish
                    ? '© 2026 VidSave. Tüm hakları saklıdır.\nGoogle Play Store Geliştirici Politikaları Uyarınca Hazırlanmıştır.'
                    : '© 2026 VidSave. All rights reserved.\nCompliant with Google Play Store Developer Policies.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? Colors.white38 : const Color(0xFFA0AEC0),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSections(
    BuildContext context, {
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color accentColor,
  }) {
    if (_isTurkish) {
      return [
        _buildPolicyCard(
          cardBg: cardBg,
          borderColor: borderColor,
          isDark: isDark,
          icon: Icons.shield_rounded,
          iconColor: const Color(0xFF10B981),
          title: '1. Giriş ve Taahhüdümüz',
          content:
              'VidSave ("biz", "uygulamamız"), kullanıcılarımızın gizliliğine ve kişisel verilerinin korunmasına en üst düzeyde önem verir. '
              'Bu politika, mobil uygulamamızı kullanırken hangi verilerin işlendiğini ve Google Play Store Veri Güvenliği (Data Safety) standartlarına '
              'nasıl tam uyum sağlandığını açıklamaktadır.\n\n'
              'Önemli Taahhüt: VidSave, kullanıcı verilerini hiçbir koşul altında üçüncü taraflara veya veri simsarlarına satmaz, kiralamaz ve pazarlamaz.',
        ),
        _buildPolicyCard(
          cardBg: cardBg,
          borderColor: borderColor,
          isDark: isDark,
          icon: Icons.account_circle_rounded,
          iconColor: const Color(0xFF3B82F6),
          title: '2. Toplanan Veriler ve Giriş Seçenekleri',
          content:
              '• Misafir Modu (Ücretsiz): VidSave, Google Play Login Wall kuralına tam uyumludur. Kullanıcılar hesap oluşturmadan uygulamayı "Giriş Yapmadan Ücretsiz Devam Et" seçeneğiyle doğrudan kullanabilir.\n\n'
              '• Google ile Giriş (İsteğe Bağlı): Kullanıcı isteğe bağlı olarak Google ile giriş yaptığında yalnızca temel profil bilgileri (Ad-Soyad, E-posta adresi, Profil Fotoğrafı) alınır. Bu bilgiler sadece kullanıcı profilini göstermek ve Aylık 9,99 TL Premium aboneliğini cihazlar arası senkronize etmek için kullanılır.',
        ),
        _buildPolicyCard(
          cardBg: cardBg,
          borderColor: borderColor,
          isDark: isDark,
          icon: Icons.folder_special_rounded,
          iconColor: const Color(0xFFF59E0B),
          title: '3. Cihaz İzinleri ve Kullanım Amaçları',
          content:
              'Uygulamamız yalnızca temel işlevleri yerine getirebilmek için minimum düzeyde izin talep eder:\n\n'
              '• Medya Kitaplığı Erişimi (READ_MEDIA_VIDEO, READ_MEDIA_AUDIO, READ_EXTERNAL_STORAGE): Cihazınızdaki mevcut videoları ve müzikleri "Videolar" ve "Müzik" sekmelerinde listelemek için kullanılır.\n\n'
              '• İndirme Kaydetme İzni (WRITE_EXTERNAL_STORAGE - Android 9 ve altı): İndirilen medya dosyalarını cihazınızın genel "Download" klasörüne ve galerinize kaydedebilmek için gereklidir.\n\n'
              '• Bildirim İzni (POST_NOTIFICATIONS): İndirme işleminin ilerleme yüzdesini canlı bildirim çubuğunda göstermek ve tamamlandığında haber vermek için kullanılır.\n\n'
              'Cihazınızdaki hiçbir fotoğraf, video veya ses dosyası sunucularımıza yüklenmez veya taranmaz.',
        ),
        _buildPolicyCard(
          cardBg: cardBg,
          borderColor: borderColor,
          isDark: isDark,
          icon: Icons.cloud_sync_rounded,
          iconColor: const Color(0xFF006673),
          title: '4. Medya İşleme ve Sıfır Kalıcı Saklama',
          content:
              'VidSave, anlık bir köprü ve medya çözümleyici olarak çalışır:\n\n'
              '• İndirilmek üzere girilen video/ses bağlantıları yalnızca talep anında akış (streaming) formatına dönüştürülür.\n'
              '• Sıfır Saklama (Zero-Retention): Sunucularımızda hiçbir video, müzik veya dosya asla kalıcı olarak depolanmaz ve arşivlenmez.\n'
              '• İndirme tamamlandığı anda dosya doğrudan sizin cihazınıza kaydedilir ve geçici akış bağlantısı kapatılır.',
        ),
        _buildPolicyCard(
          cardBg: cardBg,
          borderColor: borderColor,
          isDark: isDark,
          icon: Icons.ad_units_rounded,
          iconColor: const Color(0xFF8B5CF6),
          title: '5. Google AdMob Reklamları & Premium Filtresi',
          content:
              '• Ücretsiz / Misafir Kullanıcılar: Hizmetin sürdürülebilirliği için Google AdMob ödüllü video reklamları (Rewarded Ads) gösterilebilir. Reklam sunumu ve sahtecilik önleme amacıyla Google Play Hizmetleri tarafından anonim reklam kimliği (AAID) işlenebilir.\n\n'
              '• Premium Aboneler: Aylık abonelik satın alan kullanıcılar için AdMob reklam motoru kod mimarisinde tamamen bypass edilir (atlanır). Sıfır reklam deneyimi sunulur ve reklam verisi işlenmez.',
        ),
        _buildPolicyCard(
          cardBg: cardBg,
          borderColor: borderColor,
          isDark: isDark,
          icon: Icons.credit_card_rounded,
          iconColor: const Color(0xFFEC4899),
          title: '6. Google Play Faturalandırma & Abonelikler',
          content:
              'Premium abonelik işlemleri doğrudan resmi Google Play Billing (Google Play Faturalandırma Sistemi) üzerinden yürütülür. Kredi kartı veya finansal bilgileriniz geliştirici tarafından asla görülmez ve kaydedilmez.',
        ),
        _buildPolicyCard(
          cardBg: cardBg,
          borderColor: borderColor,
          isDark: isDark,
          icon: Icons.delete_forever_rounded,
          iconColor: Colors.redAccent,
          title: '7. Hesap ve Veri Silme Hakkı (Google Play Zorunluluğu)',
          content:
              'Google Play Store Hesap Silme Gereksinimi\'ne (Account Deletion Requirement) tam uyumluyuz:\n\n'
              'Kullanıcı Ayarlar veya Profil sayfasındaki "Hesabımı Sil" butonuna dokunduğu anda;\n'
              '• Google profil bilgileri, abonelik kayıtları, indirme geçmişi ve oturum token\'ları sunucu ve yerel veritabanından kalıcı olarak silinir.\n'
              '• Dileyen kullanıcılar admindestekk@gmail.com adresine yazarak da anında veri silme talebinde bulunabilir.',
        ),
        _buildPolicyCard(
          cardBg: cardBg,
          borderColor: borderColor,
          isDark: isDark,
          icon: Icons.child_care_rounded,
          iconColor: const Color(0xFF06B6D4),
          title: '8. Çocukların Gizliliği (COPPA)',
          content:
              'VidSave, 13 yaşın (veya bulunulan ülkedeki yasal yaş sınırının) altındaki çocuklara yönelik değildir ve bilerek çocuklardan kişisel veri toplamaz.',
        ),
        _buildPolicyCard(
          cardBg: cardBg,
          borderColor: borderColor,
          isDark: isDark,
          icon: Icons.gavel_rounded,
          iconColor: const Color(0xFF64748B),
          title: '9. Telif Hakları, Adil Kullanım ve Sorumluluk Reddi',
          content:
              'VidSave, telif hakkı ile korunan içeriklerin izinsiz indirilmesini veya çoğaltılmasını teşvik etmez. Uygulama yalnızca kişisel arşivleme, açık lisanslı içerikler ve adil kullanım (Fair Use) amacıyla tasarlanmıştır. İndirilen içeriklerin telif haklarına uygunluğundan kullanıcı sorumludur.',
        ),
      ];
    }

    // İNGİLİZCE BÖLÜMLER (EN)
    return [
      _buildPolicyCard(
        cardBg: cardBg,
        borderColor: borderColor,
        isDark: isDark,
        icon: Icons.shield_rounded,
        iconColor: const Color(0xFF10B981),
        title: '1. Introduction & Commitment',
        content:
            'VidSave ("we", "our app") is committed to protecting your privacy and personal data. '
            'This Privacy Policy explains what information is collected, how it is processed, and our full adherence '
            'to Google Play Store Developer Policies and Data Safety requirements.\n\n'
            'Strict Commitment: VidSave does NOT sell, rent, or trade user data with any third parties or data brokers under any circumstances.',
      ),
      _buildPolicyCard(
        cardBg: cardBg,
        borderColor: borderColor,
        isDark: isDark,
        icon: Icons.account_circle_rounded,
        iconColor: const Color(0xFF3B82F6),
        title: '2. Collected Data & Sign-In Options',
        content:
            '• Guest Mode (Free): VidSave strictly complies with the Google Play Login Wall policy. You may freely use the entire app without creating an account via "Continue as Guest".\n\n'
            '• Google Sign-In (Optional): If you choose to sign in with Google, only standard profile details (Name, Email, Profile Picture URL) are collected. These are solely used to display your account profile and verify your Monthly Premium subscription across devices.',
      ),
      _buildPolicyCard(
        cardBg: cardBg,
        borderColor: borderColor,
        isDark: isDark,
        icon: Icons.folder_special_rounded,
        iconColor: const Color(0xFFF59E0B),
        title: '3. Device Permissions & Purpose of Use',
        content:
            'Our app requests the bare minimum permissions necessary to function:\n\n'
            '• Media Library (READ_MEDIA_VIDEO, READ_MEDIA_AUDIO, READ_EXTERNAL_STORAGE): Used to list your local videos and audio tracks in the "Videos" and "Music" tabs.\n\n'
            '• Storage Write (WRITE_EXTERNAL_STORAGE - Android 9 & older): Required to save downloaded files directly into your public Download folder and media gallery.\n\n'
            '• Notifications (POST_NOTIFICATIONS): Used to display real-time download progress percentages in the status bar and notify upon completion.\n\n'
            'None of your personal device photos, videos, or documents are scanned or uploaded to our servers.',
      ),
      _buildPolicyCard(
        cardBg: cardBg,
        borderColor: borderColor,
        isDark: isDark,
        icon: Icons.cloud_sync_rounded,
        iconColor: const Color(0xFF006673),
        title: '4. Media Processing & Zero Permanent Storage',
        content:
            'VidSave operates as an on-the-fly streaming bridge:\n\n'
            '• Submitted URLs are resolved in real-time on demand.\n'
            '• Zero Storage Policy: No video, audio, or media file is ever permanently stored or archived on our backend servers.\n'
            '• Once streaming completes, files reside exclusively on your local device storage, and temporary buffers are purged.',
      ),
      _buildPolicyCard(
        cardBg: cardBg,
        borderColor: borderColor,
        isDark: isDark,
        icon: Icons.ad_units_rounded,
        iconColor: const Color(0xFF8B5CF6),
        title: '5. Google AdMob & Premium Ad-Free Filter',
        content:
            '• Free & Guest Users: To keep the service accessible, Google AdMob rewarded video ads may be displayed prior to downloads. Google Play Services may process anonymous Advertising IDs (AAID) for fraud prevention.\n\n'
            '• Premium Subscribers: Users with an active subscription have AdMob calls completely bypassed at the architectural level. Zero ads are shown, and no advertising telemetry is gathered.',
      ),
      _buildPolicyCard(
        cardBg: cardBg,
        borderColor: borderColor,
        isDark: isDark,
        icon: Icons.credit_card_rounded,
        iconColor: const Color(0xFFEC4899),
        title: '6. Google Play Billing & Subscriptions',
        content:
            'All in-app purchases are securely handled through the official Google Play Billing system. No credit card or financial information is ever processed or stored by the developer.',
      ),
      _buildPolicyCard(
        cardBg: cardBg,
        borderColor: borderColor,
        isDark: isDark,
        icon: Icons.delete_forever_rounded,
        iconColor: Colors.redAccent,
        title: '7. Account & Data Deletion (Google Play Compliance)',
        content:
            'We strictly abide by Google Play\'s Account Deletion Requirement:\n\n'
            'When a user taps "Delete Account" in Settings or Profile:\n'
            '• Profile information, subscription links, session tokens, and download logs are permanently purged from all databases.\n'
            '• Users may also email admindestekk@gmail.com with their Support Code to request immediate manual deletion.',
      ),
      _buildPolicyCard(
        cardBg: cardBg,
        borderColor: borderColor,
        isDark: isDark,
        icon: Icons.child_care_rounded,
        iconColor: const Color(0xFF06B6D4),
        title: '8. Children\'s Privacy (COPPA)',
        content:
            'VidSave is not directed to children under 13 years of age, and we do not knowingly collect personal information from children.',
      ),
      _buildPolicyCard(
        cardBg: cardBg,
        borderColor: borderColor,
        isDark: isDark,
        icon: Icons.gavel_rounded,
        iconColor: const Color(0xFF64748B),
        title: '9. Copyright, Fair Use & Disclaimer',
        content:
            'VidSave does not encourage or facilitate unauthorized downloading of copyrighted content. The application is built for personal archiving, open-source media, and fair use purposes. Users are strictly responsible for adhering to applicable copyright laws and platform terms of service.',
      ),
    ];
  }

  Widget _buildPolicyCard({
    required Color cardBg,
    required Color borderColor,
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF4A5568),
            ),
          ),
        ],
      ),
    );
  }
}
