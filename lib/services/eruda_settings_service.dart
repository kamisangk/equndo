import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eruda 设备内 DevTools 开关。
///
/// Eruda 打包在 compat polyfill bundle (`assets/polyfill/compat-polyfill.js`)
/// 里, 注入主站 WebView 后默认会初始化 (页面右下角 ⚙ 悬浮按钮)。本服务把它
/// 做成运行时开关、**默认关闭**:
///
/// 关闭时 [WebViewSettings.compatPolyfillScripts] 会在 polyfill 之前抢先注入
/// `window.__fluxdoErudaInited = true`, 利用 bundle 内 eruda-init 的
/// `if (window.__fluxdoErudaInited) return` guard 让其跳过 init —— 纯 dart
/// 控制, 不需要改 / 重打包 bundle。
///
/// 主要用途: 在页面内直接查看网络 / 控制台 / 元素 / 资源等, 无需外部调试器。
///
/// 实现模式对齐 [WebViewAdapterSettingsService]。
class ErudaSettingsService {
  ErudaSettingsService._internal();

  static final ErudaSettingsService instance = ErudaSettingsService._internal();

  static const _enabledKey = 'eruda_enabled';

  /// 默认关闭。
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
}
