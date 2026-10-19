import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'backend_media_resolver.dart';
import 'backend_settings.dart';
import 'locale_service.dart';
import 'media_downloader.dart';
import 'profile_screen.dart';
import 'storage_service.dart';
import 'subscription_screen.dart';
import 'home_screen.dart';
import 'theme_service.dart';
import 'user_identity_service.dart';
import 'welcome_screen.dart';

/// "Ayarlar" sekmesi.
///
/// Normal kullanıcı yalnızca dil, tema ve hakkında seçeneklerini görür.
/// Başlığa arka arkaya 5 kez dokunulduğunda gizli geliştirici bölümü açılır ve
/// backend bağlantı ayarları görünür hâle gelir.
class MoreScreen extends StatefulWidget {
  const MoreScreen({
    super.key,
    required this.store,
    required this.resolver,
    this.authService,
  });

  final BackendSettingsStore store;
  final BackendMediaResolver resolver;
  final AuthService? authService;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  static const _accent = Color(0xFF006673);

  AuthService get _authService => widget.authService ?? AuthService.instance;
  late Future<bool> _hasStoredSession = _authService.hasStoredSession;

  /// Kaç kez başlığa dokunulduğunu sayar.
  int _clickCount = 0;

  /// Gizli geliştirici bölümünün açık olup olmadığı.
  bool _isDeveloperModeActive = false;

  void _handleTitleTap() {
    if (_isDeveloperModeActive) return;
    setState(() {
      _clickCount++;
      // Üst üste 5 kez dokunulunca gizli ayarlar açılır.
      if (_clickCount >= 5) {
        _isDeveloperModeActive = true;
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    });
  }

  void _closeDeveloperMode() {
    setState(() {
      _clickCount = 0;
      _isDeveloperModeActive = false;
    });
  }

  String _getLanguageSubtitle(String code) {
    switch (code) {
      case 'tr':
        return '🇹🇷 Türkçe';
      case 'en':
        return '🇺🇸 English';
      case 'es':
        return '🇪🇸 Español';
      case 'de':
        return '🇩🇪 Deutsch';
      case 'fr':
        return '🇫🇷 Français';
      case 'ru':
        return '🇷🇺 Русский';
      case 'ar':
        return '🇸🇦 العربية';
      case 'zh':
        return '🇨🇳 简体中文';
      default:
        return '🇺🇸 English';
    }
  }

  void _showLanguageDialog() {
    final currentCode = LocaleService.currentLanguageCode;

    final languages = [
      {'code': 'tr', 'flag': '🇹🇷', 'name': 'Türkçe', 'native': 'Türkçe'},
      {'code': 'en', 'flag': '🇺🇸', 'name': 'English', 'native': 'English'},
      {'code': 'es', 'flag': '🇪🇸', 'name': 'Spanish', 'native': 'Español'},
      {'code': 'de', 'flag': '🇩🇪', 'name': 'German', 'native': 'Deutsch'},
      {'code': 'fr', 'flag': '🇫🇷', 'name': 'French', 'native': 'Français'},
      {'code': 'ru', 'flag': '🇷🇺', 'name': 'Russian', 'native': 'Русский'},
      {'code': 'ar', 'flag': '🇸🇦', 'name': 'Arabic', 'native': 'العربية'},
      {'code': 'zh', 'flag': '🇨🇳', 'name': 'Chinese', 'native': '简体中文'},
    ];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.language_rounded,
                          color: _accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Dil Seçimi / Language',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // Dikey olarak kaydırılabilen 8 Dilli Liste
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: languages.map((lang) {
                        final code = lang['code']!;
                        final flag = lang['flag']!;
                        final name = lang['name']!;
                        final native = lang['native']!;
                        final isSelected = currentCode == code;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: Text(flag, style: const TextStyle(fontSize: 26)),
                            title: Text(
                              native,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(name),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: _accent)
                                : null,
                            onTap: () async {
                              await LocaleService.setLocale(Locale(code));
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık — gizli geliştirici modu buraya bağlı.
              GestureDetector(
                onTap: _handleTitleTap,
                behavior: HitTestBehavior.opaque,
                child: const Text(
                  'VidSave',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),

              // =============================================================
              // 1. HERKESİN GÖRDÜĞÜ NORMAL AYARLAR
              // =============================================================
              const Text(
                'Uygulama Ayarları',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),

              // PREMIUM ABONELİK KARTI
              Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF5436), Color(0xFFFF7E40)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF5436).withValues(alpha: 0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      handlePremiumClick(
                        context,
                        authService: _authService,
                        store: widget.store,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.workspace_premium_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Premium Abonelik',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Sınırsız hız, 4K indirme ve reklamsız deneyim',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              FutureBuilder<bool>(
                future: _hasStoredSession,
                builder: (context, snapshot) {
                  if (snapshot.data != true) return const SizedBox.shrink();
                  return Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.account_circle_outlined,
                          color: _accent,
                        ),
                        title: const Text('Profilim ve Hesap'),
                        subtitle: const Text('Google hesabı ve üyelik bilgileri'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.logout_rounded, size: 20),
                              tooltip: 'Çıkış Yap',
                              onPressed: _logout,
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ProfileScreen(
                                authService: _authService,
                                onLoggedOut: () {
                                  setState(() {
                                    _hasStoredSession = _authService.hasStoredSession;
                                  });
                                },
                              ),
                            ),
                          ).then((_) {
                            if (mounted) {
                              setState(() {
                                _hasStoredSession = _authService.hasStoredSession;
                              });
                            }
                          });
                        },
                      ),
                      const Divider(),
                    ],
                  );
                },
              ),
              ValueListenableBuilder<Locale?>(
                valueListenable: LocaleService.localeNotifier,
                builder: (context, currentLocale, _) {
                  final code =
                      (currentLocale?.languageCode.toLowerCase() ?? 'tr');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.language, color: _accent),
                    title: const Text('Dil Seçimi / Language'),
                    subtitle: Text(_getLanguageSubtitle(code)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _showLanguageDialog,
                  );
                },
              ),
              const Divider(),

              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeService.themeModeNotifier,
                builder: (context, mode, _) {
                  final isDark = mode == ThemeMode.dark;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      color: ThemeService.primaryColor,
                    ),
                    title: const Text('Koyu Tema'),
                    subtitle: Text(
                      isDark ? 'Açık (Karanlık Mod)' : 'Kapalı (Aydınlık Mod)',
                    ),
                    trailing: Switch(
                      value: isDark,
                      activeThumbColor: Colors.white,
                      activeTrackColor: ThemeService.primaryColor,
                      onChanged: (value) async {
                        await ThemeService.setDarkMode(value);
                      },
                    ),
                  );
                },
              ),
              const Divider(),

              // =============================================================
              // DESTEK VE İLETİŞİM (SUPPORT & CONTACT)
              // =============================================================
              FutureBuilder<String>(
                future: _getEffectiveUserId(),
                builder: (context, snapshot) {
                  final userId = snapshot.data ?? '…';
                  final isTr = LocaleService.currentLanguageCode == 'tr';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. ListTile: Destek Kodu (User ID) ve Panoya Kopyalama
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fingerprint_rounded,
                            color: _accent,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          isTr ? 'Destek Kodu (User ID)' : 'Support Code (User ID)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          userId,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: _accent,
                        ),
                        onTap: () => _copyUserIdToClipboard(userId, isTr),
                      ),
                      const Divider(),

                      // 2. ListTile: E-posta İletişim Butonu (mailto)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.mail_outline_rounded,
                            color: Colors.orange,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          isTr
                              ? 'Bize Ulaşın / Destek Alın'
                              : 'Contact Us / Get Support',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          supportEmail,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: Colors.grey,
                        ),
                        onTap: () => _launchSupportEmail(userId, isTr),
                      ),
                    ],
                  );
                },
              ),
              const Divider(),

              // =============================================================
              // GOOGLE PLAY YASAL ZORUNLULUĞU: HESABIMI SİL (DELETE ACCOUNT)
              // =============================================================
              // =============================================================
              // DİĞERLERİ (OTHERS) - 4 MODERN KART
              // =============================================================
              const SizedBox(height: 24),
              _buildSectionHeader(
                context,
                title: LocaleService.currentLanguageCode == 'tr'
                    ? 'Diğerleri'
                    : 'Others',
              ),
              const SizedBox(height: 12),
              _buildModernMenuCard(
                context,
                icon: Icons.star_rounded,
                iconColor: const Color(0xFFF59E0B),
                iconBgColor: const Color(0xFFFEF3C7),
                title: LocaleService.currentLanguageCode == 'tr'
                    ? 'Bizi Değerlendirin'
                    : 'Rate Us',
                subtitle: LocaleService.currentLanguageCode == 'tr'
                    ? 'Google Play Store\'da 5 yıldız vererek bize destek olun'
                    : 'Support us with 5 stars on Google Play Store',
                onTap: _rateApp,
              ),
              const SizedBox(height: 10),
              _buildModernMenuCard(
                context,
                icon: Icons.share_rounded,
                iconColor: const Color(0xFF3B82F6),
                iconBgColor: const Color(0xFFDBEAFE),
                title: LocaleService.currentLanguageCode == 'tr'
                    ? 'Uygulamayı Paylaş'
                    : 'Share App',
                subtitle: LocaleService.currentLanguageCode == 'tr'
                    ? 'VidSave\'i arkadaşlarınızla ve ailenizle paylaşın'
                    : 'Share VidSave with friends and family',
                onTap: _shareApp,
              ),
              const SizedBox(height: 10),
              _buildModernMenuCard(
                context,
                icon: Icons.shield_rounded,
                iconColor: const Color(0xFF10B981),
                iconBgColor: const Color(0xFFD1FAE5),
                title: LocaleService.currentLanguageCode == 'tr'
                    ? 'Gizlilik Politikası'
                    : 'Privacy Policy',
                subtitle: LocaleService.currentLanguageCode == 'tr'
                    ? 'Veri güvenliği ve kullanım şartlarını inceleyin'
                    : 'Review data privacy and terms of service',
                onTap: _openPrivacyPolicy,
              ),
              const SizedBox(height: 10),
              _buildModernMenuCard(
                context,
                icon: Icons.lock_outline_rounded,
                iconColor: const Color(0xFF8B5CF6),
                iconBgColor: const Color(0xFFEDE9FE),
                title: LocaleService.currentLanguageCode == 'tr'
                    ? 'Sorumluluk Reddi'
                    : 'Disclaimer',
                subtitle: LocaleService.currentLanguageCode == 'tr'
                    ? 'Telif hakları ve yasal kullanım bildirimi'
                    : 'Copyrights and legal disclaimer',
                onTap: () => _showDisclaimerDialog(context),
              ),
              const SizedBox(height: 16),
              const Divider(),

              // =============================================================
              // GOOGLE PLAY YASAL ZORUNLULUĞU: HESABIMI SİL (DELETE ACCOUNT)
              // =============================================================
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.shade50,
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Hesabımı Sil',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.redAccent,
                  ),
                ),
                subtitle: const Text(
                  'Hesabınızı, indirme geçmişinizi ve tüm kayıtlarınızı kalıcı olarak silin.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.redAccent,
                ),
                onTap: () => _confirmDeleteAccount(context),
              ),
              const Divider(),

              // =============================================================
              // 2. GİZLİ TEKNİK AYARLAR (yalnızca 5 dokunuştan sonra görünür)
              // =============================================================
              if (_isDeveloperModeActive) ...[
                const SizedBox(height: 30),
                Row(
                  children: [
                    const Icon(Icons.build_outlined, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    const Text(
                      'Geliştirici Bölümü',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _closeDeveloperMode,
                      child: const Text('Kapat'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Gerçek backend ayar formu buraya gömülür.
                BackendSettingsPanel(
                  store: widget.store,
                  resolver: widget.resolver,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await _authService.logout();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Çıkış yapılamadı. Lütfen tekrar deneyin.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Hesabımı Sil'),
          ],
        ),
        content: const Text(
          'Hesabınızı ve tüm indirme geçmişinizi kalıcı olarak silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await _executeDeleteAccount();
            },
            child: const Text('Evet, Kalıcı Olarak Sil'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeDeleteAccount() async {
    try {
      final guestUserId = await UserIdentityService.getOrCreateUserId();
      await _authService.deleteAccount(guestUserId: guestUserId);

      await StorageService.clearAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(SubscriptionScreen.prefKeyIsPremium);
      await prefs.remove(SubscriptionScreen.prefKeySubscribedAt);
      await prefs.remove(WelcomeScreen.prefKeyHasSeenWelcome);
      await UserIdentityService.clearUserId();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      final isTurkish = LocaleService.currentLanguageCode == 'tr';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTurkish
                ? 'Hesap silinemedi. Bağlantınızı kontrol edip tekrar deneyin.'
                : 'Account deletion failed. Check your connection and try again.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  static const String supportEmail = 'admindestekk@gmail.com';

  /// Kullanıcının benzersiz Destek Kodunu (User ID) dinamik olarak çeker
  Future<String> _getEffectiveUserId() async {
    try {
      final token = await _authService.hasStoredSession;
      if (token) {
        final userId = await _authService.storedUserId;
        if (userId != null && userId.trim().isNotEmpty) {
          return userId.trim();
        }
      }
    } catch (_) {}

    // Misafir veya ücretsiz modda cihaz kimliğine özel kimlik
    try {
      final guestId = await UserIdentityService.getOrCreateUserId();
      if (guestId.isNotEmpty) {
        return guestId;
      }
    } catch (_) {}

    return 'Misafir Kullanıcı (Giriş Yapılmadı)';
  }

  /// Destek kodunu panoya kopyalar ve kullanıcıya SnackBar bildirimi gösterir
  Future<void> _copyUserIdToClipboard(String userId, bool isTurkish) async {
    await Clipboard.setData(ClipboardData(text: userId));
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isTurkish
                    ? 'Destek kodu panoya kopyalandı!'
                    : 'Support code copied to clipboard!',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0E7C4B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// E-posta uygulamasını otomatik açarak [VidSave Destek - ID: UserID] konusuyla hazır mail taslağı oluşturur
  Future<void> _launchSupportEmail(String userId, bool isTurkish) async {
    final subject = '[VidSave Destek - ID: $userId]';
    final body = isTurkish
        ? 'Merhaba VidSave Destek Ekibi,\n\nKullanıcı ID / Destek Kodu: $userId\n\nYaşadığım sorun / Geri bildirimim:\n'
        : 'Hello VidSave Support Team,\n\nUser ID / Support Code: $userId\n\nIssue / Feedback:\n';

    final emailLaunchUri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    try {
      final launched = await launchUrl(
        emailLaunchUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        // Fallback: E-posta istemcisi bulunamazsa adresi panoya kopyala ve bildir
        await Clipboard.setData(const ClipboardData(text: supportEmail));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isTurkish
                  ? 'E-posta uygulaması açılamadı. $supportEmail adresi panoya kopyalandı.'
                  : 'Could not open mail app. $supportEmail copied to clipboard.',
            ),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: supportEmail));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTurkish
                ? '$supportEmail adresi panoya kopyalandı.'
                : '$supportEmail copied to clipboard.',
          ),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // =============================================================
  // DİĞERLERİ BÖLÜMÜ YARDIMCI WIDGET'LARI VE METODLARI
  // =============================================================

  Widget _buildSectionHeader(BuildContext context, {required String title}) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildModernMenuCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E262B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2C353D) : const Color(0xFFEDF2F7);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : const Color(0xFF718096),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: isDark ? Colors.white38 : const Color(0xFFA0AEC0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 1. Bizi Değerlendirin: in_app_review ile Google Play Store puanı & yorumu
  Future<void> _rateApp() async {
    try {
      final InAppReview inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
      } else {
        await inAppReview.openStoreListing(
          appStoreId: 'com.example.vid_downloader_app',
        );
      }
    } catch (_) {
      final fallbackUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=com.example.vid_downloader_app',
      );
      try {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  /// 2. Uygulamayı Paylaş: share_plus ile sistem paylaşım menüsü
  Future<void> _shareApp() async {
    final isTr = LocaleService.currentLanguageCode == 'tr';
    const playStoreLink =
        'https://play.google.com/store/apps/details?id=com.example.vid_downloader_app';

    final shareText = isTr
        ? 'VidSave ile tüm video ve MP3\'leri ışık hızında indir! Link: $playStoreLink'
        : 'Download all videos & MP3s at lightning speed with VidSave! Link: $playStoreLink';

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: shareText,
          subject: isTr ? 'VidSave Video & MP3 İndirici' : 'VidSave Downloader',
        ),
      );
    } catch (e) {
      debugPrint('Share error: $e');
    }
  }

  /// 3. Gizlilik Politikası: url_launcher ile resmi GitHub Pages sözleşme linki
  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse('https://admindestekk-dev.github.io/vidsave/privacy-policy.html');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        // Fallback ana domain
        await launchUrl(
          Uri.parse('https://github.io'),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      try {
        await launchUrl(
          Uri.parse('https://github.io'),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
    }
  }

  /// 4. Sorumluluk Reddi (Disclaimer): Şık yasal bilgilendirme modalı
  void _showDisclaimerDialog(BuildContext context) {
    final isTr = LocaleService.currentLanguageCode == 'tr';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E262B) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.gavel_rounded,
                color: Color(0xFF8B5CF6),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              isTr ? 'Sorumluluk Reddi' : 'Legal Disclaimer',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTr
                  ? 'Bu uygulama telif hakkı içeren materyallerin indirilmesini teşvik etmez. Tüm sorumluluk kullanıcıya aittir.'
                  : 'This application does not encourage downloading copyrighted material. All responsibility belongs to the user.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isTr
                  ? 'VidSave yalnızca kişisel kullanım, açık kaynak ve adil kullanım (Fair Use) kapsamındaki içeriklerin arşivlenmesi amacıyla tasarlanmıştır.'
                  : 'VidSave is intended solely for personal use and archival purposes under Fair Use guidelines.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(isTr ? 'Anladım' : 'Got it'),
          ),
        ],
      ),
    );
  }
}

/// Backend adresi ve API anahtarını düzenleyen, kaydeden ve sınayan form.
///
/// Daha önce `main.dart` içinde özel bir sayfa (`_BackendSettingsPage`) olarak
/// duruyordu; artık gizli geliştirici bölümünden gömülebilmesi için bağımsız bir
/// widget hâline getirildi.
class BackendSettingsPanel extends StatefulWidget {
  const BackendSettingsPanel({
    super.key,
    required this.store,
    required this.resolver,
  });

  final BackendSettingsStore store;
  final BackendMediaResolver resolver;

  @override
  State<BackendSettingsPanel> createState() => _BackendSettingsPanelState();
}

class _BackendSettingsPanelState extends State<BackendSettingsPanel> {
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _baseUrlController,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Backend adresi',
              hintText: 'http://10.192.215.20:8787',
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
                tooltip: _obscureApiKey ? 'Anahtarı göster' : 'Anahtarı gizle',
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
            'API anahtarı cihazın şifreli güvenli deposunda tutulur. Uygulama '
            'sahibinin cihaz erişimi varsa anahtar yine çıkarılabilir; üretimde '
            'kullanıcıya özel kısa ömürlü kimlik bilgisi tercih edin.',
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
            onPressed: _busy ? null : () => _saveSettings(testConnection: true),
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
    );
  }
}
