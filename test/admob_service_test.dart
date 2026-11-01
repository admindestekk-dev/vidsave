import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/admob_service.dart';
import 'package:vid_downloader_app/subscription_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdmobService Architecture & Premium Filter Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('all ad formats use official Google test unit IDs', () {
      expect(
        AdmobService.rewardedAdUnitId,
        AdmobService.testAdUnitId('rewarded'),
      );
      expect(AdmobService.testAdUnitIds['android'], {
        'banner': 'ca-app-pub-3940256099942544/6300978111',
        'interstitial': 'ca-app-pub-3940256099942544/1033173712',
        'rewarded': 'ca-app-pub-3940256099942544/5224354917',
        'native': 'ca-app-pub-3940256099942544/2247696110',
        'appOpen': 'ca-app-pub-3940256099942544/9257395921',
      });
      expect(AdmobService.testAdUnitIds['ios'], {
        'banner': 'ca-app-pub-3940256099942544/2934735716',
        'interstitial': 'ca-app-pub-3940256099942544/4411468910',
        'rewarded': 'ca-app-pub-3940256099942544/1712485313',
        'native': 'ca-app-pub-3940256099942544/3986624511',
        'appOpen': 'ca-app-pub-3940256099942544/5575463023',
      });
    });

    test(
      'checkIsPremium returns false by default for free/guest users',
      () async {
        final isPrem = await AdmobService.instance.checkIsPremium();
        expect(isPrem, isFalse);
      },
    );

    test('checkIsPremium returns true when subscription is active in SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SubscriptionScreen.prefKeyIsPremium, true);
      await prefs.setString(
        SubscriptionScreen.prefKeyPremiumUntil,
        '2099-12-31T23:59:59Z',
      );

      final isPrem = await AdmobService.instance.checkIsPremium();
      expect(isPrem, isTrue);
    });

    test('expired premium status is cleared and does not bypass ads', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SubscriptionScreen.prefKeyIsPremium, true);
      await prefs.setString(
        SubscriptionScreen.prefKeyPremiumUntil,
        '2000-01-01T00:00:00Z',
      );

      expect(await AdmobService.instance.checkIsPremium(), isFalse);
      expect(prefs.getBool(SubscriptionScreen.prefKeyIsPremium), isNull);
    });

    test(
      'showRewardedAdOrBypass bypasses AdMob directly when isPremium == true',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(SubscriptionScreen.prefKeyIsPremium, true);
        await prefs.setString(
          SubscriptionScreen.prefKeyPremiumUntil,
          '2099-12-31T23:59:59Z',
        );

        bool downloadCallbackCalled = false;
        await AdmobService.instance.showRewardedAdOrBypass(
          onRewardEarned: () {
            downloadCallbackCalled = true;
          },
        );

        expect(downloadCallbackCalled, isTrue);
      },
    );
  });
}
