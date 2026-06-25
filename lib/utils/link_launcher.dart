import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/site_customization.dart';
import '../constants.dart';
import '../pages/equn_thread_detail_page.dart';
import '../pages/webview_page.dart';
import '../providers/preferences_provider.dart';
import '../services/discourse/discourse_service.dart';
import '../widgets/common/external_link_confirm_dialog.dart';
import 'equn_discuz_url_parser.dart';
import 'link_security.dart';
import 'url_helper.dart';

const _browserChannel = MethodChannel('com.github.kamisangk.equndo/browser');

/// 检查 URL 是否属于站点内部链接（主域名或子域名）
bool isInternalUrl(Uri uri) {
  final baseUri = Uri.tryParse(AppConstants.baseUrl);
  if (baseUri == null) return false;

  final baseHost = baseUri.host; // 如 'linux.do'
  final host = uri.host;

  final hostMatches = host == baseHost || host.endsWith('.$baseHost');
  if (!hostMatches) return false;

  return UrlHelper.samePrefix(uri.toString());
}

/// 检查 URL 是否属于站点内部链接（字符串版本，支持相对路径）
bool isInternalUrlString(String url) {
  if (url.startsWith('/')) return true;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return isInternalUrl(uri);
}

bool _isUploadLink(String url) {
  return url.contains('/uploads/') ||
      url.contains('/secure-uploads/') ||
      url.contains('/secure-media-uploads/');
}

/// 打开外部链接
///
/// 根据用户偏好决定使用内置浏览器还是外部浏览器
/// 如果启用了链接安全检查，会根据链接风险等级显示确认对话框
Future<void> launchExternalLink(BuildContext context, String url) async {
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;

  // 链接安全检查
  final config = AppConstants.siteCustomization.linkSecurityConfig;
  if (config != null && config.enableExitConfirmation) {
    final riskLevel = LinkSecurity.checkUrl(url, config);

    switch (riskLevel) {
      case LinkRiskLevel.internal:
      case LinkRiskLevel.trusted:
        // 内部或信任链接，直接打开
        break;
      case LinkRiskLevel.blocked:
        // 阻止链接，显示阻止提示
        await showLinkBlockedDialog(context, url);
        return;
      case LinkRiskLevel.normal:
      case LinkRiskLevel.risky:
      case LinkRiskLevel.dangerous:
        // 需要确认的链接，显示确认对话框
        final confirmed = await showExternalLinkConfirmDialog(
          context,
          url,
          riskLevel,
        );
        if (confirmed != true) return;
        break;
    }
  }

  final prefs = ProviderScope.containerOf(
    // ignore: use_build_context_synchronously
    context,
    listen: false,
  ).read(preferencesProvider);
  final preferInApp = prefs.openExternalLinksInAppBrowser;

  if (preferInApp && (uri.scheme == 'http' || uri.scheme == 'https')) {
    // ignore: use_build_context_synchronously
    WebViewPage.open(context, url);
    return;
  }

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 打开内容中的链接（统一入口）
///
/// 处理所有类型的链接：
/// - equn 话题链接 → 打开原生 Discuz 话题详情
/// - equn 用户链接 → 用内置浏览器打开 Discuz 用户空间
/// - 附件链接 /uploads/ → 外部浏览器打开
/// - 站点内部链接（主域名或子域名）→ 内置浏览器
/// - Email 链接 → 外部邮件客户端
/// - 外部链接 → 根据用户偏好决定
Future<void> launchContentLink(
  BuildContext context,
  String url, {
  void Function(int topicId, String? topicSlug, int? postNumber)? onInternalLinkTap,
  void Function(String url)? onDownloadAttachment,
}) async {
  if (url.isEmpty) return;
  if (url.startsWith('upload://')) {
    url = await DiscourseService().resolveShortUrlForLink(url) ?? url;
    if (!context.mounted) return;
  }

  final fullUrl = UrlHelper.resolveUrl(url);

  // 1. 解析 equn Discuz 话题链接
  final threadInfo = EqunDiscuzUrlParser.parseThread(fullUrl);
  if (threadInfo != null) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EqunThreadDetailPage(tid: threadInfo.tid),
      ),
    );
    return;
  }

  // 2. 解析 equn Discuz 用户空间链接
  final userInfo = EqunDiscuzUrlParser.parseUser(fullUrl);
  if (userInfo != null) {
    WebViewPage.open(context, fullUrl);
    return;
  }

  // 3. 附件链接：优先使用内置下载，回退外部浏览器
  if (_isUploadLink(url) && isInternalUrlString(url)) {
    if (onDownloadAttachment != null) {
      onDownloadAttachment(fullUrl);
    } else {
      final uri = Uri.tryParse(fullUrl);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    return;
  }

  // 4. Email 链接
  if (url.startsWith('mailto:')) {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }

  // 5. 站点内部链接（主域名或子域名、相对路径）→ 内置浏览器
  if (isInternalUrlString(url)) {
    WebViewPage.open(context, fullUrl);
    return;
  }

  // 6. 外部链接 → 根据用户偏好决定
  if (!context.mounted) return;
  await launchExternalLink(context, url);
}

/// 强制在外部浏览器打开链接，绕过 App Links
///
/// 在 Android 上通过原生代码排除自己的应用，直接用外部浏览器打开，
/// 避免被应用的 intent-filter 拦截导致链接又回到应用本身。
Future<bool> launchInExternalBrowser(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;

  if (Platform.isAndroid) {
    try {
      final result = await _browserChannel.invokeMethod<bool>(
        'openInBrowser',
        {'url': url},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[LinkLauncher] Failed to launch browser: $e');
      // 回退到 url_launcher
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    }
  } else {
    // iOS 和其他平台使用 url_launcher
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }
}
