import 'package:flutter/widgets.dart';
import 'app_localizations.dart';
export 'app_localizations.dart';
import '../services/local_notification_service.dart';

/// 全局本地化文本访问器
///
/// 在有 context 的地方使用 `context.l10n`
/// 在无 context 的地方（如 Service、Toast）使用 `S.current`
class S {
  S._();

  static AppLocalizations get current {
    final context = navigatorKey.currentContext;
    assert(context != null, 'navigatorKey.currentContext is null');
    return Translations.of(context!);
  }
}

extension L10nExtension on BuildContext {
  AppLocalizations get l10n => Translations.of(this);
}
