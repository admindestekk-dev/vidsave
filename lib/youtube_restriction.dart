import 'package:flutter/material.dart';

import 'media_downloader.dart';

const String youtubeRestrictionMessage =
    'Yasal kısıtlamalar nedeniyle YouTube videoları İNDİRİLEMEMEKTEDİR.';

bool isYouTubeUrl(String input) {
  final value = input.trim();
  if (value.isEmpty) return false;

  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  if (uri == null) return false;

  final host = uri.host.toLowerCase();
  const domains = {
    'youtube.com',
    'youtu.be',
    'youtube-nocookie.com',
    'youtube.googleapis.com',
    'youtubei.googleapis.com',
    'googlevideo.com',
  };
  return domains.any((domain) => host == domain || host.endsWith('.$domain'));
}

bool checkAndShowYouTubeRestriction(BuildContext context, String input) {
  if (!isYouTubeUrl(input)) return false;

  showYouTubeRestrictionDialog(context);
  return true;
}

Future<void> showYouTubeRestrictionDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => AlertDialog(
      key: const Key('youtube_restriction_dialog'),
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.gavel_rounded, color: Color(0xFFFF5436)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'YouTube indirme uyarısı',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      content: const Text(
        youtubeRestrictionMessage,
        style: TextStyle(color: Color(0xFFE2E8F0), height: 1.5),
      ),
      actions: [
        TextButton(
          key: const Key('youtube_restriction_dialog_ok_button'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('ANLADIM'),
        ),
      ],
    ),
  );
}

void ensureNotYouTubeUrl(String input) {
  if (isYouTubeUrl(input)) {
    throw const MediaResolverException(youtubeRestrictionMessage);
  }
}
