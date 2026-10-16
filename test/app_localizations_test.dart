import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/app_localizations.dart';

void main() {
  group('AppLocalizations & Global Language Support', () {
    test('Turkish locale returns Turkish strings', () {
      final l10n = AppLocalizations(const Locale('tr'));
      expect(l10n.text('nav_videos'), 'Videolar');
      expect(l10n.text('nav_music'), 'Müzik');
      expect(l10n.text('downloads_screen_title'), 'İndirilenler');
      expect(l10n.isRtl, isFalse);
    });

    test('English locale returns English strings', () {
      final l10n = AppLocalizations(const Locale('en'));
      expect(l10n.text('nav_videos'), 'Videos');
      expect(l10n.text('nav_music'), 'Music');
      expect(l10n.text('downloads_screen_title'), 'Downloads');
      expect(l10n.isRtl, isFalse);
    });

    test('German locale returns German strings', () {
      final l10n = AppLocalizations(const Locale('de'));
      expect(l10n.text('nav_videos'), 'Videos');
      expect(l10n.text('nav_music'), 'Musik');
      expect(l10n.text('downloads_screen_title'), 'Downloads');
    });

    test('Spanish locale returns Spanish strings', () {
      final l10n = AppLocalizations(const Locale('es'));
      expect(l10n.text('nav_videos'), 'Videos');
      expect(l10n.text('nav_music'), 'Música');
      expect(l10n.text('downloads_screen_title'), 'Descargas');
    });

    test('Arabic (RTL) locale returns Arabic strings and isRtl is true', () {
      final l10n = AppLocalizations(const Locale('ar'));
      expect(l10n.text('nav_videos'), 'فيديوهات');
      expect(l10n.text('nav_music'), 'موسيقى');
      expect(l10n.text('downloads_screen_title'), 'التنزيلات');
      expect(l10n.isRtl, isTrue);
    });

    test('Persian (RTL) locale returns Persian strings and isRtl is true', () {
      final l10n = AppLocalizations(const Locale('fa'));
      expect(l10n.text('nav_videos'), 'ویدیوها');
      expect(l10n.text('nav_music'), 'موسیقی');
      expect(l10n.isRtl, isTrue);
    });

    test('Unknown world language (e.g. Swahili sw) falls back gracefully to English', () {
      final l10n = AppLocalizations(const Locale('sw'));
      expect(l10n.text('nav_videos'), 'Videos');
      expect(l10n.text('nav_music'), 'Music');
      expect(l10n.text('downloads_screen_title'), 'Downloads');
      expect(l10n.isRtl, isFalse);
    });
  });
}
