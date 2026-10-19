import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/backend_media_resolver.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/more_screen.dart';

class _FakeSettingsStore implements BackendSettingsStore {
  BackendSettings current = BackendSettings.fromInput(
    baseUrl: 'https://fake-server.test',
    apiKey: '',
  );

  @override
  Future<BackendSettings> load() async => current;

  @override
  Future<void> save(BackendSettings value) async {
    current = value;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('MoreScreen renders "Diğerleri" section with all 4 modern cards', (
    WidgetTester tester,
  ) async {
    final store = _FakeSettingsStore();
    final resolver = BackendMediaResolver(settingsStore: store);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoreScreen(
            store: store,
            resolver: resolver,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Bölüm başlığı
    expect(find.text('Diğerleri'), findsOneWidget);

    // 4 Modern Kart
    expect(find.text('Bizi Değerlendirin'), findsOneWidget);
    expect(find.text('Uygulamayı Paylaş'), findsOneWidget);
    expect(find.text('Gizlilik Politikası'), findsOneWidget);
    expect(find.text('Sorumluluk Reddi'), findsOneWidget);

    // Sorumluluk reddi kartını ekranda görünür kılmak için kaydır
    await tester.ensureVisible(find.text('Sorumluluk Reddi'));
    await tester.pumpAndSettle();

    // Sorumluluk reddi tıklandığında dialog açılmalı
    await tester.tap(find.text('Sorumluluk Reddi'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Bu uygulama telif hakkı içeren materyallerin indirilmesini teşvik etmez'),
      findsOneWidget,
    );
    expect(find.text('Anladım'), findsOneWidget);

    // Kapat butonu
    await tester.tap(find.text('Anladım'));
    await tester.pumpAndSettle();

    expect(find.text('Anladım'), findsNothing);

    // Gizlilik politikası tıklandığında PrivacyPolicyScreen açılmalı
    await tester.ensureVisible(find.text('Gizlilik Politikası'));
    await tester.tap(find.text('Gizlilik Politikası'));
    await tester.pumpAndSettle();

    expect(find.text('Google Play Data Safety Compliant'), findsOneWidget);
    expect(find.text('1. Giriş ve Taahhüdümüz'), findsOneWidget);
    expect(find.text('3. Cihaz İzinleri ve Kullanım Amaçları'), findsOneWidget);

    // Dil değiştirme (EN) testi
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();

    expect(find.text('1. Introduction & Commitment'), findsOneWidget);
  });
}
