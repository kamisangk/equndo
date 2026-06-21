import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'default_cookie_strategy.dart';

/// Android cookie 策略
///
/// - deleteAllCookies 加 timeout 保护（避免 ANR）
/// - 补充逐 host 精确删除残留 domain cookie
class AndroidCookieStrategy extends DefaultCookieStrategy {
  @override
  Future<void> clearWebViewCookies(
    CookieManager cookieManager,
    Set<String> knownHosts,
  ) async {
    // deleteAllCookies 可能 ANR，加 timeout
    try {
      await cookieManager
          .deleteAllCookies()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[CookieStrategy][Android] deleteAllCookies failed/timeout: $e');
    }

    // 补充逐 host 精确删除残留 cookie（deleteAllCookies 在 Android 上可能不彻底）
    for (final host in knownHosts) {
      try {
        final url = WebUri('https://$host');
        final remaining = await cookieManager.getCookies(url: url);
        for (final wc in remaining) {
          await cookieManager.deleteCookie(
            url: url,
            name: wc.name,
            domain: wc.domain,
            path: wc.path ?? '/',
          );
        }
      } catch (e) {
        debugPrint('[CookieStrategy][Android] per-host delete failed for $host: $e');
      }
    }
  }
}
