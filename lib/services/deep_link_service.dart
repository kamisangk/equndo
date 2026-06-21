import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import '../pages/equn_thread_detail_page.dart';
import '../pages/webview_page.dart';
import '../utils/equn_discuz_url_parser.dart';

/// Deep Link 服务
/// 处理从外部链接打开应用的场景
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService _instance = DeepLinkService._();
  static DeepLinkService get instance => _instance;

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  BuildContext? _navigatorContext;
  bool _initialized = false;

  /// 防重复：记录最近处理的链接和时间
  Uri? _lastHandledUri;
  DateTime? _lastHandledTime;

  /// 邮箱登录成功回调（用于 Onboarding 页面完成引导）
  VoidCallback? onEmailLoginSuccess;

  /// 初始化服务
  /// 在主页面初始化后调用
  void initialize(BuildContext context) {
    _navigatorContext = context;

    if (_initialized) return;
    _initialized = true;

    // 处理应用冷启动时的链接
    _handleInitialLink();

    // 监听后续链接
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleLink);
  }

  /// 更新导航 context
  void updateContext(BuildContext context) {
    _navigatorContext = context;
  }

  /// 处理初始链接（冷启动）
  Future<void> _handleInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        // 延迟处理，确保导航 context 已就绪
        await Future.delayed(const Duration(milliseconds: 500));
        _handleLink(uri);
      }
    } catch (e) {
      debugPrint('DeepLinkService: 获取初始链接失败: $e');
    }
  }

  /// 处理外部或应用内链接，入口内会先校验可处理的 scheme 和 host
  void handleUri(Uri uri) {
    _handleLink(uri);
  }

  @visibleForTesting
  bool canHandleUri(Uri uri) => _canHandleUri(uri);

  /// 处理链接
  void _handleLink(Uri uri) {
    if (_navigatorContext == null) {
      debugPrint('DeepLinkService: 导航 context 未就绪');
      return;
    }

    final context = _navigatorContext!;
    final url = uri.toString();

    if (!_canHandleUri(uri)) {
      debugPrint('DeepLinkService: 未知链接类型 $url');
      return;
    }

    // 防重复：1秒内相同链接不重复处理
    final now = DateTime.now();
    if (_lastHandledUri == uri &&
        _lastHandledTime != null &&
        now.difference(_lastHandledTime!).inSeconds < 1) {
      debugPrint('DeepLinkService: 忽略重复链接 $uri');
      return;
    }
    _lastHandledUri = uri;
    _lastHandledTime = now;

    debugPrint('DeepLinkService: 收到链接 $url');

    final threadInfo = EqunDiscuzUrlParser.parseThreadUri(uri);
    if (threadInfo != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EqunThreadDetailPage(tid: threadInfo.tid),
        ),
      );
      return;
    }

    if (EqunDiscuzUrlParser.isEqunForumUri(uri)) {
      WebViewPage.open(context, url);
      return;
    }

    debugPrint('DeepLinkService: 未知链接类型 $url');
  }

  /// 释放资源
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _navigatorContext = null;
    _initialized = false;
    _lastHandledUri = null;
    _lastHandledTime = null;
  }

  static bool _canHandleUri(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    return EqunDiscuzUrlParser.isEqunForumUri(uri);
  }
}
