import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/admob_service.dart';
import 'package:vid_downloader_app/services/ad_frequency_policy.dart';
import 'package:vid_downloader_app/services/unified_download_engine.dart';
import 'package:vid_downloader_app/subscription_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 1, 1, 12);

  test('interstitial requires the third success and both time boundaries', () {
    bool allowed(int count, Duration launch, DateTime? last) =>
        AdFrequencyPolicy.canShowInterstitial(
          successfulOperations: count,
          sinceLaunch: launch,
          now: now,
          lastShown: last,
        );

    expect(allowed(3, const Duration(seconds: 59), null), isFalse);
    expect(allowed(1, const Duration(seconds: 60), null), isFalse);
    expect(allowed(2, const Duration(seconds: 60), null), isFalse);
    expect(allowed(3, const Duration(seconds: 60), null), isTrue);
    expect(
      allowed(
        6,
        const Duration(minutes: 5),
        now.subtract(const Duration(seconds: 179)),
      ),
      isFalse,
    );
    expect(
      allowed(
        6,
        const Duration(minutes: 5),
        now.subtract(const Duration(seconds: 180)),
      ),
      isTrue,
    );
    expect(allowed(4, const Duration(minutes: 5), null), isFalse);
    expect(
      allowed(
        3,
        const Duration(minutes: 5),
        now.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
  });

  test('app open cooldown includes exactly four hours', () {
    expect(AdFrequencyPolicy.canShowAppOpen(now, null), isTrue);
    expect(
      AdFrequencyPolicy.canShowAppOpen(
        now,
        now.subtract(const Duration(hours: 4)).add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
    expect(
      AdFrequencyPolicy.canShowAppOpen(
        now,
        now.subtract(const Duration(hours: 4)),
      ),
      isTrue,
    );
    expect(
      AdFrequencyPolicy.canShowAppOpen(
        now,
        now.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
  });

  test(
    'successful operation count persists and concurrent updates are serialized',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = AdmobService.instance;
      final counts = await Future.wait(
        List.generate(
          6,
          (_) => service.recordSuccessfulOperation(showInterstitial: false),
        ),
      );
      expect(counts, [1, 2, 3, 4, 5, 6]);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          'ad_successful_operations',
        ),
        6,
      );
      expect(
        await service.recordSuccessfulOperation(showInterstitial: false),
        7,
      );
    },
  );

  test('the operation count resumes from persisted state', () async {
    SharedPreferences.setMockInitialValues({'ad_successful_operations': 2});
    expect(
      await AdmobService.instance.recordSuccessfulOperation(
        showInterstitial: false,
      ),
      3,
    );
  });

  test('active subscription is detected and clears when removed', () async {
    SharedPreferences.setMockInitialValues({});
    await SubscriptionScreen.savePremiumStatus(
      DateTime.now().add(const Duration(days: 1)),
    );
    expect(await AdmobService.instance.hasActiveSubscription(), isTrue);
    await SubscriptionScreen.clearPremiumStatus();
    expect(await AdmobService.instance.hasActiveSubscription(), isFalse);
  });

  test('a rejected download does not increment the operation counter', () async {
    SharedPreferences.setMockInitialValues({});
    await expectLater(
      UnifiedDownloadEngine.instance.download(
        rawUrl: 'https://www.youtube.com/watch?v=example',
        type: 'video',
      ),
      throwsA(isA<Exception>()),
    );
    expect(
      (await SharedPreferences.getInstance()).getInt('ad_successful_operations'),
      isNull,
    );
  });
}
