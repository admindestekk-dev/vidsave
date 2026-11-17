import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'auth_service.dart';

Future<void> showGoogleSignInErrorDialog(
  BuildContext context,
  Object error,
) {
  final isTurkish =
      AppLocalizations.of(context).locale.languageCode.toLowerCase() == 'tr';
  final message = error is AuthException
      ? '${error.message}\n\n${isTurkish ? 'Hata kodu' : 'Error code'}: ${error.code}'
      : error.toString();

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        isTurkish ? 'Google ile giriş başarısız' : 'Google sign-in failed',
      ),
      content: SingleChildScrollView(child: SelectableText(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isTurkish ? 'Tamam' : 'OK'),
        ),
      ],
    ),
  );
}
