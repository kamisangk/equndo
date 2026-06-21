import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../pages/webview_page.dart';

class EqunSearchLauncher {
  static const url = 'https://equn.com/forum/search.php?mod=forum';

  static Future<T?> open<T extends Object?>(BuildContext context) {
    return WebViewPage.open<T>(
      context,
      url,
      title: context.l10n.common_search,
    );
  }
}
