import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants.dart';

/// WebView 适配器设置服务
///
/// 开启后，主站 API 请求通过 WebView 内核发送（真正的 Chrome TLS 指纹），
/// 可改善因 TLS 指纹被 Cloudflare 识别为非浏览器客户端导致的登录失效问题。
///
/// 仅对主域名的 API 请求生效，排除：
/// - CDN 图片请求（cdn.linux.do 等子域名）
/// - MessageBus 长轮询（/message-bus/ 路径）
class WebViewAdapterSettingsService {
  WebViewAdapterSettingsService._internal();

  static final WebViewAdapterSettingsService instance =
      WebViewAdapterSettingsService._internal();

  static const _enabledKey = 'webview_adapter_enabled';

  final ValueNotifier<bool> notifier = ValueNotifier(false);

  SharedPreferences? _prefs;

  bool get enabled => notifier.value;

  Future<void> initialize(SharedPreferences prefs) async {
    if (_prefs != null) return;
    _prefs = prefs;
    notifier.value = prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    notifier.value = value;
    await prefs.setBool(_enabledKey, value);
  }

  /// 判断请求是否应走 WebView 适配器
  bool shouldUseWebView(Uri uri) {
    if (!enabled) return false;
    final baseHost = Uri.parse(AppConstants.baseUrl).host;
    // 仅主域名（排除 CDN、ping 等子域名）
    if (uri.host != baseHost) return false;
    // 排除 MessageBus 长轮询
    if (uri.path.startsWith('/message-bus/')) return false;
    return true;
  }
}
