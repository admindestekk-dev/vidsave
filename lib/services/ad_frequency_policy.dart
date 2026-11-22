class AdFrequencyPolicy {
  static const startupGrace = Duration(seconds: 60);
  static const interstitialCooldown = Duration(seconds: 180);
  static const appOpenCooldown = Duration(hours: 4);

  static bool canShowInterstitial({
    required int successfulOperations,
    required Duration sinceLaunch,
    required DateTime now,
    required DateTime? lastShown,
  }) {
    return successfulOperations > 0 &&
        successfulOperations % 3 == 0 &&
        sinceLaunch >= startupGrace &&
        (lastShown == null ||
            now.difference(lastShown) >= interstitialCooldown);
  }

  static bool canShowAppOpen(DateTime now, DateTime? lastShown) =>
      lastShown == null || now.difference(lastShown) >= appOpenCooldown;
}
