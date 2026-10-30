import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../music_player.dart';
import '../services/private_vault_service.dart';
import '../video_player_screen.dart';

/// VidSave Dahili Şifreli Gizli Klasör Ekranı (Private Vault Screen)
///
/// Biyometrik (Parmak izi / Face ID) veya 4 haneli PIN kodu ile kilitlenmiş
/// özel kasa alanı. Dosyalar karmaşık `.dat` adıyla diskte gizlenir.
class PrivateVaultScreen extends StatefulWidget {
  const PrivateVaultScreen({super.key});

  @override
  State<PrivateVaultScreen> createState() => _PrivateVaultScreenState();
}

class _PrivateVaultScreenState extends State<PrivateVaultScreen> {
  bool _isAuthenticated = false;
  bool _isCheckingAuth = true;
  bool _hasPin = false;

  final TextEditingController _pinController = TextEditingController();
  static const Color _neonOrange = Color(0xFFFF5436);
  static const Color _darkBg = Color(0xFF14191F);
  static const Color _cardBg = Color(0xFF1E2630);

  @override
  void initState() {
    super.initState();
    _checkInitialAccess();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialAccess() async {
    setState(() => _isCheckingAuth = true);
    final hasPin = await PrivateVaultService.instance.hasPinCode();
    setState(() => _hasPin = hasPin);

    // Otomatik biyometrik kimlik doğrulamayı dene
    final authed = await PrivateVaultService.instance.authenticate();
    if (mounted) {
      setState(() {
        _isAuthenticated = authed;
        _isCheckingAuth = false;
      });
      if (authed) {
        await PrivateVaultService.instance.getVaultItems();
      }
    }
  }

  Future<void> _submitPin() async {
    final entered = _pinController.text.trim();
    if (entered.length < 4) return;

    if (!_hasPin) {
      // Yeni PIN belirleme
      await PrivateVaultService.instance.setPinCode(entered);
      setState(() {
        _hasPin = true;
        _isAuthenticated = true;
      });
      await PrivateVaultService.instance.getVaultItems();
      return;
    }

    final success = await PrivateVaultService.instance.authenticate(
      enteredPin: entered,
    );
    if (success) {
      HapticFeedback.lightImpact();
      setState(() => _isAuthenticated = true);
      await PrivateVaultService.instance.getVaultItems();
    } else {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hatalı PIN Kodu! Lütfen tekrar deneyin.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _pinController.clear();
    }
  }

  Future<void> _openVaultFile(VaultItem item) async {
    final file = await PrivateVaultService.instance.getVaultFile(item);
    if (file == null || !mounted) return;

    if (item.isAudio) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => MusicPlayerScreen(
            file: file,
            title: item.originalName,
            autoStart: true,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              VideoPlayerScreen(file: file, title: item.originalName),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAuth) {
      return const Scaffold(
        backgroundColor: _darkBg,
        body: Center(child: CircularProgressIndicator(color: _neonOrange)),
      );
    }

    if (!_isAuthenticated) {
      return _buildLockScreen();
    }

    return _buildVaultContent();
  }

  Widget _buildLockScreen() {
    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Gizli Kasa',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _neonOrange.withValues(alpha: 0.15),
                  border: Border.all(color: _neonOrange, width: 2),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 40,
                  color: _neonOrange,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _hasPin
                    ? 'Gizli Klasör Şifresi'
                    : 'Gizli Kasa İçin PIN Belirleyin',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _hasPin
                    ? 'Parmak iziniz veya 4 haneli PIN kodunuzla giriş yapın.'
                    : 'Özel indirmelerinizi şifrelemek için 4 haneli bir PIN kodu girin.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    letterSpacing: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: _cardBg,
                    hintText: '••••',
                    hintStyle: const TextStyle(
                      color: Colors.white24,
                      letterSpacing: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: _neonOrange,
                        width: 2,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submitPin(),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _submitPin,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: Text(_hasPin ? 'Giriş Yap' : 'PIN Kaydet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _neonOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () =>
                        PrivateVaultService.instance.authenticate().then((val) {
                          if (val) setState(() => _isAuthenticated = true);
                        }),
                    icon: const Icon(
                      Icons.fingerprint_rounded,
                      size: 36,
                      color: _neonOrange,
                    ),
                    tooltip: 'Biyometrik Giriş',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVaultContent() {
    return Scaffold(
      backgroundColor: _darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: _neonOrange, size: 24),
            SizedBox(width: 8),
            Text(
              'Gizli Kasa (Private Vault)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded),
            tooltip: 'Kilitle',
            onPressed: () => setState(() => _isAuthenticated = false),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<VaultItem>>(
        valueListenable: PrivateVaultService.instance.vaultNotifier,
        builder: (context, items, _) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      child: const Icon(
                        Icons.lock_clock_rounded,
                        size: 54,
                        color: Colors.white38,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Gizli Kasanız Boş',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'İndirilenler ekranından dosyalarınızı buraya aktararak galeride görünmeyecek şekilde şifreleyebilirsiniz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return Container(
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _neonOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item.isAudio
                          ? Icons.music_note_rounded
                          : Icons.videocam_rounded,
                      color: _neonOrange,
                    ),
                  ),
                  title: Text(
                    item.originalName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${item.formattedSize} · Şifreli: ${item.encryptedFileName}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.lock_open_rounded,
                          color: Color(0xFF20B8C5),
                          size: 24,
                        ),
                        tooltip: 'Kasadan Çıkar (Restore)',
                        onPressed: () async {
                          final restored = await PrivateVaultService.instance.exportFileFromVault(item);
                          if (restored != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('"${item.originalName}" kasadan çıkarıldı! 🔓'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: _neonOrange,
                          size: 30,
                        ),
                        onPressed: () => _openVaultFile(item),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.white54,
                        ),
                        onPressed: () =>
                            PrivateVaultService.instance.deleteItem(item.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
