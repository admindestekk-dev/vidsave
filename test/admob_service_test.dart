import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/admob_banner_widget.dart';
import 'package:vid_downloader_app/admob_native_ad_widget.dart';
import 'package:vid_downloader_app/admob_service.dart';
import 'package:vid_downloader_app/services/pro_server_reward_service.dart';
import 'package:vid_downloader_app/subscription_screen.dart';
import 'package:vid_downloader_app/widgets/pro_server_reward_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdmobService Architecture & Premium Filter Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('all ad formats use official Google test unit IDs', () {
      expect(
        AdmobService.bannerAdUnitId,
        'ca-app-pub-3940256099942544/6300978111',
      );
      expect(
        AdmobService.interstitialAdUnitId,
        'ca-app-pub-3940256099942544/1033173712',
      );
      expect(
        AdmobService.rewardedAdUnitId,
        'ca-app-pub-3940256099942544/5224354917',
      );
      expect(
        AdmobService.nativeAdUnitId,
        'ca-app-pub-3940256099942544/2247696110',
      );
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
      'UMP debug geography supports EEA, regulated US, and other regions',
      () {
        expect(
          AdmobService.debugGeographyFor('eea'),
          DebugGeography.debugGeographyEea,
        );
        expect(
          AdmobService.debugGeographyFor('regulated-us'),
          DebugGeography.debugGeographyRegulatedUsState,
        );
        expect(
          AdmobService.debugGeographyFor('other'),
          DebugGeography.debugGeographyOther,
        );
        expect(AdmobService.debugGeographyFor('unknown'), isNull);
      },
    );

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

    test('showInterstitialAd and showAppOpenAd bypass in test environment safely', () async {
      final interstitialShown = await AdmobService.instance.showInterstitialAd();
      expect(interstitialShown, isFalse);

      final appOpenShown = await AdmobService.instance.showAppOpenAdIfAvailable();
      expect(appOpenShown, isFalse);
    });

    testWidgets('AdmobBannerWidget renders SizedBox.shrink in test environment', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdmobBannerWidget(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdmobBannerWidget), findsOneWidget);
      expect(find.byType(AdWidget), findsNothing);
    });

    testWidgets('AdmobNativeAdWidget renders SizedBox.shrink in test environment', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdmobNativeAdWidget(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdmobNativeAdWidget), findsOneWidget);
      expect(find.byType(AdWidget), findsNothing);
    });

    test('ProServerRewardService adds and consumes credits correctly', () async {
      await ProServerRewardService.instance.clearCredits();
      expect(await ProServerRewardService.instance.getCredits(), 0);
      expect(await ProServerRewardService.instance.isProServerActive(), isFalse);

      final added = await ProServerRewardService.instance.addCredits(3);
      expect(added, 3);
      expect(await ProServerRewardService.instance.getCredits(), 3);
      expect(await ProServerRewardService.instance.isProServerActive(), isTrue);

      // checkIsPremium Pro kredisi varken true dönmeli
      expect(await AdmobService.instance.checkIsPremium(), isTrue);

      // 1 kredi harca
      final consumed = await ProServerRewardService.instance.consumeCredit();
      expect(consumed, isTrue);
      expect(await ProServerRewardService.instance.getCredits(), 2);

      await ProServerRewardService.instance.consumeCredit();
      await ProServerRewardService.instance.consumeCredit();
      expect(await ProServerRewardService.instance.getCredits(), 0);
      expect(await ProServerRewardService.instance.isProServerActive(), isFalse);

      // 0 iken tekrar harcanamaz
      expect(await ProServerRewardService.instance.consumeCredit(), isFalse);
    });

    testWidgets('ProServerRewardCard renders and watching ad grants 3 Pro credits', (tester) async {
      await ProServerRewardService.instance.clearCredits();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProServerRewardCard(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pro_server_reward_card')), findsOneWidget);
      expect(find.text('1 Kısa Video İzle, 3 İndirme Boyunca Pro Sunucuyu Aktif Et!'), findsOneWidget);
      expect(find.byKey(const ValueKey('watch_pro_reward_button')), findsOneWidget);

      // Butona dokun ve ödülü kazan
      await tester.tap(find.byKey(const ValueKey('watch_pro_reward_button')));
      await tester.pumpAndSettle();

      expect(await ProServerRewardService.instance.getCredits(), 3);
      expect(find.text('Pro Sunucu Aktif • Kalan Hak: 3 İndirme'), findsOneWidget);
    });
  });
}
