import 'package:flutter/widgets.dart';

import '../app_localizations.dart';

/// VidSave localization extension methods for clean and concise access across the codebase.
/// Allows:
///   `context.tr('btn_download')`
///   `context.l10n.text('btn_download')`
///   `'btn_download'.tr(context)`
extension LocalizationStringExtension on String {
  /// Translates this key using the ambient [AppLocalizations].
  String tr(BuildContext context) => AppLocalizations.of(context).text(this);
}

extension LocalizationBuildContextExtension on BuildContext {
  /// Quick ambient accessor: `context.l10n.text('key')`
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Direct translate helper: `context.tr('key')`
  String tr(String key) => AppLocalizations.of(this).text(key);
}
