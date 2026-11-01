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
  _FakeInAppPurchase({this.price = '9,99 TL'});

  final String price;
  final purchaseStreamController =
      StreamController<List<PurchaseDetails>>.broadcast();
  bool buyNonConsumableCalled = false;
  bool restorePurchasesCalled = false;

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
          price: price,
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

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restorePurchasesCalled = true;
  }
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

  testWidgets('SubscriptionScreen displays localized store pricing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('tr'),
        home: SubscriptionScreen(
          inAppPurchase: _FakeInAppPurchase(price: '9,99 TL'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aylık 9,99 TL'), findsOneWidget);
    expect(
      find.text('Fiyat ve vergilendirme mağaza tarafından belirlenir.'),
      findsOneWidget,
    );
    expect(find.text('9,99 TL / Ay - Abone Ol'), findsOneWidget);
  });

  testWidgets(
    'SubscriptionScreen uses the store price regardless of app locale',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('en'),
          home: SubscriptionScreen(
            inAppPurchase: _FakeInAppPurchase(price: '\$0.99'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('\$0.99 / month'), findsOneWidget);
      expect(
        find.text('Price and applicable taxes are set by the store.'),
        findsOneWidget,
      );
      expect(find.text('Subscribe - \$0.99 / month'), findsOneWidget);
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
              'premiumUntil': '2099-11-18T12:00:00Z',
              'receiptMessage': 'Geliştirici test aboneliği etkinleştirildi.',
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
            isPlayStoreLive: false,
            inAppPurchase: _FakeInAppPurchase(),
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
        find.text('Geliştirici test aboneliği etkinleştirildi.'),
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
      expect(find.text('Aylık 9,99 TL'), findsOneWidget);

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
      expect(
        prefs.getString(SubscriptionScreen.prefKeyPremiumUntil),
        '2026-11-18T12:00:00.000Z',
      );

      await tester.tap(find.byKey(const Key('restore_purchases')));
      await tester.pump();
      expect(fakeIap.restorePurchasesCalled, isTrue);
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
                'premiumUntil': '2099-11-18T12:00:00Z',
                'receiptMessage': 'Geliştirici test aboneliği etkinleştirildi.',
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

  testWidgets('failed debug subscription response never activates Premium', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeIap = _FakeInAppPurchase();
    final client = MockClient(
      (_) async => http.Response('{"success":false}', 503),
    );
    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('tr'),
        home: SubscriptionScreen(
          isPlayStoreLive: false,
          inAppPurchase: fakeIap,
          httpClient: client,
          authService: _testAuthService(client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final subscribeButton = find.text('9,99 TL / Ay - Abone Ol');
    await tester.ensureVisible(subscribeButton);
    await tester.tap(subscribeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SubscriptionScreen.prefKeyIsPremium), isNull);
    expect(await SubscriptionScreen.readPremiumStatus(), isFalse);
    expect(find.text('PREMIUM AKTİF'), findsNothing);
  });
}
