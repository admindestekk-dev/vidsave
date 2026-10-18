

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/app_localizations.dart';
import 'package:vid_downloader_app/subscription_screen.dart';

Widget _buildTestApp({
  required Locale locale,
  required Widget home,
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
    home: home,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SubscriptionScreen displays psychological Turkish pricing (9,99 TL)', (tester) async {
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

    expect(find.text('Aylık Sadece 9,99 TL'), findsOneWidget);
    expect(find.text('Tüm vergiler ve KDV dahildir.'), findsOneWidget);
    expect(find.text('9,99 TL / Ay - Abone Ol'), findsOneWidget);
  });

  testWidgets('SubscriptionScreen displays psychological English pricing (\$0.99)', (tester) async {
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

    expect(find.text('Only \$0.99 / Month'), findsOneWidget);
    expect(find.text('All taxes and VAT included.'), findsOneWidget);
    expect(find.text('Subscribe - \$0.99 / Mo'), findsOneWidget);
  });

  testWidgets('Subscribing triggers payment, receipt and persists to SharedPreferences', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockClient((request) async {
      expect(request.url.path, '/api/auth/subscribe-monthly');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['lang'], 'tr');

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
        home: SubscriptionScreen(httpClient: mockClient),
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
    expect(find.text('Faturanız kesildi: 9,99 TL (KDV Dahil) tahsil edilmiştir. Premium mod aktif!'), findsWidgets);
    expect(find.text('PREMIUM AKTİF'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SubscriptionScreen.prefKeyIsPremium), isTrue);
  });
}
