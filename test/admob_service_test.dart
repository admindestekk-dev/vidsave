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

    test('AdmobService constants and rewardedAdUnitId match official Google test id', () {
      expect(
        AdmobService.rewardedAdUnitId,
        'ca-app-pub-3940256099942544/5224354917',
      );
    });

    test('checkIsPremium returns false by default for free/guest users', () async {
      final isPrem = await AdmobService.instance.checkIsPremium();
      expect(isPrem, isFalse);
    });

    test('checkIsPremium returns true when subscription is active in SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SubscriptionScreen.prefKeyIsPremium, true);

      final isPrem = await AdmobService.instance.checkIsPremium();
      expect(isPrem, isTrue);
    });

    test('showRewardedAdOrBypass bypasses AdMob directly when isPremium == true', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SubscriptionScreen.prefKeyIsPremium, true);

      bool downloadCallbackCalled = false;
      await AdmobService.instance.showRewardedAdOrBypass(
        onRewardEarned: () {
          downloadCallbackCalled = true;
        },
      );

      expect(downloadCallbackCalled, isTrue);
    });
  });
}
