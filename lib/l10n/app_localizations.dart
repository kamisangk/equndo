import 'package:intl/intl.dart' as intl;

import 'slang/strings.g.dart';

export 'slang/strings.g.dart'
    show
        AppLocale,
        AppLocaleUtils,
        LocaleSettings,
        TranslationProvider,
        Translations,
        t;

part 'generated/app_localizations_compat.g.dart';

typedef AppLocalizations = Translations;

extension AppLocalizationsMeta on Translations {
  String get localeName =>
      intl.Intl.canonicalizedLocale($meta.locale.flutterLocale.toString());
}
