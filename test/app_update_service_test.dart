import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/remote_config_service.dart';
import 'package:vid_downloader_app/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdateService & Remote Config Update Integration Tests', () {
    setUp(() {
      RemoteConfigService.instance.clearOverrides();
    });

    tearDown(() {
      RemoteConfigService.instance.clearOverrides();
    });

    test('Default update parameters are initialized properly', () {
      final rc = RemoteConfigService.instance;
      expect(rc.latestAppVersion, '1.0.0');
      expect(rc.minRequiredVersion, '1.0.0');
      expect(rc.isForceUpdateEnabled, false);
      expect(rc.updateReleaseNotes, contains('video indirme'));
      expect(rc.playStoreUrl, contains('play.google.com'));
    });

    test(
      'When remote config reports a newer version, checkForUpdate flags update',
      () async {
        RemoteConfigService.instance.setOverride('latest_app_version', '1.2.0');
        RemoteConfigService.instance.setOverride(
          'min_required_version',
          '1.0.0',
        );
        RemoteConfigService.instance.setOverride(
          'force_update_enabled',
          'false',
        );

        final result = await AppUpdateService.instance.checkForUpdate();

        expect(result.hasUpdate, isTrue);
        expect(result.isMandatory, isFalse);
        expect(result.latestVersion, '1.2.0');
        expect(result.storeUrl, contains('play.google.com'));
      },
    );

    test(
      'When remote config min_required_version is higher, update is mandatory',
      () async {
        RemoteConfigService.instance.setOverride('latest_app_version', '2.0.0');
        RemoteConfigService.instance.setOverride(
          'min_required_version',
          '1.5.0',
        );
        RemoteConfigService.instance.setOverride(
          'force_update_enabled',
          'false',
        );

        final result = await AppUpdateService.instance.checkForUpdate();

        expect(result.hasUpdate, isTrue);
        expect(result.isMandatory, isTrue);
      },
    );

    test(
      'When remote force_update_enabled is true, update is mandatory',
      () async {
        RemoteConfigService.instance.setOverride('latest_app_version', '1.0.5');
        RemoteConfigService.instance.setOverride(
          'force_update_enabled',
          'true',
        );

        final result = await AppUpdateService.instance.checkForUpdate();

        expect(result.hasUpdate, isTrue);
        expect(result.isMandatory, isTrue);
      },
    );

    test(
      'When current version equals or exceeds remote, no update is flagged',
      () async {
        RemoteConfigService.instance.setOverride('latest_app_version', '1.0.0');
        RemoteConfigService.instance.setOverride(
          'min_required_version',
          '1.0.0',
        );
        RemoteConfigService.instance.setOverride(
          'force_update_enabled',
          'false',
        );

        final result = await AppUpdateService.instance.checkForUpdate();

        expect(result.hasUpdate, isFalse);
      },
    );
  });
}
