import 'package:flutter/material.dart';

import 'backend_media_resolver.dart';
import 'backend_settings.dart';
import 'instagram_login_webview_screen.dart';
import 'media_downloader.dart';
import 'theme_service.dart';

/// "Ayarlar" sekmesi.
///
/// Normal kullanıcı yalnızca dil, tema ve hakkında seçeneklerini görür.
/// Başlığa arka arkaya 5 kez dokunulduğunda gizli geliştirici bölümü açılır ve
/// backend bağlantı ayarları görünür hâle gelir.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key, required this.store, required this.resolver});

  final BackendSettingsStore store;
  final BackendMediaResolver resolver;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  static const _accent = Color(0xFF006673);

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geliştirici Seçenekleri Aktif Edildi!'),
            backgroundColor: _accent,
          ),
        );
      }
    });
  }

  void _closeDeveloperMode() {
    setState(() {
      _clickCount = 0;
      _isDeveloperModeActive = false;
    });
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

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.language, color: _accent),
                title: const Text('Dil Seçimi / Language'),
                subtitle: const Text('Türkçe / English'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dil seçimi yakında eklenecek.'),
                    ),
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
                    subtitle: Text(isDark ? 'Açık (Karanlık Mod)' : 'Kapalı (Aydınlık Mod)'),
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

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline, color: _accent),
                title: const Text('Hakkında'),
                onTap: () => _showAboutDialog(),
              ),
              const Divider(),

              // =============================================================
              // ÖZELLİK 3: INSTAGRAM GİZLİ PROFİL VE STORY İNDİRME YETKİSİ
              // =============================================================
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)],
                    ),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                ),
                title: const Text(
                  'Instagram Hesabını Bağla (Gizli Hesaplar İçin)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Gizli profil ve hikayeleri sorunsuz indirebilmek için güvenli giriş yapın.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (context) => InstagramLoginWebViewScreen(
                        store: widget.store,
                      ),
                    ),
                  );
                },
              ),

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

  void _showAboutDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('VidSave'),
        content: const Text(
          'VidSave, video ve müzik indirmenizi sağlayan bir uygulamadır.\n\n'
          'İndirme işlemleri kendi sunucunuzda (backend) çalışır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
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
