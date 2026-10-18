import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/app_localizations.dart';
import 'package:vid_downloader_app/auth_service.dart';
import 'package:vid_downloader_app/backend_media_resolver.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/download_item_model.dart';
import 'package:vid_downloader_app/locale_service.dart';
import 'package:vid_downloader_app/more_screen.dart';
import 'package:vid_downloader_app/storage_service.dart';
import 'package:vid_downloader_app/subscription_screen.dart';
import 'package:vid_downloader_app/user_identity_service.dart';
import 'package:vid_downloader_app/welcome_screen.dart';

class _FakeSettingsStore implements BackendSettingsStore {
  @override
  Future<BackendSettings> load() async => const BackendSettings(
    baseUrl: 'https://example.test',
    apiKey: 'test-key',
  );

  @override
  Future<void> save(BackendSettings settings) async {}
}

class _FakeResolver extends Fake implements BackendMediaResolver {}

class _MemoryTokenStore implements AuthTokenStore {
  String? token;
  String? userId;

  @override
  Future<void> clearToken() async {
    token = null;
    userId = null;
  }

  @override
  Future<String?> readToken() async => token;

  @override
  Future<String?> readUserId() async => userId;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> saveUserId(String value) async => userId = value;
}

Widget _buildApp({required AuthService authService}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('tr'),
    home: MoreScreen(
      store: _FakeSettingsStore(),
      resolver: _FakeResolver(),
      authService: authService,
    ),
  );
}

Future<void> _confirmDeletion(WidgetTester tester) async {
  final deleteTile = find.text('Hesabımı Sil').first;
  await tester.ensureVisible(deleteTile);
  await tester.tap(deleteTile);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Evet, Kalıcı Olarak Sil'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'preserve_this_setting': 'keep',
      SubscriptionScreen.prefKeyIsPremium: true,
      SubscriptionScreen.prefKeySubscribedAt: '2026-10-01T00:00:00.000',
      WelcomeScreen.prefKeyHasSeenWelcome: true,
    });
    LocaleService.localeNotifier.value = const Locale('tr');
    await StorageService.clearAll();
    await StorageService.addItem(
      DownloadItemModel(
        id: 'download_1',
        name: 'saved.mp4',
        type: 'video',
        sizeInBytes: 12,
        filePath: '/tmp/saved.mp4',
        downloadedAt: DateTime.utc(2026, 10, 1),
      ),
    );
  });

  testWidgets(
    'successful deletion sends installation id and clears owned local state',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final existingUserId = await UserIdentityService.getOrCreateUserId();
      String? sentUserId;
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/delete-account');
        expect(request.headers['X-Api-Key'], 'test-key');
        sentUserId =
            (jsonDecode(request.body) as Map<String, dynamic>)['userId']
                as String;
        return http.Response('{"success":true}', 200);
      });
      final authService = AuthService(
        settingsStore: _FakeSettingsStore(),
        tokenStore: _MemoryTokenStore(),
        httpClient: client,
      );

      await tester.pumpWidget(_buildApp(authService: authService));
      await tester.pumpAndSettle();
      await _confirmDeletion(tester);

      expect(sentUserId, existingUserId);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(await StorageService.getItems(), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('preserve_this_setting'), 'keep');
      expect(prefs.getBool(SubscriptionScreen.prefKeyIsPremium), isNull);
      expect(prefs.getString(SubscriptionScreen.prefKeySubscribedAt), isNull);
      expect(prefs.getBool(WelcomeScreen.prefKeyHasSeenWelcome), isNull);
      expect(
        await UserIdentityService.getOrCreateUserId(),
        isNot(existingUserId),
      );
    },
  );

  testWidgets('failed server deletion preserves local data and offers retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final existingUserId = await UserIdentityService.getOrCreateUserId();
    final client = MockClient(
      (_) async => http.Response('{"error":"unavailable"}', 503),
    );
    final authService = AuthService(
      settingsStore: _FakeSettingsStore(),
      tokenStore: _MemoryTokenStore(),
      httpClient: client,
    );

    await tester.pumpWidget(_buildApp(authService: authService));
    await tester.pumpAndSettle();
    await _confirmDeletion(tester);

    expect(find.byType(MoreScreen), findsOneWidget);
    expect(
      find.text('Hesap silinemedi. Bağlantınızı kontrol edip tekrar deneyin.'),
      findsOneWidget,
    );
    expect((await StorageService.getItems()).single.id, 'download_1');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SubscriptionScreen.prefKeyIsPremium), isTrue);
    expect(prefs.getBool(WelcomeScreen.prefKeyHasSeenWelcome), isTrue);
    expect(await UserIdentityService.getOrCreateUserId(), existingUserId);
  });
}
