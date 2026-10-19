import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/app_localizations.dart';
import 'package:vid_downloader_app/auth_service.dart';
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

class _FakeInAppPurchase extends Fake implements InAppPurchase {
  final purchaseStreamController =
      StreamController<List<PurchaseDetails>>.broadcast();
  bool buyNonConsumableCalled = false;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      purchaseStreamController.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: [
        ProductDetails(
          id: SubscriptionScreen.productId,
          title: 'VidSave Premium Monthly',
          description: 'Monthly unlimited access',
          price: '9,99 ₺',
          rawPrice: 9.99,
          currencyCode: 'TRY',
        ),
      ],
      notFoundIDs: const [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyNonConsumableCalled = true;
    purchaseStreamController.add([
      PurchaseDetails(
        purchaseID: 'google_order_12345',
        productID: purchaseParam.productDetails.id,
        verificationData: PurchaseVerificationData(
          localVerificationData: 'test_local_data',
          serverVerificationData: 'test_google_play_token_xyz',
          source: 'google_play',
        ),
        transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
        status: PurchaseStatus.purchased,
      ),
    ]);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}
}

AuthService _testAuthService(http.Client client) =>
    AuthService(tokenStore: _MemoryTokenStore(), httpClient: client);

Widget _buildTestApp({required Locale locale, required Widget home}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: home,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'SubscriptionScreen displays psychological Turkish pricing (9,99 TL)',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('tr'),
          home: const SubscriptionScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('9,99 TL / Ay - KDV Dahil'), findsOneWidget);
      expect(find.text('Tüm vergiler ve KDV dahildir.'), findsOneWidget);
      expect(find.text('9,99 TL / Ay - Abone Ol'), findsOneWidget);
    },
  );

  testWidgets(
    'SubscriptionScreen displays psychological English pricing (\$0.99)',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('en'),
          home: const SubscriptionScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('\$0.99 / Month - All Taxes Included'), findsOneWidget);
      expect(find.text('All taxes and VAT included.'), findsOneWidget);
      expect(find.text('Subscribe - \$0.99 / Mo'), findsOneWidget);
    },
  );

  testWidgets(
    'Subscribing triggers payment, receipt and persists to SharedPreferences',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/auth/subscribe-monthly');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['lang'], 'tr');
        expect(body['userId'], matches(RegExp(r'^[0-9a-f-]{36}$')));

        return http.Response(
          jsonEncode({
            'status': 'ok',
            'success': true,
            'subscription': {
              'amount': 9.99,
              'currency': 'TRY',
              'receiptMessage': 'Faturanız kesildi: 9,99 TL (KDV Dahil) tahsil edilmiştir. Premium mod aktif!',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('tr'),
          home: SubscriptionScreen(
            httpClient: mockClient,
            authService: _testAuthService(mockClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final subscribeButton = find.text('9,99 TL / Ay - Abone Ol');
      expect(subscribeButton, findsOneWidget);
      await tester.ensureVisible(subscribeButton);
      await tester.tap(subscribeButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify receipt message appears
      expect(
        find.text(
          'Faturanız kesildi: 9,99 TL (KDV Dahil) tahsil edilmiştir. Premium mod aktif!',
        ),
        findsWidgets,
      );
      expect(find.text('PREMIUM AKTİF'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SubscriptionScreen.prefKeyIsPremium), isTrue);
    },
  );

  testWidgets(
    'InAppPurchase triggers Google Play purchase and verifies on backend verify-purchase endpoint',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeIap = _FakeInAppPurchase();
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/auth/verify-purchase');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['token'], 'test_google_play_token_xyz');
        expect(body['productId'], 'vidsave_premium_monthly');
        expect(body['lang'], 'tr');
        expect(body['userId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
        expect(body['userId'], matches(RegExp(r'^[0-9a-f-]{36}$')));

        return http.Response(
          jsonEncode({
            'status': 'ok',
            'success': true,
            'verified': true,
            'premiumUntil': '2026-11-18T12:00:00Z',
            'receiptMessage': 'Faturanız onaylandı: Google Play aboneliğiniz doğrulandı ve Premium süreniz 30 gün uzatıldı!',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('tr'),
          home: SubscriptionScreen(
            isPlayStoreLive: true,
            inAppPurchase: fakeIap,
            httpClient: mockClient,
            authService: _testAuthService(mockClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify price is displayed
      expect(find.text('9,99 TL / Ay - KDV Dahil'), findsOneWidget);

      final subscribeButton = find.text('9,99 TL / Ay - Abone Ol');
      expect(subscribeButton, findsOneWidget);
      await tester.ensureVisible(subscribeButton);
      await tester.tap(subscribeButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify buyNonConsumable was called on Google Play billing
      expect(fakeIap.buyNonConsumableCalled, isTrue);

      // Verify backend confirmation message appears and premium is activated
      expect(
        find.text(
          'Faturanız onaylandı: Google Play aboneliğiniz doğrulandı ve Premium süreniz 30 gün uzatıldı!',
        ),
        findsWidgets,
      );
      expect(find.text('PREMIUM AKTİF'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SubscriptionScreen.prefKeyIsPremium), isTrue);

      fakeIap.purchaseStreamController.close();
    },
  );

  testWidgets(
    'SubscriptionScreen renders Terms of Service and Privacy Policy legal links',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('tr'),
          home: const SubscriptionScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final termsButton = find.text('Kullanım Koşulları');
      final privacyButton = find.text('Gizlilik Politikası');
      expect(termsButton, findsOneWidget);
      expect(privacyButton, findsOneWidget);

      await tester.ensureVisible(termsButton);
      await tester.tap(termsButton);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Kullanım Koşulları'), findsWidgets);

      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'isPlayStoreLive == false shields from in_app_purchase engine and calls subscribe-monthly simulation',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeIap = _FakeInAppPurchase();
      bool subscribeMonthlyCalled = false;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/subscribe-monthly') {
          subscribeMonthlyCalled = true;
          return http.Response(
            jsonEncode({
              'status': 'ok',
              'success': true,
              'subscription': {
                'amount': 9.99,
                'currency': 'TRY',
                'receiptMessage': 'Faturanız kesildi: 9,99 TL (KDV Dahil) tahsil edilmiştir. Premium mod aktif!',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('tr'),
          home: SubscriptionScreen(
            isPlayStoreLive: false,
            inAppPurchase: fakeIap,
            httpClient: mockClient,
            authService: _testAuthService(mockClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final subscribeButton = find.text('9,99 TL / Ay - Abone Ol');
      await tester.ensureVisible(subscribeButton);
      await tester.tap(subscribeButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // in_app_purchase engine was NOT called because isPlayStoreLive is false!
      expect(fakeIap.buyNonConsumableCalled, isFalse);
      // backend simulation endpoint WAS called!
      expect(subscribeMonthlyCalled, isTrue);
      expect(find.text('PREMIUM AKTİF'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SubscriptionScreen.prefKeyIsPremium), isTrue);

      fakeIap.purchaseStreamController.close();
    },
  );
}
