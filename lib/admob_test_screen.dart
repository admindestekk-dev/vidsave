import 'package:flutter/material.dart';

import 'admob_banner_widget.dart';
import 'admob_native_ad_widget.dart';

class AdmobTestScreen extends StatelessWidget {
  const AdmobTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AdMob test reklamları')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'Google test reklam birimleri kullanılır. Geçiş ve açılış '
            'reklamları yalnızca uygulamanın sıklık ve Premium kurallarına '
            'uygun olduğunda gösterilir.',
          ),
          SizedBox(height: 16),
          AdmobBannerWidget(),
          AdmobNativeAdWidget(),
        ],
      ),
    );
  }
}
