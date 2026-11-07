import 'package:flutter/material.dart';

import '../admob_service.dart';
import '../services/micro_toast.dart';
import '../services/pro_server_reward_service.dart';

/// Ana Ekranda (HomeScreen) yer alan ve kullanıcının kısa bir ödüllü test videosu izleyerek
/// 3 indirme boyunca Pro Sunucuyu ve reklamsız modu aktif etmesini sağlayan ödül kartı.
class ProServerRewardCard extends StatefulWidget {
  const ProServerRewardCard({
    super.key,
    this.margin = const EdgeInsets.symmetric(vertical: 8),
  });

  final EdgeInsetsGeometry margin;

  @override
  State<ProServerRewardCard> createState() => _ProServerRewardCardState();
}

class _ProServerRewardCardState extends State<ProServerRewardCard> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    ProServerRewardService.instance.init();
  }

  Future<void> _handleWatchAd() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final isPremiumSubscribed = await AdmobService.instance.checkIsPremium();
      final currentCredits = await ProServerRewardService.instance.getCredits();

      // Zaten sınırsız premium üyesi ise kullanıcıya nazikçe bildir
      if (isPremiumSubscribed && currentCredits == 0) {
        if (!mounted) return;
        showMicroToast(
          context,
          message: 'Zaten aktif Premium üyesisiniz! Pro sunucu sınırsız kullanılabilir.',
          isSuccess: true,
        );
        return;
      }

      await AdmobService.instance.showProServerRewardAd(
        onRewardEarned: () async {
          final updatedCredits = await ProServerRewardService.instance
              .addCredits(3);
          if (!mounted) return;
          showMicroToast(
            context,
            message:
                '🎉 Tebrikler! 3 indirme boyunca Pro Sunucu aktif edildi! (Toplam hak: $updatedCredits)',
            isSuccess: true,
          );
        },
        onAdDismissedWithoutReward: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pro hak kazanmak için videoyu sonuna kadar izlemelisiniz.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        },
        onAdFailedToLoad: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Reklam yüklenemedi. Lütfen internet bağlantınızı kontrol edin.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('ProServerRewardCard hata: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const neonOrange = Color(0xFFFF5436);
    const cyanAccent = Color(0xFF20B8C5);

    return Container(
      key: const ValueKey('pro_server_reward_card'),
      margin: widget.margin,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2630) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: neonOrange.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: neonOrange.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: neonOrange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.rocket_launch_rounded,
                    color: neonOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '1 Kısa Video İzle, 3 İndirme Boyunca Pro Sunucuyu Aktif Et!',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable:
                  ProServerRewardService.instance.proCreditsNotifier,
              builder: (context, credits, _) {
                final isProActive = credits > 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isProActive
                        ? cyanAccent.withValues(alpha: 0.12)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFF4F6F8)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isProActive
                            ? Icons.check_circle_rounded
                            : Icons.flash_on_rounded,
                        size: 16,
                        color: isProActive
                            ? cyanAccent
                            : const Color(0xFF87949D),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isProActive
                              ? 'Pro Sunucu Aktif • Kalan Hak: $credits İndirme'
                              : 'Standart Sunucu • Videoyu izleyin, anında Pro hıza geçin!',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isProActive
                                ? cyanAccent
                                : const Color(0xFF87949D),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                key: const ValueKey('watch_pro_reward_button'),
                onPressed: _isLoading ? null : _handleWatchAd,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.play_circle_fill_rounded, size: 20),
                label: Text(
                  _isLoading
                      ? 'Reklam Hazırlanıyor…'
                      : 'VİDEOYU İZLE & PRO\'YU AÇ (+3 HAK)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: neonOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
