import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/app_dio.dart';
import 'package:vid_downloader_app/download_exception_handler.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/remote_config_service.dart';
import 'package:vid_downloader_app/universal_scraper.dart';

void main() {
  group('1. Global Kazıyıcı Motor Yapılandırması (universal_scraper.dart)', () {
    late UniversalScraper scraper;

    setUp(() {
      scraper = UniversalScraper();
    });

    tearDown(() {
      scraper.dispose();
    });

    test('Dio motoru istenen kalıcı ayarlarla yapılandırılmıştır', () {
      final options = scraper.dio.options;

      // followRedirects: true
      expect(options.followRedirects, isTrue);

      // maxRedirects: 8
      expect(options.maxRedirects, equals(8));

      // validateStatus: (status) => status! < 500
      expect(options.validateStatus(200), isTrue);
      expect(options.validateStatus(400), isTrue);
      expect(options.validateStatus(403), isTrue);
      expect(options.validateStatus(404), isTrue);
      expect(options.validateStatus(499), isTrue);
      expect(options.validateStatus(500), isFalse);
      expect(options.validateStatus(502), isFalse);

      // Headers: User-Agent, Sec-Fetch-Mode: navigate
      expect(options.headers['User-Agent'], equals(kUniversalDesktopUserAgent));
      expect(options.headers['Sec-Fetch-Mode'], equals('navigate'));
      expect(options.headers['Sec-Fetch-Site'], equals('cross-site'));
    });

    test('Dinamik Interceptor platform bazlı Referer ve Origin başlıklarını üretir', () async {
      final dio = scraper.dio;
      RequestOptions? capturedOptions;

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            capturedOptions = opts;
            handler.resolve(
              Response(
                requestOptions: opts,
                statusCode: 200,
                data: '<html>ok</html>',
              ),
            );
          },
        ),
      );

      // TikTok
      await dio.get<dynamic>('https://www.tiktok.com/@user/video/123');
      expect(capturedOptions?.headers['Referer'], 'https://www.tiktok.com/');
      expect(capturedOptions?.headers['Origin'], 'https://www.tiktok.com');

      // Instagram
      await dio.get<dynamic>('https://www.instagram.com/reel/xyz/');
      expect(capturedOptions?.headers['Referer'], 'https://www.instagram.com/');
      expect(capturedOptions?.headers['Origin'], 'https://www.instagram.com');

      // Facebook
      await dio.get<dynamic>('https://www.facebook.com/watch/?v=999');
      expect(capturedOptions?.headers['Referer'], 'https://www.facebook.com/');
      expect(capturedOptions?.headers['Origin'], 'https://www.facebook.com');

      // Pinterest
      await dio.get<dynamic>('https://www.pinterest.com/pin/123/');
      expect(capturedOptions?.headers['Referer'], 'https://www.pinterest.com/');
      expect(capturedOptions?.headers['Origin'], 'https://www.pinterest.com');

      // Twitter / X
      await dio.get<dynamic>('https://twitter.com/user/status/456');
      expect(capturedOptions?.headers['Referer'], 'https://twitter.com/');
      expect(capturedOptions?.headers['Origin'], 'https://twitter.com');

      // Vimeo
      await dio.get<dynamic>('https://vimeo.com/789');
      expect(capturedOptions?.headers['Referer'], 'https://vimeo.com/');
      expect(capturedOptions?.headers['Origin'], 'https://vimeo.com');

      // Dailymotion
      await dio.get<dynamic>('https://www.dailymotion.com/video/x123');
      expect(
        capturedOptions?.headers['Referer'],
        'https://www.dailymotion.com/',
      );
      expect(capturedOptions?.headers['Origin'], 'https://www.dailymotion.com');
    });

    test('CookieManager oturum çerezlerini hafızadan okuyup Cookie başlığına enjekte eder', () async {
      final jar = InMemoryCookieJar();
      final cookieManager = UniversalCookieManager(memoryJar: jar);
      final scraperWithJar = UniversalScraper(cookieManager: cookieManager);

      // Instagram oturum çerezleri
      cookieManager.saveCookie(
        'instagram.com',
        'sessionid',
        'mock_session_123',
      );
      cookieManager.saveCookie('instagram.com', 'ds_user_id', '987654');

      RequestOptions? captured;
      scraperWithJar.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: 'ok'),
            );
          },
        ),
      );

      await scraperWithJar.dio.get<dynamic>(
        'https://www.instagram.com/p/mock/',
      );

      expect(
        captured?.headers['Cookie'],
        contains('sessionid=mock_session_123'),
      );
      expect(captured?.headers['Cookie'], contains('ds_user_id=987654'));
    });
  });

  group('2. Evrensel URL Temizlik Kalkanı (evrenselTemizUrlShield)', () {
    test('Tırnak işaretlerini (" veya \') otomatik ayıklar', () {
      expect(
        evrenselTemizUrlShield('"https://example.com/video.mp4"'),
        'https://example.com/video.mp4',
      );
      expect(
        evrenselTemizUrlShield("'https://example.com/audio.mp3'"),
        'https://example.com/audio.mp3',
      );
    });

    test(r'JSON kaçış çizgilerini (\/) ve Unicode (\u002F, \u0026) kalıntılarını temizler', () {
      const rawJson =
          r'https:\/\/v16-webapp.tiktokcdn.com\/video\/test.mp4?param=1\u0026v=2';
      expect(
        evrenselTemizUrlShield(rawJson),
        'https://v16-webapp.tiktokcdn.com/video/test.mp4?param=1&v=2',
      );
    });

    test('Metin kalıntısı "u002F" durumunu tamir eder', () {
      const raw = 'https://u002F/u002Fv16-webapp-prime.tiktokcdn.com/video.mp4';
      expect(
        evrenselTemizUrlShield(raw),
        'https://v16-webapp-prime.tiktokcdn.com/video.mp4',
      );
    });

    test('Eksik protokollerin başına https: ekler ve protokol anomalilerini düzeltir', () {
      expect(
        evrenselTemizUrlShield('//v16.tiktokcdn.com/video.mp4'),
        'https://v16.tiktokcdn.com/video.mp4',
      );
      expect(
        evrenselTemizUrlShield('https:///v16.tiktokcdn.com/video.mp4'),
        'https://v16.tiktokcdn.com/video.mp4',
      );
      expect(
        evrenselTemizUrlShield('https:/v16.tiktokcdn.com/video.mp4'),
        'https://v16.tiktokcdn.com/video.mp4',
      );
      expect(
        evrenselTemizUrlShield('instagram.com/reel/12345'),
        'https://instagram.com/reel/12345',
      );
    });
  });

  group('3. Platform Kazıyıcıları & Regex Çözümleme Testleri', () {
    test(
      'TikTok HTML içindeki script regexleri ve download_url kalıplarını çözer',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (opts, handler) {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: '''
                <html>
                  <script id="SIGI_STATE">
                    {"ItemModule":{"123":{"playAddr":"https:\\/\\/v16-webapp.tiktokcdn.com\\/video.mp4"}}}
                  </script>
                </html>
                ''',
                ),
              );
            },
          ),
        );

        final scraper = UniversalScraper(dioClient: dio);
        final result = await scraper.extractTikTok(
          Uri.parse('https://www.tiktok.com/@test/video/123'),
        );

        expect(
          result.url.toString(),
          'https://v16-webapp.tiktokcdn.com/video.mp4',
        );
        expect(result.fileName.endsWith('.mp4'), isTrue);
      },
    );

    test('TikTok TikWM API yanıtını başarıyla ayrıştırır', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            if (opts.uri.toString().contains('tikwm.com/api')) {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: {
                    'code': 0,
                    'msg': 'success',
                    'data': {
                      'id': '7106594312292453678',
                      'title': 'Test TikTok Video',
                      'play': 'https://www.tikwm.com/video/media/play/test.mp4',
                    },
                  },
                ),
              );
            } else {
              handler.next(opts);
            }
          },
        ),
      );

      final scraper = UniversalScraper(dioClient: dio);
      final result = await scraper.extractTikTok(
        Uri.parse('https://www.tiktok.com/@tiktok/video/7106594312292453678'),
      );

      expect(
        result.url.toString(),
        'https://www.tikwm.com/video/media/play/test.mp4',
      );
      expect(result.fileName.contains('Test TikTok Video'), isTrue);
      expect(result.fileName.endsWith('.mp4'), isTrue);
    });

    test(
      'Pinterest HTML içindeki download_url veya mp4 regexini çözer',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (opts, handler) {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: '''
                <html>
                  <script>
                    var data = {"download_url":"https:\\/\\/v.pinimg.com\\/videos\\/mc\\/720p\\/pin.mp4"};
                  </script>
                </html>
                ''',
                ),
              );
            },
          ),
        );

        final scraper = UniversalScraper(dioClient: dio);
        final result = await scraper.extractPinterest(
          Uri.parse('https://pin.it/abc'),
        );

        expect(
          result.url.toString(),
          'https://v.pinimg.com/videos/mc/720p/pin.mp4',
        );
        expect(result.fileName.endsWith('.mp4'), isTrue);
      },
    );

    test('Twitter HTML içindeki twimg video regexini çözer', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            handler.resolve(
              Response(
                requestOptions: opts,
                statusCode: 200,
                data: '''
                <html>
                  <meta property="og:video:url" content="https://video.twimg.com/ext_tw_video/123/pu/vid/720x1280/clip.mp4" />
                </html>
                ''',
              ),
            );
          },
        ),
      );

      final scraper = UniversalScraper(dioClient: dio);
      final result = await scraper.extractTwitter(
        Uri.parse('https://x.com/user/status/123'),
      );

      expect(result.url.toString(), contains('video.twimg.com'));
      expect(result.fileName.endsWith('.mp4'), isTrue);
    });

    test(
      'Facebook HTML içindeki playable_url_quality_hd regexini çözer',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (opts, handler) {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: r'''
                <html>
                  <script>
                    "playable_url_quality_hd":"https:\/\/video.xx.fbcdn.net\/v\/t39\/fb_hd.mp4"
                  </script>
                </html>
                ''',
                ),
              );
            },
          ),
        );

        final scraper = UniversalScraper(dioClient: dio);
        final result = await scraper.extractFacebook(
          Uri.parse('https://www.facebook.com/watch/?v=123'),
        );

        expect(
          result.url.toString(),
          'https://video.xx.fbcdn.net/v/t39/fb_hd.mp4',
        );
        expect(result.fileName.endsWith('.mp4'), isTrue);
      },
    );

    test('Facebook reel HTML içindeki browser_native_hd_url regexini çözer', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            handler.resolve(
              Response(
                requestOptions: opts,
                statusCode: 200,
                data: r'''
                <html>
                  <script>
                    "browser_native_hd_url":"https:\/\/video.fna.fbcdn.net\/v\/t39\/reel_hd.mp4?_nc_cat=101\u0026efg=xyz"
                  </script>
                </html>
                ''',
              ),
            );
          },
        ),
      );

      final scraper = UniversalScraper(dioClient: dio);
      final result = await scraper.extractFacebook(
        Uri.parse('https://www.facebook.com/reel/1065415035800269'),
      );

      expect(
        result.url.toString(),
        'https://video.fna.fbcdn.net/v/t39/reel_hd.mp4?_nc_cat=101&efg=xyz',
      );
      expect(result.fileName.contains('1065415035800269'), isTrue);
      expect(result.fileName.endsWith('.mp4'), isTrue);
    });

    test('Vimeo progressive JSON config formatını çözer', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            handler.resolve(
              Response(
                requestOptions: opts,
                statusCode: 200,
                data: {
                  'request': {
                    'files': {
                      'progressive': [
                        {
                          'quality': '1080p',
                          'url': 'https://vod-progressive.akamaized.net/vimeo_1080p.mp4',
                        },
                      ],
                    },
                  },
                },
              ),
            );
          },
        ),
      );

      final scraper = UniversalScraper(dioClient: dio);
      final result = await scraper.extractVimeo(
        Uri.parse('https://vimeo.com/123456'),
      );

      expect(
        result.url.toString(),
        'https://vod-progressive.akamaized.net/vimeo_1080p.mp4',
      );
    });

    test('Vimeo ham HTML ve progressive Regex cımbızıyla String veriyi çözer (Map cast hatası yok)', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            // Sunucunun JSON yerine düz ham String (HTML metni) döndürdüğü senaryo
            const rawHtml = '''
              <!DOCTYPE html>
              <html>
              <head><title>Vimeo Video</title></head>
              <body>
                <script>
                  window.playerConfig = {
                    "request": {
                      "files": {
                        "progressive":[
                          {"profile":"112","width":640,"height":360,"mime":"video/mp4","fps":30,"url":"https://player.vimeo.com/progressive_redirect/download/123456/rendition/360p/file.mp4","cdn":"fastly","quality":"360p","id":"p360"},
                          {"profile":"119","width":1920,"height":1080,"mime":"video/mp4","fps":60,"file_code":"xyz","url":"https://player.vimeo.com/progressive_redirect/download/123456/rendition/1080p/file_code_1080p.mp4","cdn":"fastly","quality":"1080p","id":"p1080"}
                        ]
                      }
                    }
                  };
                </script>
              </body>
              </html>
            ''';

            handler.resolve(
              Response(
                requestOptions: opts,
                statusCode: 200,
                data: rawHtml, // Düz String metin! (Map<String, dynamic> değil)
              ),
            );
          },
        ),
      );

      final scraper = UniversalScraper(dioClient: dio);
      final result = await scraper.extractVimeo(
        Uri.parse('https://vimeo.com/123456'),
      );

      // En yüksek kalite (1080p) linki cımbızlanmalı
      expect(
        result.url.toString(),
        'https://player.vimeo.com/progressive_redirect/download/123456/rendition/1080p/file_code_1080p.mp4',
      );
      expect(result.fileName.startsWith('vimeo_123456_'), isTrue);
      expect(result.fileName.endsWith('.mp4'), isTrue);
    });

    test('Dailymotion metadata JSON formatını çözer', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            handler.resolve(
              Response(
                requestOptions: opts,
                statusCode: 200,
                data: {
                  'qualities': {
                    'auto': [
                      {
                        'type': 'video/mp4',
                        'url': 'https://www.dailymotion.com/cdn/dm_video.mp4',
                      },
                    ],
                  },
                },
              ),
            );
          },
        ),
      );

      final scraper = UniversalScraper(dioClient: dio);
      final result = await scraper.extractDailymotion(
        Uri.parse('https://www.dailymotion.com/video/x8mock'),
      );

      expect(
        result.url.toString(),
        'https://www.dailymotion.com/cdn/dm_video.mp4',
      );
    });

    test('Instagram reel köprü çözümleyici ile og:video ve doğrudan CDN mp4 adresini çözer', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            final uriStr = opts.uri.toString();
            if (uriStr.contains('eeinstagram.com/reel/TEST_SHORTCODE') ||
                uriStr.contains('vxinstagram.com/reel/TEST_SHORTCODE')) {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: '''
                  <!DOCTYPE html>
                  <html>
                  <head>
                    <meta property="og:video" content="https://scontent.cdninstagram.com/o1/v/t2/test_reel.mp4" />
                  </head>
                  <body></body>
                  </html>
                  ''',
                ),
              );
            } else {
              handler.next(opts);
            }
          },
        ),
      );

      final scraper = UniversalScraper(dioClient: dio);
      final result = await scraper.extractInstagram(
        Uri.parse('https://www.instagram.com/reel/TEST_SHORTCODE/'),
      );

      expect(
        result.url.toString(),
        'https://scontent.cdninstagram.com/o1/v/t2/test_reel.mp4',
      );
      expect(result.fileName.contains('TEST_SHORTCODE'), isTrue);
      expect(result.fileName.endsWith('.mp4'), isTrue);
      expect(result.downloadHeaders['Referer'], 'https://www.instagram.com/');
    });

    test(
      'resolve() tüm çıktıları evrenselTemizUrlShield süzgecinden geçirir',
      () async {
        final dio = Dio();
        final scraper = UniversalScraper(dioClient: dio);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (opts, handler) {
              if (opts.method == 'HEAD') {
                handler.resolve(
                  Response(
                    requestOptions: opts,
                    statusCode: 200,
                    headers: Headers.fromMap({
                      'content-type': ['video/mp4'],
                      'content-length': ['5242880'], // 5 MB
                    }),
                  ),
                );
              } else {
                handler.next(opts);
              }
            },
          ),
        );

        final sample = Uri.parse('https://example.com/test.mp4');
        final resolved = await scraper.resolve(sample, DownloadKind.video);

        expect(resolved.url.isScheme('https'), isTrue);
        expect(resolved.downloadHeaders.isNotEmpty, isTrue);
      },
    );
  });

  group('4. Evrensel Hata Yakalama ve Regex Fallback (Emniyet Supabı) Testleri', () {
    test('extractWithRegexFallback ham HTML içindeki .mp4 linkini başarıyla cımbızlar', () async {
      final dio = Dio();
      final scraper = UniversalScraper(dioClient: dio);

      const mockHtml = '''
        <html>
          <div>Bazı bozuk scriptler...</div>
          <script>
            var config = {
              "video_url": "https:\\/\\/cdn.example.com\\/videos\\/source_video.mp4?token=123"
            };
          </script>
        </html>
      ''';

      final result = await scraper.extractWithRegexFallback(
        Uri.parse('https://example.com/video_post'),
        DownloadKind.video,
        rawData: mockHtml,
      );

      expect(result.url.toString(), 'https://cdn.example.com/videos/source_video.mp4?token=123');
      expect(result.fileName.endsWith('.mp4'), isTrue);
    });

    test('extractWithRegexFallback ham HTML içindeki .mp3 ses linkini başarıyla cımbızlar', () async {
      final dio = Dio();
      final scraper = UniversalScraper(dioClient: dio);

      const mockHtml = '''
        <html>
          <audio src="https://cdn.example.com/music/track_audio.mp3"></audio>
        </html>
      ''';

      final result = await scraper.extractWithRegexFallback(
        Uri.parse('https://example.com/audio_post'),
        DownloadKind.audio,
        rawData: mockHtml,
      );

      expect(result.url.toString(), 'https://cdn.example.com/music/track_audio.mp3');
      expect(result.fileName.endsWith('.mp3'), isTrue);
    });

    test('Ana çözümleyici DioException aldığında otomatik Regex Fallback devreye girer', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            // Ana TikTok isteklerinde hata simülasyonu yap ama HTML'de yedek video linki barındır
            handler.resolve(
              Response(
                requestOptions: opts,
                statusCode: 200,
                data: '''
                <html>
                  <script>
                    var obj = {"download_url": "https://cdn.fallback.com/video/recovered.mp4"};
                  </script>
                </html>
                ''',
              ),
            );
          },
        ),
      );

      final scraper = UniversalScraper(dioClient: dio);
      // TikTok regex kalıpları eşleşmese bile fallback devreye girip linki cımbızlar
      final result = await scraper.resolve(
        Uri.parse('https://www.tiktok.com/@user/video/fallback_test'),
        DownloadKind.video,
      );

      expect(result.url.toString(), contains('recovered.mp4'));
    });

    test('DownloadExceptionHandler DioException, FormatException ve TypeError için güvenli mesaj üretir', () {
      final dioTimeout = DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionTimeout,
      );
      expect(
        DownloadExceptionHandler.getFriendlyMessage(dioTimeout, null),
        contains('zaman aşımına'),
      );

      final dioForbidden = DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: RequestOptions(path: ''), statusCode: 403),
      );
      expect(
        DownloadExceptionHandler.getFriendlyMessage(dioForbidden, null),
        contains('403 Forbidden'),
      );

      final formatErr = const FormatException('Invalid JSON format');
      expect(
        DownloadExceptionHandler.getFriendlyMessage(formatErr, null),
        contains('ayrıştırılamadı'),
      );

      final typeErr = TypeError();
      expect(
        DownloadExceptionHandler.getFriendlyMessage(typeErr, null),
        contains('formatta'),
      );
    });
  });

  group('5. Firebase Remote Config & Dinamik Regex & Backend Fallback Testleri', () {
    test('RemoteConfigService varsayılan fallback değerleri eksiksiz tanımlıdır', () {
      final service = RemoteConfigService.instance;
      expect(service.tiktokRegex.isNotEmpty, isTrue);
      expect(service.instagramRegex.isNotEmpty, isTrue);
      expect(service.facebookRegex.isNotEmpty, isTrue);
      expect(service.twitterRegex.isNotEmpty, isTrue);
      expect(service.pinterestRegex.isNotEmpty, isTrue);
      expect(service.userAgent.isNotEmpty, isTrue);
    });

    test('RemoteConfigService setOverride ile dinamik regex güncellenebilir', () {
      final service = RemoteConfigService.instance;
      service.setOverride('tiktok_regex', r'"custom_remote_url":"(.*?)"');
      expect(service.tiktokRegex, equals(r'"custom_remote_url":"(.*?)"'));
      service.clearOverrides();
    });

    test('Lokal motor ve regex fallback başarısız olursa backup_api_url Python backend devreye girer', () async {
      final dio = Dio();
      final scraper = UniversalScraper(dioClient: dio);

      RemoteConfigService.instance.setOverride('backup_api_url', 'https://api.vidsave.fake/backend');

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            final uri = opts.uri.toString();
            // Eğer backup api isteğiyse başarılı yanıt simüle et
            if (uri.contains('/api/resolve')) {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: {
                    'status': 'ok',
                    'url': 'https://storage.vidsave.fake/videos/python_resolved_video.mp4',
                    'title': 'Garantili Python Video',
                  },
                ),
              );
            } else {
              // Lokal istek başarısız olsun ve boş/bozuk veri döndürsün
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: '<html>Bozuk ve link içermeyen sayfa</html>',
                ),
              );
            }
          },
        ),
      );

      final result = await scraper.resolve(
        Uri.parse('https://www.tiktok.com/@user/video/fail_case'),
        DownloadKind.video,
      );

      expect(result.url.toString(), 'https://storage.vidsave.fake/videos/python_resolved_video.mp4');
      expect(result.fileName, contains('Garantili Python Video'));

      RemoteConfigService.instance.clearOverrides();
    });

    test('3 Aşamalı Güvenlik Kalkanı: HEAD yanıtında text/html tespit edildiğinde yedek hat devreye girer', () async {
      final dio = Dio();
      final scraper = UniversalScraper(dioClient: dio);

      RemoteConfigService.instance.setOverride('backup_api_url', 'https://api.vidsave.fake/backend');

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            final uri = opts.uri.toString();
            if (opts.method == 'HEAD' && uri.contains('tiktokcdn.com')) {
              // Bot koruması: platform HTML sayfası döndürüyor (sahte dosya tuzağı)
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  headers: Headers.fromMap({
                    'content-type': ['text/html; charset=utf-8'],
                    'content-length': ['12450'], // 12 KB HTML hata sayfası
                  }),
                ),
              );
            } else if (uri.contains('/api/resolve')) {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: {
                    'status': 'ok',
                    'url': 'https://storage.vidsave.fake/videos/python_repaired.mp4',
                    'title': 'Onarilmis Guvenli Video',
                  },
                ),
              );
            } else if (uri.contains('tiktok.com')) {
              // Sayfa HTML'i içinde sahte video linki var
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: '<html>"playAddr":"https://v16-webapp-prime.tiktokcdn.com/bot_trap.mp4"</html>',
                ),
              );
            } else {
              handler.next(opts);
            }
          },
        ),
      );

      final result = await scraper.resolve(
        Uri.parse('https://www.tiktok.com/@user/video/bot_trap_case'),
        DownloadKind.video,
      );

      // Bot korumalı sahte link HEAD denetiminde elenip Remote Config backup_api_url hattından garantili çözülmeli
      expect(result.url.toString(), 'https://storage.vidsave.fake/videos/python_repaired.mp4');
      expect(result.fileName, contains('Onarilmis Guvenli Video'));

      RemoteConfigService.instance.clearOverrides();
    });

    test('3 Aşamalı Güvenlik Kalkanı: HEAD yanıtında dosya boyutu 1 MB altı (<1024*1024) tespit edildiğinde yedek hat devreye girer', () async {
      final dio = Dio();
      final scraper = UniversalScraper(dioClient: dio);

      RemoteConfigService.instance.setOverride('backup_api_url', 'https://api.vidsave.fake/backend');

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            final uri = opts.uri.toString();
            if (opts.method == 'HEAD' && uri.contains('tiny_video.mp4')) {
              // 50 KB sahte video / hata sayfası
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  headers: Headers.fromMap({
                    'content-type': ['video/mp4'],
                    'content-length': ['51200'], // 50 KB (< 1 MB)
                  }),
                ),
              );
            } else if (uri.contains('/api/resolve')) {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: {
                    'status': 'ok',
                    'url': 'https://storage.vidsave.fake/videos/python_repaired_size.mp4',
                    'title': 'Onarilmis Boyut Guvenli Video',
                  },
                ),
              );
            } else if (uri.contains('instagram.com')) {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: '<html><meta property="og:video" content="https://instagram.com/cdn/tiny_video.mp4" /></html>',
                ),
              );
            } else {
              handler.next(opts);
            }
          },
        ),
      );

      final result = await scraper.resolve(
        Uri.parse('https://www.instagram.com/reel/tiny_reel/'),
        DownloadKind.video,
      );

      expect(result.url.toString(), 'https://storage.vidsave.fake/videos/python_repaired_size.mp4');
      expect(result.fileName, contains('Onarilmis Boyut Guvenli Video'));

      RemoteConfigService.instance.clearOverrides();
    });
  });
}
