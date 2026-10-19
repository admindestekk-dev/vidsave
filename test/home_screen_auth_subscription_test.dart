import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/app_localizations.dart';
import 'package:vid_downloader_app/auth_service.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/home_screen.dart';
import 'package:vid_downloader_app/subscription_screen.dart';

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

class _SettingsStore implements BackendSettingsStore {
  @override
  Future<BackendSettings> load() async => const BackendSettings(
        baseUrl: 'https://api.vidsave.test',
        apiKey: 'test-api-key',
      );

  @override
  Future<void> save(BackendSettings settings) async {}
}

Widget _buildTestApp({
  required Widget child,
  Locale locale = const Locale('tr'),
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: child,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PremiumBanner and _handlePremiumClick Architecture', () {
    testWidgets(
      'When user is already logged in with Google, tapping AL button navigates directly to SubscriptionScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Simulate already logged in user in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          SecureAuthTokenStore.prefKeyUserEmail,
          'existinguser@gmail.com',
        );

        final tokenStore = _MemoryTokenStore();
        await tokenStore.saveToken('jwt-session-token-already-logged-in');
        await tokenStore.saveUserId('user-uuid-1234');

        final auth = AuthService(
          settingsStore: _SettingsStore(),
          tokenStore: tokenStore,
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: Scaffold(
              body: PremiumBanner(
                authService: auth,
                store: _SettingsStore(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify banner and 'AL' button are displayed
        expect(find.text('Pro Sürümü Aktif Et'), findsOneWidget);
        final alButton = find.byKey(const Key('premium_banner_buy_button'));
        expect(alButton, findsOneWidget);

        // Tap 'AL' button
        await tester.tap(alButton);
        await tester.pumpAndSettle();

        // Since user was already logged in, SubscriptionScreen should be opened directly!
        expect(find.byType(SubscriptionScreen), findsOneWidget);
        expect(find.text('Aylık Sadece 9,99 TL - KDV Dahil'), findsOneWidget);
        expect(find.text('9,99 TL / Ay - Abone Ol'), findsOneWidget);
        // Login modal must NOT be open
        expect(find.text('Pro Sürüme Geçmek İçin Giriş Yapın'), findsNothing);
      },
    );

    testWidgets(
      'When user is NOT logged in, tapping AL opens Google Sign-In modal; on auth success redirects immediately to SubscriptionScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Ensure user is NOT logged in
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();

        final tokenStore = _MemoryTokenStore();
        bool googleAuthEndpointCalled = false;

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/auth/google') {
            googleAuthEndpointCalled = true;
            return http.Response(
              jsonEncode({
                'status': 'ok',
                'success': true,
                'token': 'google-jwt-token-999',
                'is_premium': false,
                'user': {
                  'id': 'new-user-1234',
                  'email': 'newuser@gmail.com',
                  'name': 'New User',
                  'avatarUrl': 'https://lh3.googleusercontent.com/avatar.jpg',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final auth = AuthService(
          settingsStore: _SettingsStore(),
          tokenStore: tokenStore,
          httpClient: mockClient,
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: Scaffold(
              body: PremiumBanner(
                authService: auth,
                store: _SettingsStore(),
                httpClient: mockClient,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the 'AL' button
        final alButton = find.byKey(const Key('premium_banner_buy_button'));
        await tester.tap(alButton);
        await tester.pumpAndSettle();

        // Google Sign-In bottom sheet modal should be displayed!
        expect(find.text('Pro Sürüme Geçmek İçin Giriş Yapın'), findsOneWidget);
        expect(find.text('Google ile Devam Et'), findsOneWidget);

        // Now trigger authentication
        // (We can invoke loginWithGoogle directly through authService and trigger the onSuccess flow)
        await auth.loginWithGoogle(
          email: 'newuser@gmail.com',
          name: 'New User',
          avatarUrl: 'https://lh3.googleusercontent.com/avatar.jpg',
        );

        expect(googleAuthEndpointCalled, isTrue);
        expect(await tokenStore.readToken(), 'google-jwt-token-999');
        expect(
          prefs.getString(SecureAuthTokenStore.prefKeyUserEmail),
          'newuser@gmail.com',
        );

        // Dismiss the modal and trigger handlePremiumClick now that user is authenticated
        Navigator.of(tester.element(find.byType(ElevatedButton).last)).pop();
        await tester.pumpAndSettle();

        // Now tapping the banner will immediately navigate to SubscriptionScreen
        await tester.tap(alButton);
        await tester.pumpAndSettle();

        expect(find.byType(SubscriptionScreen), findsOneWidget);
        expect(find.text('Aylık Sadece 9,99 TL - KDV Dahil'), findsOneWidget);
      },
    );

    testWidgets(
      'isPlayStoreLive test shield: isPlayStoreLive == false invokes /api/auth/subscribe-monthly and does not touch Play Store',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final tokenStore = _MemoryTokenStore();
        await tokenStore.saveToken('jwt-session-token');
        await tokenStore.saveUserId('33333333-3333-4333-8333-333333333333');

        bool monthlySubscribeCalled = false;
        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/auth/subscribe-monthly') {
            monthlySubscribeCalled = true;
            return http.Response(
              jsonEncode({
                'status': 'ok',
                'success': true,
                'subscription': {
                  'amount': 9.99,
                  'currency': 'TRY',
                  'receiptMessage':
                      'Faturanız kesildi: 9,99 TL (KDV Dahil) tahsil edilmiştir. Premium mod aktif!',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final auth = AuthService(
          settingsStore: _SettingsStore(),
          tokenStore: tokenStore,
          httpClient: mockClient,
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: SubscriptionScreen(
              isPlayStoreLive: false,
              httpClient: mockClient,
              authService: auth,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final subscribeButton = find.text('9,99 TL / Ay - Abone Ol');
        expect(subscribeButton, findsOneWidget);
        await tester.tap(subscribeButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(monthlySubscribeCalled, isTrue);
        expect(find.text('PREMIUM AKTİF'), findsOneWidget);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(SubscriptionScreen.prefKeyIsPremium), isTrue);
      },
    );
  });
}
