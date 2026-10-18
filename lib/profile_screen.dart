import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import 'auth_service.dart';
import 'subscription_screen.dart';
import 'welcome_screen.dart';

/// VidSave Kullanıcı Profil Ekranı (Profile Screen)
///
/// Google ile giriş yapmış kullanıcının profil fotoğrafını, adını,
/// e-posta adresini ve Premium abonelik durumunu dinamik olarak gösterir.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.authService,
    this.onLoggedOut,
  });

  final AuthService? authService;
  final VoidCallback? onLoggedOut;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = '';
  String _email = '';
  String _avatarUrl = '';
  bool _isPremium = false;
  bool _loading = true;

  static const Color _brandColor = Color(0xFFFF5436);
  static const Color _darkBackground = Color(0xFF14191F);
  static const Color _cardBackground = Color(0xFF1E252D);

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(SecureAuthTokenStore.prefKeyUserName) ?? '';
    final email = prefs.getString(SecureAuthTokenStore.prefKeyUserEmail) ?? '';
    final avatar =
        prefs.getString(SecureAuthTokenStore.prefKeyUserAvatarUrl) ?? '';
    final isPremium =
        prefs.getBool(SubscriptionScreen.prefKeyIsPremium) ?? false;

    if (!mounted) return;
    setState(() {
      _name = name;
      _email = email;
      _avatarUrl = avatar;
      _isPremium = isPremium;
      _loading = false;
    });

    // Try fetching fresh data from server if online
    try {
      final auth = widget.authService ?? AuthService.instance;
      final user = await auth.currentUser();
      if (user != null && mounted) {
        setState(() {
          if (user.name.isNotEmpty) _name = user.name;
          if (user.email.isNotEmpty) _email = user.email;
          if (user.avatarUrl.isNotEmpty) _avatarUrl = user.avatarUrl;
        });
      }
    } catch (_) {}
  }

  Future<void> _logout() async {
    final auth = widget.authService ?? AuthService.instance;
    await auth.logout();
    if (!mounted) return;
    widget.onLoggedOut?.call();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTurkish =
        l10n.locale.languageCode.toLowerCase() == 'tr';

    return Scaffold(
      backgroundColor: _darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isTurkish ? 'Profilim' : 'My Profile',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _brandColor),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Avatar
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _brandColor, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: _brandColor.withValues(alpha: 0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: _avatarUrl.isNotEmpty
                                ? Image.network(
                                    _avatarUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        _buildFallbackAvatar(),
                                  )
                                : _buildFallbackAvatar(),
                          ),
                        ),
                        if (_isPremium)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFB703),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.star_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Name
                  Text(
                    _name.isNotEmpty
                        ? _name
                        : (isTurkish ? 'Google Kullanıcısı' : 'Google User'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Email
                  Text(
                    _email.isNotEmpty ? _email : '—',
                    style: const TextStyle(
                      color: Color(0xFF8B9BA7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Membership Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _cardBackground,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _isPremium
                            ? const Color(0xFF0E7C4B)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isPremium
                                ? const Color(0xFF0E7C4B).withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _isPremium
                                ? Icons.workspace_premium_rounded
                                : Icons.person_rounded,
                            color: _isPremium
                                ? const Color(0xFF1DB954)
                                : const Color(0xFF8B9BA7),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isTurkish ? 'Üyelik Durumu' : 'Membership Status',
                                style: const TextStyle(
                                  color: Color(0xFF8B9BA7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isPremium
                                    ? (isTurkish
                                        ? 'VidSave Premium (Aktif)'
                                        : 'VidSave Premium (Active)')
                                    : (isTurkish ? 'Ücretsiz Üye' : 'Free Member'),
                                style: TextStyle(
                                  color: _isPremium
                                      ? const Color(0xFF1DB954)
                                      : Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Logout button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: Text(
                        isTurkish ? 'Oturumu Kapat' : 'Sign Out',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFallbackAvatar() {
    return Container(
      color: const Color(0xFF2C353F),
      child: const Center(
        child: Icon(
          Icons.person_rounded,
          color: Colors.white70,
          size: 52,
        ),
      ),
    );
  }
}
