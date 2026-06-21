import 'dart:io' as io;

import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../constants.dart';
import '../../auth_session.dart';
import '../../log/log_writer.dart';
import 'cookie_jar_service.dart';
import 'cookie_logger.dart';
import 'strategy/platform_cookie_strategy.dart';

/// 边界同步服务：在登录成功、CF 验证成功等关键时机，
/// 从 WebView CookieManager 读取 cookie 写入 CookieJar。
///
/// 只在边界时机调用，不做常态同步。
class BoundarySyncService {
  BoundarySyncService._internal();

  static final BoundarySyncService instance = BoundarySyncService._internal();

  final CookieJarService _jar = CookieJarService();
  final PlatformCookieStrategy _strategy = PlatformCookieStrategy.create();

  /// 从 WebView 读取一个 cookie 值，但不写入 CookieJar。
  ///
  /// 用于 auth 恢复时把 WebView session 当作候选值先验证，避免未验证的
  /// session cookie 覆盖 native canonical cookie。
  Future<String?> readCookieValueFromWebView({
    String? currentUrl,
    InAppWebViewController? controller,
    required String name,
    bool allowLowConfidenceSessionCookies = false,
  }) async {
    final url = currentUrl ?? AppConstants.baseUrl;
    final uri = Uri.parse(url);
    final host = uri.host;

    if (io.Platform.isWindows && controller != null) {
      return _jar.readCookieValueFromController(
        controller,
        name,
        currentUrl: url,
      );
    }

    final webViewCookies = await _strategy.readCookiesFromWebView(
      _jar.webViewCookieManager,
      url,
    );
    final matches = <Cookie>[];
    for (final cookie in webViewCookies) {
      final value = cookie.value?.toString() ?? '';
      if (cookie.name != name || value.isEmpty) continue;
      if (CookieJarService.sessionCookieNames.contains(cookie.name) &&
          _isLowConfidenceWebViewCookie(cookie) &&
          !allowLowConfidenceSessionCookies) {
        continue;
      }
      matches.add(cookie);
    }
    if (matches.isEmpty) return null;

    final selected = CookieJarService.sessionCookieNames.contains(name)
        ? _selectBestSessionCookie(matches, host)
        : matches.first;
    return selected?.value?.toString();
  }

  /// 从 WebView 读 cookie 写入 jar。
  ///
  /// [currentUrl] 当前页面 URL，用于确定读取哪个域名的 cookie。
  /// [cookieNames] 只同步指定的 cookie 名；null 表示同步所有。
  /// [excludeCookieNames] 排除指定 cookie；用于 CF/预登录流程避免写回 session。
  /// [trusted] 标记为权威写入（CF challenge 确认后），让写入升 version 盖过旧值。
  /// [acceptValues] cookie 名 → 只接受的值；用于 challenge 场景按确认的 fresh 值
  ///   过滤，排除 WebView 中可能残留的旧变体。
  Future<void> syncFromWebView({
    String? currentUrl,
    InAppWebViewController? controller,
    Set<String>? cookieNames,
    Set<String>? excludeCookieNames,
    bool allowLowConfidenceSessionCookies = false,
    int? requestGeneration,
    bool trusted = false,
    Map<String, String>? acceptValues,
  }) async {
    final url = currentUrl ?? AppConstants.baseUrl;
    final uri = Uri.parse(url);
    final host = uri.host;

    try {
      if (requestGeneration != null &&
          !AuthSession().isValid(requestGeneration)) {
        debugPrint(
          '[BoundarySync] 跳过过期会话同步: '
          'gen=$requestGeneration current=${AuthSession().generation}',
        );
        return;
      }

      if (io.Platform.isWindows && controller != null) {
        final synced = await _jar.syncCriticalCookiesFromController(
          controller,
          currentUrl: url,
          cookieNames: cookieNames,
          excludeCookieNames: excludeCookieNames,
          trusted: trusted,
          acceptValues: acceptValues,
        );
        if (synced > 0) {
          final syncedDetails = await _jar.getCookieDiagnosticsForRequest(
            uri,
            names: cookieNames,
          );
          CookieLogger.sync(
            direction: 'WebView(CDP) → CookieJar',
            count: synced,
            names: cookieNames?.toList() ?? const [],
            source: 'boundary_sync',
            url: url,
            cookieDetails: syncedDetails,
          );
          return;
        }
      }

      // 通过 strategy 读取（Linux 用 getAllCookies 兜底）
      final webViewCookies = await _strategy.readCookiesFromWebView(
        _jar.webViewCookieManager,
        url,
      );
      final cookiesToPersist = <Cookie>[];
      final sessionCookieGroups = <String, List<Cookie>>{};

      for (final wc in webViewCookies) {
        final value = wc.value?.toString() ?? '';
        if (value.isEmpty) continue;
        if (cookieNames != null && !cookieNames.contains(wc.name)) continue;
        if (excludeCookieNames != null &&
            excludeCookieNames.contains(wc.name)) {
          continue;
        }
        // challenge 场景：只接受确认的 fresh 值，排除 WebView 残留的旧变体。
        final onlyValue = acceptValues?[wc.name];
        if (onlyValue != null && value != onlyValue) continue;

        final isSessionCookie =
            CookieJarService.sessionCookieNames.contains(wc.name);
        if (isSessionCookie) {
          sessionCookieGroups.putIfAbsent(wc.name, () => <Cookie>[]).add(wc);
        } else {
          cookiesToPersist.add(wc);
        }
      }

      for (final entry in sessionCookieGroups.entries) {
        final selected = _selectBestSessionCookie(entry.value, host);
        if (selected == null) continue;

        if (entry.value.length > 1) {
          _logDuplicateSessionCookies(
            url: url,
            host: host,
            name: entry.key,
            cookies: entry.value,
            selected: selected,
          );
        }
        cookiesToPersist.add(selected);
      }

      final toSave = <io.Cookie>[];
      final forcedHostOnlySessionCookies = <Map<String, dynamic>>[];

      for (final wc in cookiesToPersist) {
        final value = wc.value?.toString() ?? '';
        final isSessionCookie =
            CookieJarService.sessionCookieNames.contains(wc.name);
        final lowConfidenceSnapshot = _isLowConfidenceWebViewCookie(wc);
        if (isSessionCookie &&
            lowConfidenceSnapshot &&
            !allowLowConfidenceSessionCookies) {
          debugPrint(
            '[BoundarySync] ${wc.name}: 跳过低置信度会话 Cookie 快照',
          );
          continue;
        }

        // domain 处理：优先用平台返回值，旧 Android 兜底
        String? domain;
        final rawDomain = wc.domain?.trim();
        final shouldForceSessionHostOnly =
            io.Platform.isAndroid && isSessionCookie;
        if (shouldForceSessionHostOnly) {
          domain = null;
          if (rawDomain != null && rawDomain.isNotEmpty) {
            forcedHostOnlySessionCookies.add({
              'name': wc.name,
              'webViewDomain': wc.domain,
              'path': wc.path,
              'valueLength': value.length,
            });
          }
        } else if (rawDomain != null && rawDomain.startsWith('.')) {
          // 浏览器约定: 前导点表示真 domain cookie(原始 Set-Cookie 带 Domain=)
          domain = rawDomain;
        } else if (rawDomain != null && rawDomain.isNotEmpty) {
          // 无前导点表示 host-only(WebView 回读时对 host-only cookie
          // 会回填裸 host 到 domain 字段, 这里必须当 host-only 处理,
          // 否则 _t 等会话 cookie 会被写成 domain cookie 挂到子域名上)
          domain = null;
        } else if (isSessionCookie) {
          // 会话 Cookie 缺失 domain 时，保持 host-only 语义，不再放大到子域名。
          domain = null;
        } else {
          // 旧 Android（GET_COOKIE_INFO 不支持）：domain 为 null
          // 优先继承 jar 中已有的 domain
          final existing = await _jar.getCanonicalCookie(wc.name);
          if (existing != null &&
              existing.domain != null &&
              existing.domain!.trim().isNotEmpty) {
            domain = existing.domain;
            debugPrint(
              '[BoundarySync] ${wc.name}: domain=null, 继承 jar 已有 domain=${existing.domain}',
            );
          } else {
            // jar 也没有 → 兜底为 .{host}（domain cookie）
            // 宁可多发到子域名，不能因为 host-only 导致子域名拿不到关键 cookie
            domain = '.$host';
            debugPrint('[BoundarySync] ${wc.name}: domain=null, 兜底为 .$host');
          }
        }

        io.Cookie cookie;
        try {
          cookie = io.Cookie(wc.name, value);
        } catch (_) {
          // value 含 RFC 不允许的字符（如 { } " 等），编码后存储
          cookie = io.Cookie(wc.name, CookieValueCodec.encode(value));
        }
        cookie
          ..path = wc.path ?? '/'
          ..secure = wc.isSecure ?? (isSessionCookie ? uri.scheme == 'https' : false)
          ..httpOnly =
              wc.isHttpOnly ?? (isSessionCookie && allowLowConfidenceSessionCookies);
        if (domain != null && domain.trim().isNotEmpty) {
          cookie.domain = domain;
        }

        if (wc.expiresDate != null) {
          cookie.expires = DateTime.fromMillisecondsSinceEpoch(wc.expiresDate!);
        }

        if (isSessionCookie &&
            await _isSameSessionCookieAlreadyInJar(
              name: wc.name,
              value: value,
              domain: domain,
              path: cookie.path ?? '/',
              requestHost: host,
            )) {
          continue;
        }

        toSave.add(cookie);
      }

      if (toSave.isEmpty) {
        debugPrint('[BoundarySync] 未从 WebView 读取到有效 cookie: url=$url');
        return;
      }

      if (requestGeneration != null &&
          !AuthSession().isValid(requestGeneration)) {
        debugPrint(
          '[BoundarySync] 跳过过期会话写入: '
          'gen=$requestGeneration current=${AuthSession().generation}',
        );
        return;
      }

      if (!_jar.isInitialized) await _jar.initialize();
      final jar = _jar.cookieJar;
      if (trusted && jar is EnhancedPersistCookieJar) {
        await jar.saveFromResponseTrusted(uri, toSave, trusted: true);
      } else {
        await jar.saveFromResponse(uri, toSave);
      }
      final syncedDetails = await _jar.getCookieDiagnosticsForRequest(
        uri,
        names: toSave.map((cookie) => cookie.name),
      );

      CookieLogger.sync(
        direction: 'WebView → CookieJar',
        count: toSave.length,
        names: toSave.map((c) => c.name).toList(),
        source: 'boundary_sync',
        url: url,
        cookieDetails: syncedDetails,
        extraFields: {
          if (forcedHostOnlySessionCookies.isNotEmpty)
            'forcedHostOnlySessionCookies': forcedHostOnlySessionCookies,
        },
      );
    } catch (e) {
      CookieLogger.error(operation: 'boundary_sync', error: e.toString());
    }
  }

  bool _isLowConfidenceWebViewCookie(Cookie cookie) {
    final hasDomain = cookie.domain != null && cookie.domain!.trim().isNotEmpty;
    final hasPath = cookie.path != null && cookie.path!.trim().isNotEmpty;
    final hasSecureFlag = cookie.isSecure != null;
    final hasHttpOnlyFlag = cookie.isHttpOnly != null;
    final hasExpiry = cookie.expiresDate != null;
    final hasSameSite = cookie.sameSite != null;
    return !(hasDomain ||
        hasPath ||
        hasSecureFlag ||
        hasHttpOnlyFlag ||
        hasExpiry ||
        hasSameSite);
  }

  Cookie? _selectBestSessionCookie(List<Cookie> cookies, String requestHost) {
    if (cookies.isEmpty) return null;
    final candidates = [...cookies]
      ..sort((a, b) {
        final scoreDiff =
            _scoreSessionCookie(b, requestHost) - _scoreSessionCookie(a, requestHost);
        if (scoreDiff != 0) return scoreDiff;

        final pathDiff = (b.path?.length ?? 1).compareTo(a.path?.length ?? 1);
        if (pathDiff != 0) return pathDiff;

        return (b.value?.length ?? 0).compareTo(a.value?.length ?? 0);
      });
    return candidates.first;
  }

  int _scoreSessionCookie(Cookie cookie, String requestHost) {
    var score = 0;
    final value = cookie.value?.toString() ?? '';
    if (value.isNotEmpty) score += 100000;

    final expires = CookieJarService.parseWebViewCookieExpires(cookie.expiresDate);
    if (expires == null || expires.isAfter(DateTime.now())) {
      score += 50000;
    }

    final normalizedDomain =
        CookieJarService.normalizeWebViewCookieDomain(cookie.domain);
    if (normalizedDomain == null || normalizedDomain.isEmpty) {
      score += 40000;
    } else if (normalizedDomain == requestHost) {
      score += 30000 + normalizedDomain.length;
    } else if (requestHost.endsWith('.$normalizedDomain')) {
      score += 20000 + normalizedDomain.length;
    } else {
      score += normalizedDomain.length;
    }

    if (cookie.isHttpOnly == true) score += 500;
    if (cookie.isSecure == true) score += 250;
    score += cookie.path?.length ?? 1;
    score += value.length;
    return score;
  }

  Future<bool> _isSameSessionCookieAlreadyInJar({
    required String name,
    required String value,
    required String? domain,
    required String path,
    required String requestHost,
  }) async {
    final existing = await _jar.getCanonicalCookie(name);
    if (existing == null || existing.value != value) return false;
    if (existing.path != path) return false;

    final nextHostOnly = domain == null || domain.trim().isEmpty;
    if (existing.hostOnly != nextHostOnly) return false;

    final nextDomain = nextHostOnly
        ? requestHost.toLowerCase()
        : CookieJarService.normalizeWebViewCookieDomain(domain);
    return existing.normalizedDomain == nextDomain;
  }

  void _logDuplicateSessionCookies({
    required String url,
    required String host,
    required String name,
    required List<Cookie> cookies,
    required Cookie selected,
  }) {
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'warning',
      'type': 'cookie_conflict',
      'event': 'duplicate_session_cookie_from_webview',
      'message': 'WebView 中检测到重复会话 Cookie，已在边界同步时选优',
      'url': url,
      'host': host,
      'name': name,
      'duplicateCount': cookies.length,
      'selected': {
        'domain': selected.domain,
        'path': selected.path,
        'hostOnly': selected.domain == null || selected.domain!.trim().isEmpty,
        'valueLength': selected.value?.length ?? 0,
        'httpOnly': selected.isHttpOnly,
        'secure': selected.isSecure,
      },
      'cookies': cookies
          .map(
            (cookie) => {
              'domain': cookie.domain,
              'path': cookie.path,
              'hostOnly': cookie.domain == null || cookie.domain!.trim().isEmpty,
              'valueLength': cookie.value?.length ?? 0,
              'httpOnly': cookie.isHttpOnly,
              'secure': cookie.isSecure,
              'expiresDate': cookie.expiresDate,
            },
          )
          .toList(growable: false),
    });
  }
}
