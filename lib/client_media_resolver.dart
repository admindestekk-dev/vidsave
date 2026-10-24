import 'dart:async';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_exp;

import 'media_downloader.dart';
import 'universal_scraper.dart';

/// Sent on requests to perfectly mimic Chrome on Android and avoid 403 Forbidden / bot detection.
const Map<String, String> kChromeMobileHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
  'Accept': '*/*',
  'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
  'Connection': 'keep-alive',
};

/// Client-side media resolver powered by the UniversalScraper engine.
///
/// Fully decentralized and serverless:
/// 1. YouTube & MP3: Uses youtube_explode_dart streamsClient to fetch manifests,
///    audio-only streams, and highest resolution video streams.
/// 2. TikTok, Pinterest, Twitter (X): Follows redirects, fetches raw HTML, and extracts
///    mp4/jpg using local script regex parsing.
/// 3. Instagram & Facebook: Injects session cookies from CookieManager (InAppWebView / storage)
///    to bypass 403 bot and access barriers at zero cost.
/// 4. Vimeo & Dailymotion: Resolves progressive mp4 stream manifests locally.
class ClientMediaResolver implements MediaResolver {
  ClientMediaResolver({
    Dio? dioClient,
    yt_exp.YoutubeExplode? youtubeExplode,
    UniversalScraper? scraper,
  }) : _scraper = scraper ??
            (dioClient != null || youtubeExplode != null
                ? UniversalScraper(
                    dioClient: dioClient,
                    youtubeExplode: youtubeExplode,
                  )
                : UniversalScraper.instance);

  final UniversalScraper _scraper;

  UniversalScraper get scraper => _scraper;
  Dio get dio => _scraper.dio;
  yt_exp.YoutubeExplode get yt => _scraper.yt;

  void dispose() {
    _scraper.dispose();
  }

  @override
  Future<List<SearchResultItem>> search(String query) => _scraper.search(query);

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) =>
      _scraper.preview(source, kind);

  @override
  Future<ResolvedMedia> resolve(
    Uri source,
    DownloadKind kind, {
    int? height,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) =>
      _scraper.resolve(
        source,
        kind,
        height: height,
        startTime: startTime,
        endTime: endTime,
        audioEffect: audioEffect,
      );
}
