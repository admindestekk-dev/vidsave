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
import 'package:vid_downloader_app/backend_settings.dart';
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
  Future<BackendSettings> load() async =>
      const BackendSettings(baseUrl: 'https://api.example.test');

  @override
  Future<void> save(BackendSettings settings) async {}
}

class _FakeInAppPurchase extends Fake implements InAppPurchase {
  _FakeInAppPurchase({
    this.price = '9,99 TL',
    this.hasProduct = true,
  });

  final String price;
  final bool hasProduct;
  final purchaseStreamController =
      StreamController<List<PurchaseDetails>>.broadcast();
  bool buyNonConsumableCalled = false;
  bool restorePurchasesCalled = false;
  bool completePurchaseCalled = false;

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
      productDetails: hasProduct
          ? [
              ProductDetails(
                id: SubscriptionScreen.productId,
                title: 'VidSave Premium Monthly',
                description: 'Monthly unlimited access',
                price: price,
                rawPrice: 9.99,
                currencyCode: 'TRY',
              ),
            ]
          : const [],
      notFoundIDs: hasProduct ? const [] : [SubscriptionScreen.productId],
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
      )..pendingCompletePurchase = true,
    ]);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completePurchaseCalled = true;
  }

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

  test('legacy unverified local premium is not accepted', () async {
    SharedPreferences.setMockInitialValues({
      'vidsave_is_premium': true,
      'vidsave_premium_until': '2099-12-31T23:59:59Z',
    });

    expect(await SubscriptionScreen.readPremiumStatus(), isFalse);
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

  testWidgets('missing store product cannot start a simulated subscription', (
    tester,
  ) async {
    final fakeIap = _FakeInAppPurchase(hasProduct: false);
    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('tr'),
        home: SubscriptionScreen(inAppPurchase: fakeIap),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mağaza fiyatı alınamadı'), findsOneWidget);
    expect(find.text('Ürün yüklenemedi'), findsOneWidget);
    expect(find.textContaining('Test Satın Alımı'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
    await fakeIap.purchaseStreamController.close();
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
        expect(body['purchaseToken'], 'test_google_play_token_xyz');
        expect(body['productId'], 'vidsave_premium_monthly');
        expect(body['lang'], 'tr');
        expect(body['userId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
        expect(body['userId'], matches(RegExp(r'^[0-9a-f-]{36}$')));

        return http.Response(
          jsonEncode({
            'status': 'ok',
            'success': true,
            'verified': true,
            'premiumUntil': '2099-11-18T12:00:00Z',
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
            inAppPurchase: fakeIap,
            httpClient: mockClient,
            store: _SettingsStore(),
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
      expect(fakeIap.completePurchaseCalled, isTrue);

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
        '2099-11-18T12:00:00.000Z',
      );

      await tester.tap(find.byKey(const Key('restore_purchases')));
      await tester.pump();
      expect(fakeIap.restorePurchasesCalled, isTrue);
      fakeIap.purchaseStreamController.close();
    },
  );

  testWidgets('failed purchase verification never activates premium', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeIap = _FakeInAppPurchase();
    final client = MockClient((_) async => http.Response('{}', 503));
    await tester.pumpWidget(_buildTestApp(
      locale: const Locale('tr'),
      home: SubscriptionScreen(
        inAppPurchase: fakeIap,
        store: _SettingsStore(),
        httpClient: client,
        authService: _testAuthService(client),
      ),
    ));
    await tester.pumpAndSettle();
    final button = find.text('9,99 TL / Ay - Abone Ol');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(await SubscriptionScreen.readPremiumStatus(), isFalse);
    expect(find.textContaining('Satın alma doğrulanamadı'), findsOneWidget);
    expect(fakeIap.completePurchaseCalled, isFalse);
    await fakeIap.purchaseStreamController.close();
  });

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

}
