import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/app_localizations.dart';
import 'package:vid_downloader_app/backend_media_resolver.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/locale_service.dart';
import 'package:vid_downloader_app/more_screen.dart';

class _FakeSettingsStore implements BackendSettingsStore {
  BackendSettings _settings = const BackendSettings();

  @override
  Future<BackendSettings> load() async => _settings;

  @override
  Future<void> save(BackendSettings settings) async {
    _settings = settings;
  }
}

class _FakeResolver extends Fake implements BackendMediaResolver {}

Widget _buildTestApp({required Widget child}) {
  return ValueListenableBuilder<Locale?>(
    valueListenable: LocaleService.localeNotifier,
    builder: (context, currentLocale, _) {
      return MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: currentLocale ?? const Locale('tr'),
        home: child,
      );
    },
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleService.localeNotifier.value = const Locale('tr');
  });

  testWidgets('Language selection dialog opens with rounded corners and lists Turkish and English', (tester) async {
    final store = _FakeSettingsStore();
    final resolver = _FakeResolver();

    await tester.pumpWidget(
      _buildTestApp(
        child: MoreScreen(store: store, resolver: resolver),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial state is Turkish
    expect(find.text('Dil Seçimi / Language'), findsOneWidget);
    expect(find.text('🇹🇷 Türkçe'), findsOneWidget);

    // Tap the Language ListTile
    await tester.tap(find.text('Dil Seçimi / Language'));
    await tester.pumpAndSettle();

    // Verify dialog opened
    expect(find.byType(Dialog), findsOneWidget);

    final dialogFinder = find.byType(Dialog);
    final dialog = tester.widget<Dialog>(dialogFinder);
    expect(dialog.shape, isA<RoundedRectangleBorder>());
    final border = dialog.shape as RoundedRectangleBorder;
    expect(border.borderRadius, BorderRadius.circular(20));

    // Verify language options are listed (including flags)
    expect(find.text('Türkçe'), findsWidgets);
    expect(find.text('English'), findsWidgets);
    expect(find.text('Español'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);

    expect(find.text('🇹🇷'), findsOneWidget);
    expect(find.text('🇺🇸'), findsOneWidget);
    expect(find.text('🇪🇸'), findsOneWidget);
    expect(find.text('🇩🇪'), findsOneWidget);
    expect(find.text('🇫🇷'), findsOneWidget);
    expect(find.text('🇷🇺'), findsOneWidget);
    expect(find.text('🇸🇦'), findsOneWidget);
    expect(find.text('🇨🇳'), findsOneWidget);

    // Tap English option
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    // Verify dialog closed
    expect(find.byType(Dialog), findsNothing);

    // Verify language changed to English reactively
    expect(LocaleService.currentLanguageCode, 'en');
    expect(find.text('🇺🇸 English'), findsOneWidget);

    // Open dialog again and select Turkish
    await tester.tap(find.text('Dil Seçimi / Language'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('Türkçe').last);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(LocaleService.currentLanguageCode, 'tr');
    expect(find.text('🇹🇷 Türkçe'), findsOneWidget);
  });

  testWidgets('MoreScreen renders Delete Account and confirms dialog', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _FakeSettingsStore();
    final resolver = _FakeResolver();

    await tester.pumpWidget(
      _buildTestApp(
        child: MoreScreen(store: store, resolver: resolver),
      ),
    );
    await tester.pumpAndSettle();

    final deleteAccountTile = find.text('Hesabımı Sil');
    expect(deleteAccountTile, findsOneWidget);
    await tester.ensureVisible(deleteAccountTile);
    await tester.tap(deleteAccountTile);
    await tester.pumpAndSettle();

    // Verify warning dialog appeared
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Hesabınızı ve tüm indirme geçmişinizi kalıcı olarak silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'), findsOneWidget);

    final cancelButton = find.text('Vazgeç');
    expect(cancelButton, findsOneWidget);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}
