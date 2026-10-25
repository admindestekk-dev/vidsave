import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vid_downloader_app/admob_service.dart';
import 'package:vid_downloader_app/api_service.dart';
import 'package:vid_downloader_app/app_localizations.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/batch_download_screen.dart';
import 'package:vid_downloader_app/bulk_download_screen.dart';
import 'package:vid_downloader_app/download_platforms.dart';
import 'package:vid_downloader_app/downloads_screen.dart';
import 'package:vid_downloader_app/home_screen.dart';
import 'package:vid_downloader_app/main.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/media_library.dart';
import 'package:vid_downloader_app/quick_download_dialog.dart';

class _IntegrationTestMediaLibrary implements MediaLibrary {
  const _IntegrationTestMediaLibrary();

  @override
  Future<PermissionState> requestPermission() async =>
      PermissionState.authorized;

  @override
  Future<List<AssetEntity>> loadPage({
    required RequestType type,
    required int page,
    required int pageSize,
  }) async =>
      const [];

  @override
  void invalidateCache() {}
}

class _IntegrationTestResolver implements MediaResolver {
  final List<String> resolvedCalls = [];

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    return const MediaPreview(
      title: 'VidSave Canlı Test Medyası (HD)',
      uploader: 'VidSave Test Studio',
      duration: Duration(minutes: 3, seconds: 45),
      qualities: [
        VideoQuality(height: 1080, label: '1080p Full HD', sizeInBytes: 52428800),
        VideoQuality(height: 720, label: '720p HD', sizeInBytes: 26214400),
        VideoQuality(height: 480, label: '480p Standart', sizeInBytes: 13107200),
      ],
    );
  }

  @override
  Future<ResolvedMedia> resolve(
    Uri source,
    DownloadKind kind, {
    int? height,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    resolvedCalls.add('${source.path}|kind=${kind.name}|height=$height|effect=$audioEffect');
    final ext = kind == DownloadKind.audio ? 'mp3' : 'mp4';
    return ResolvedMedia(
      url: Uri.parse('https://vidsave-q7ut.onrender.com/api/ping'),
      fileName: 'vidsave_test_${kind.name}_${height ?? 0}.$ext',
      mimeType: kind == DownloadKind.audio ? 'audio/mpeg' : 'video/mp4',
      fileSizeInBytes: 1024 * 1024 * 2,
    );
  }

  @override
  Future<List<SearchResultItem>> search(String query) async {
    return [
      SearchResultItem(
        id: '1',
        baslik: '$query - Canlı Arama Sonucu 1',
        kanal: 'VidSave Müzik Kanalı',
        sure: '3:45',
        url: 'https://youtube.com/watch?v=mock1',
      ),
      SearchResultItem(
        id: '2',
        baslik: '$query - Canlı Arama Sonucu 2',
        kanal: 'VidSave Resmi Prodüksiyon',
        sure: '4:15',
        url: 'https://youtube.com/watch?v=mock2',
      ),
    ];
  }
}

class _IntegrationTestDownloader extends MediaDownloader {
  _IntegrationTestDownloader() : super(directoryProvider: () async => _testDir);
  static final Directory _testDir = Directory.systemTemp.createTempSync('vidsave_it_downloads');

  @override
  Future<File> download(
    ResolvedMedia media, {
    DownloadProgressCallback? onProgress,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    final file = File('${_testDir.path}${Platform.pathSeparator}${media.fileName}');
    await file.writeAsBytes(List.filled(1024 * 100, 65)); // 100 KB test dosyası
    onProgress?.call(50 * 1024, 100 * 1024);
    onProgress?.call(100 * 1024, 100 * 1024);
    return file;
  }
}

Future<void> _ensureHomePage(
  WidgetTester tester, {
  MediaResolver? resolver,
  MediaDownloader? downloader,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('vidsave_has_seen_welcome', true);

  AdmobService.instance.disableAdsForTesting = true;

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('tr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: VidSaveHomePage(
        library: const _IntegrationTestMediaLibrary(),
        mediaResolver: resolver,
        mediaDownloader: downloader,
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group('VidSave Canlı Android Emülatör & Render Tüm İndirme Yerleri Entegrasyon Testi', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'vidsave_has_seen_welcome': true,
      });
      AdmobService.instance.disableAdsForTesting = true;
    });

    testWidgets('1. Render Bulut Sunucusu Canlı Ping & Health Kontrolü', (
      WidgetTester tester,
    ) async {
      debugPrint('\n======================================================');
      debugPrint('[TEST 1] Render bulut sunucusuna canlı ping atılıyor...');
      debugPrint('======================================================');
      final apiService = ApiService(baseUrl: BackendSettings.defaultBaseUrl);

      final pingResponse = await apiService.dio.get<Map<String, dynamic>>(
        '${BackendSettings.defaultBaseUrl}/api/ping',
      );

      expect(pingResponse.statusCode, 200);
      expect(pingResponse.data?['status'], 'pong');
      debugPrint(
        '  [BAŞARILI] Render Bulut Ping Alındı! status: ${pingResponse.data?['status']}, zaman: ${pingResponse.data?['time']}',
      );
    });

    testWidgets('2. VidSave Uygulama Başlatma, Logo, Navigasyon ve Platform Butonları', (
      WidgetTester tester,
    ) async {
      debugPrint('\n======================================================');
      debugPrint('[TEST 2] VidSave Ana Ekranı ve Platform Izgarası Doğrulanıyor...');
      debugPrint('======================================================');
      await _ensureHomePage(tester);

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(VidSaveBrandTitle), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);

      final navBar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(navBar.currentIndex, 2); // Varsayılan İndir sekmesi

      expect(find.byType(QuickDownloadWindow), findsOneWidget);
      expect(find.text('Hızlı İndirme Paneli'), findsOneWidget);
      expect(find.text('Video İndir'), findsOneWidget);
      expect(find.text('MP3 İndir'), findsOneWidget);

      // 8 Platform karesi ve butonları kontrolü
      for (final p in kDownloadPlatforms) {
        expect(find.text(p.label), findsOneWidget);
      }
      expect(find.text('İNDİR'), findsNWidgets(kDownloadPlatforms.length));
      debugPrint('  [BAŞARILI] Ana Ekran, Hızlı İndirme Paneli ve ${kDownloadPlatforms.length} adet Platform Butonu doğrulandı.');
    });

    testWidgets('3. Alt Sekmeler Arası Canlı Geçiş (Videolar, Müzik, Ayarlar, İndir)', (
      WidgetTester tester,
    ) async {
      debugPrint('\n======================================================');
      debugPrint('[TEST 3] Alt Sekmeler Arası Canlı Geçişler Doğrulanıyor...');
      debugPrint('======================================================');
      await _ensureHomePage(tester);

      // Videolar
      await tester.tap(find.text('Videolar').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Cihazda gösterilecek videolar bulunamadı.'), findsOneWidget);
      debugPrint('  [BAŞARILI] Videolar sekmesine geçildi.');

      // Müzik
      await tester.tap(find.text('Müzik').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Cihazda gösterilecek müzik bulunamadı.'), findsOneWidget);
      debugPrint('  [BAŞARILI] Müzik sekmesine geçildi.');

      // Ayarlar
      await tester.tap(find.text('Ayarlar').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Uygulama Ayarları'), findsOneWidget);
      expect(find.text('Dil Seçimi / Language'), findsOneWidget);
      expect(find.text('Destek & İletişim'), findsOneWidget);
      debugPrint('  [BAŞARILI] Ayarlar sekmesi doğrulandı.');

      // İndir sekmesine dönüş
      await tester.tap(find.text('İndir').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(QuickDownloadWindow), findsOneWidget);
      debugPrint('  [BAŞARILI] İndir ana ekranına dönüldü.');
    });

    testWidgets('4. İNDİRME YERİ 1: Hızlı İndirme Paneli (Video İndir & MP3 İndir)', (
      WidgetTester tester,
    ) async {
      debugPrint('\n======================================================');
      debugPrint('[TEST 4] İndirme Yeri 1: Hızlı İndirme Paneli Test Ediliyor...');
      debugPrint('======================================================');
      await _ensureHomePage(tester);

      // Boş form hata yakalama denetimi
      final videoBtn = find.text('Video İndir');
      await tester.tap(videoBtn);
      await tester.pumpAndSettle();
      expect(find.text('Lütfen geçerli bir video veya ses bağlantısı yapıştırın.'), findsOneWidget);
      debugPrint('  -> Boş link doğrulama uyarısı yakalandı.');

      // Canlı Render destekli URL girme
      final inputField = find.byType(TextField).first;
      await tester.enterText(inputField, 'https://vimeo.com/76979871');
      await tester.pumpAndSettle();
      expect(find.text('https://vimeo.com/76979871'), findsOneWidget);

      // Canlı API Analiz Bağlantısı Doğrulaması
      final api = ApiService(baseUrl: BackendSettings.defaultBaseUrl);
      final res = await api.dio.get<Map<String, dynamic>>('${BackendSettings.defaultBaseUrl}/');
      expect(res.statusCode, 200);
      expect(res.data?['service'], 'VidSave Backend');
      debugPrint('  [BAŞARILI] Hızlı İndirme Paneli formu ve Render bağlantısı canlı olarak doğrulandı.');
    });

    testWidgets('5. İNDİRME YERİ 2: Platform Seçim Modalı (FB, TT, IG, Pinterest, MP3 Arama & Kalite Butonları)', (
      WidgetTester tester,
    ) async {
      debugPrint('\n======================================================');
      debugPrint('[TEST 5] İndirme Yeri 2: Platform Özel Modal & Kalite Butonları Test Ediliyor...');
      debugPrint('======================================================');
      final resolver = _IntegrationTestResolver();
      final downloader = _IntegrationTestDownloader();

      await _ensureHomePage(tester, resolver: resolver, downloader: downloader);

      // 5.1. Facebook Platform Kartına Tıkla ve Modal Aç
      final fbTile = find.text('FB VİDEO İNDİR');
      expect(fbTile, findsOneWidget);
      await tester.tap(fbTile);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Video ara veya bağlantı yapıştırın'), findsOneWidget);
      expect(find.text('ARA'), findsOneWidget);
      debugPrint('  -> Facebook platform arama/indirme modalı açıldı.');

      // Facebook linki yapıştır ve ARA'ya bas
      final searchInput = find.widgetWithText(TextField, 'Video ara veya bağlantı yapıştırın');
      await tester.enterText(searchInput, 'https://facebook.com/reel/123456');
      await tester.pump();
      await tester.tap(find.text('ARA'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Kalite seçenekleri ve İNDİR butonları kontrolü
      expect(find.text('VidSave Canlı Test Medyası (HD)'), findsOneWidget);
      expect(find.text('1080p Full HD'), findsOneWidget);
      expect(find.text('720p HD'), findsOneWidget);
      expect(find.text('480p Standart'), findsOneWidget);

      // 720p HD yanındaki İNDİR butonuna tıkla
      final hd720DownloadBtn = find.byKey(const ValueKey('quality_720'));
      expect(hd720DownloadBtn, findsOneWidget);
      await tester.tap(hd720DownloadBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(resolver.resolvedCalls.any((call) => call.contains('height=720')), isTrue);
      debugPrint('  -> 720p HD video indirme akışı başarıyla tetiklendi.');

      // Modalı kapat
      final closeButton = find.byKey(const ValueKey('platform_modal_close_button'));
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 5.2. MP3 İndir Kartı ve Canlı Şarkı Arama Listesini Test Et
      showModalBottomSheet<void>(
        context: tester.element(find.byType(VidSaveHomePage)),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => PlatformSearchDownloadModal(
          platform: kDownloadPlatforms.firstWhere((p) => p.isAudio),
          resolver: resolver,
          downloader: downloader,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Müzik ara veya Video linki yapıştırın (YouTube, TikTok, IG vb.)'), findsOneWidget);
      final musicSearchInput = find.widgetWithText(
        TextField,
        'Müzik ara veya Video linki yapıştırın (YouTube, TikTok, IG vb.)',
      );
      await tester.enterText(musicSearchInput, 'Barış Manço');
      await tester.pump();
      await tester.tap(find.text('ARA'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Barış Manço - Canlı Arama Sonucu 1'), findsOneWidget);
      debugPrint('  -> MP3 canlı liste arama sonuçları başarıyla listelendi.');

      // Modaldan çık
      final closeButton2 = find.byKey(const ValueKey('platform_modal_close_button'));
      expect(closeButton2, findsOneWidget);
      await tester.tap(closeButton2);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      debugPrint('  [BAŞARILI] Platform Modalları (Video & MP3) ve Kalite Seçim butonları doğrulandı.');
    });

    testWidgets('6. İNDİRME YERİ 3: Toplu İndirme Ekranı (Bulk Download) ve Dinamik Satır Modu (Batch)', (
      WidgetTester tester,
    ) async {
      debugPrint('\n======================================================');
      debugPrint('[TEST 6] İndirme Yeri 3: Toplu İndirme (Bulk & Batch) Ekranı Test Ediliyor...');
      debugPrint('======================================================');
      final resolver = _IntegrationTestResolver();
      final downloader = _IntegrationTestDownloader();

      await _ensureHomePage(tester, resolver: resolver, downloader: downloader);

      // Toplu İndir butonuna basarak sayfayı aç
      final bulkBtn = find.text('Toplu İndir');
      expect(bulkBtn, findsOneWidget);
      await tester.tap(bulkBtn);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Toplu İndirme (Bulk Download)'), findsOneWidget);
      expect(find.text('Video (MP4)'), findsOneWidget);
      expect(find.text('Müzik (MP3)'), findsOneWidget);
      expect(find.text('Algılanan Bağlantı: 0'), findsOneWidget);

      // Çoklu link yapıştır
      final bulkInput = find.byType(TextField);
      await tester.enterText(
        bulkInput,
        'https://instagram.com/reel/1\nhttps://tiktok.com/@u/2\nhttps://vimeo.com/3',
      );
      await tester.pump();

      expect(find.text('Algılanan Bağlantı: 3'), findsOneWidget);
      expect(find.text('Toplu İndirmeyi Başlat (3 Link)'), findsOneWidget);
      debugPrint('  -> 3 adet bağlantı başarıyla ayrıştırıldı.');

      // Toplu İndirmeyi Başlat
      await tester.tap(find.text('Toplu İndirmeyi Başlat (3 Link)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      debugPrint('  -> Toplu indirme kuyruk ilerlemesi canlı olarak başlatıldı.');

      // Dinamik Satır Moduna (BatchDownloadScreen) Geçiş Kontrolü
      final batchIconBtn = find.byIcon(Icons.playlist_add_rounded);
      expect(batchIconBtn, findsOneWidget);
      await tester.tap(batchIconBtn);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Toplu İndirme'), findsOneWidget);
      expect(find.text('Yeni Link Satırı Ekle'), findsOneWidget);
      expect(find.text('Toplu İndirmeyi Başlat'), findsOneWidget);
      debugPrint('  -> Dinamik Satır Modu (Batch Download Screen) doğrulandı.');

      // Ana sayfaya geri dön
      Navigator.of(tester.element(find.byType(BatchDownloadScreen))).pop();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(BulkDownloadScreen))).pop();
      await tester.pumpAndSettle();

      debugPrint('  [BAŞARILI] Toplu İndirme (Bulk & Batch) arayüzleri ve indirme tetikleyicileri doğrulandı.');
    });

    testWidgets('7. İNDİRME YERİ 4: Otomatik Pano Algılama Penceresi (QuickDownloadDialog)', (
      WidgetTester tester,
    ) async {
      debugPrint('\n======================================================');
      debugPrint('[TEST 7] İndirme Yeri 4: Otomatik Algılama Dialogu (QuickDownloadDialog) Test Ediliyor...');
      debugPrint('======================================================');
      final resolver = _IntegrationTestResolver();
      final downloader = _IntegrationTestDownloader();

      await _ensureHomePage(tester, resolver: resolver, downloader: downloader);

      // Doğrudan QuickDownloadDialog.show yardımcı metodunu tetikle
      QuickDownloadDialog.show(
        context: tester.element(find.byType(VidSaveHomePage)),
        videoTitle: 'https://vimeo.com/76979871',
        resolver: resolver,
        downloader: downloader,
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('VidSave Algıladı'), findsOneWidget);
      expect(find.text('https://vimeo.com/76979871'), findsOneWidget);
      expect(find.text('Ses Modu & Efekt'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Nightcore'), findsOneWidget);
      expect(find.text('Bass Boost'), findsOneWidget);
      expect(find.text('Sadece Nakaratı İndir'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_dialog_video_button')), findsOneWidget);
      expect(find.text('MP3 İndir'), findsWidgets);

      // Video İndir butonuna basınca onay popup'ı açılırsa 'Reklamı İzle ve İndir' butonuna bas
      await tester.tap(find.byKey(const ValueKey('quick_dialog_video_button')));
      await tester.pumpAndSettle();

      final watchAdBtn = find.text('Reklamı İzle ve İndir');
      if (watchAdBtn.evaluate().isNotEmpty) {
        await tester.tap(watchAdBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(resolver.resolvedCalls.any((call) => call.contains('kind=video')), isTrue);
      debugPrint('  -> QuickDownloadDialog üzerinden video indirme işlemi başarıyla tetiklendi.');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Eğer dialog otomatik kapanmadıysa kapatma butonuna bas
      final dialogCloseBtn = find.byKey(const ValueKey('quick_download_dialog_close_button'));
      if (dialogCloseBtn.evaluate().isNotEmpty) {
        await tester.tap(dialogCloseBtn);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      debugPrint('  [BAŞARILI] QuickDownloadDialog tüm butonları ve efekt çipleriyle doğrulandı.');
    });

    testWidgets('8. İNDİRME YERİ 5: İndirilenler Kategorileri (Video & MP3 Kartları ve DownloadsScreen)', (
      WidgetTester tester,
    ) async {
      debugPrint('\n======================================================');
      debugPrint('[TEST 8] İndirme Yeri 5: İndirilenler Bölümü ve Kategorileri Test Ediliyor...');
      debugPrint('======================================================');
      await _ensureHomePage(tester);

      // Sayfayı aşağı kaydırarak İndirilenler kartlarını görünür yap
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -600));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('İNDİRİLENLER'), findsWidgets);
      expect(find.text('Video'), findsWidgets);
      expect(find.text('MP3'), findsWidgets);

      // Video Kategori Kartına Tıkla -> DownloadsScreen filtrelenmiş açılmalı
      final videoCardKey = find.byKey(const ValueKey('video_category_card'));
      await tester.ensureVisible(videoCardKey);
      await tester.tap(videoCardKey);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(DownloadsScreen), findsOneWidget);
      expect(find.text('Tümü'), findsOneWidget);
      expect(find.text('Videolar'), findsOneWidget);
      expect(find.text('Müzikler (MP3)'), findsOneWidget);
      debugPrint('  -> Video Kategori kartı DownloadsScreen ekranını başarıyla açtı.');

      // Geri dön
      Navigator.of(tester.element(find.byType(DownloadsScreen))).pop();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // MP3 Kategori Kartına Tıkla
      final audioCardKey = find.byKey(const ValueKey('audio_category_card'));
      await tester.ensureVisible(audioCardKey);
      await tester.tap(audioCardKey);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(DownloadsScreen), findsOneWidget);
      debugPrint('  -> MP3 Kategori kartı DownloadsScreen ekranını başarıyla açtı.');

      // Geri dön
      Navigator.of(tester.element(find.byType(DownloadsScreen))).pop();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Ana sayfaya dönüp testi sonlandır
      debugPrint('  [BAŞARILI] Tüm İndirme Yerleri, Platform Kartları ve İndirilenler Ekranı Eksiksiz Doğrulandı.');
      debugPrint('======================================================\n');
    });
  });
}
