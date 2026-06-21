class EqunThreadLinkInfo {
  final int tid;
  final int? page;
  final int? postNumber;
  final Uri normalizedUri;

  const EqunThreadLinkInfo({
    required this.tid,
    required this.normalizedUri,
    this.page,
    this.postNumber,
  });
}

class EqunUserLinkInfo {
  final int uid;

  const EqunUserLinkInfo({required this.uid});
}

class EqunDiscuzUrlParser {
  EqunDiscuzUrlParser._();

  static final RegExp _threadPathRegex = RegExp(
    r'^/(?:forum/)?thread-(\d+)(?:-(\d+))?(?:-(\d+))?\.html$',
    caseSensitive: false,
  );

  static bool isEqunForumHost(String host) {
    final normalizedHost = host.toLowerCase();
    return normalizedHost == 'equn.com' ||
        normalizedHost == 'www.equn.com' ||
        normalizedHost.endsWith('.equn.com');
  }

  static bool isEqunForumUri(Uri uri) {
    if (!isEqunForumHost(uri.host)) return false;
    return uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first.toLowerCase() == 'forum';
  }

  static EqunThreadLinkInfo? parseThread(String url) {
    final uri = _parseUri(url);
    if (uri == null) return null;
    return parseThreadUri(uri);
  }

  static EqunThreadLinkInfo? parseThreadUri(Uri uri) {
    final normalized = normalizeUri(uri);
    if (!isEqunForumUri(normalized)) return null;

    final staticMatch = _threadPathRegex.firstMatch(normalized.path);
    if (staticMatch != null) {
      final tid = int.tryParse(staticMatch.group(1)!);
      if (tid == null) return null;
      return EqunThreadLinkInfo(
        tid: tid,
        page: int.tryParse(staticMatch.group(2) ?? ''),
        postNumber: int.tryParse(staticMatch.group(3) ?? ''),
        normalizedUri: normalized,
      );
    }

    final segments = normalized.pathSegments;
    if (segments.length >= 2 &&
        segments[0].toLowerCase() == 'forum' &&
        segments[1].toLowerCase() == 'forum.php') {
      final mod = normalized.queryParameters['mod']?.toLowerCase();
      if (mod == 'viewthread') {
        final tid = _parseInt(normalized.queryParameters['tid']);
        if (tid != null) {
          return EqunThreadLinkInfo(tid: tid, normalizedUri: normalized);
        }
      }

      if (mod == 'redirect' &&
          normalized.queryParameters['goto']?.toLowerCase() == 'findpost') {
        final tid = _parseInt(
          normalized.queryParameters['ptid'] ??
              normalized.queryParameters['tid'],
        );
        if (tid != null) {
          return EqunThreadLinkInfo(tid: tid, normalizedUri: normalized);
        }
      }
    }

    return null;
  }

  static EqunUserLinkInfo? parseUser(String url) {
    final uri = _parseUri(url);
    if (uri == null) return null;
    final normalized = normalizeUri(uri);
    if (!isEqunForumUri(normalized)) return null;

    final segments = normalized.pathSegments;
    if (segments.length < 2 ||
        segments[0].toLowerCase() != 'forum' ||
        segments[1].toLowerCase() != 'home.php') {
      return null;
    }

    if (normalized.queryParameters['mod']?.toLowerCase() != 'space') {
      return null;
    }

    final uid = _parseInt(normalized.queryParameters['uid']);
    if (uid == null) return null;
    return EqunUserLinkInfo(uid: uid);
  }

  static Uri normalizeUri(Uri uri) {
    final keepPort = uri.hasPort && !_isDefaultPort(uri.scheme, uri.port);
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: keepPort ? uri.port : null,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
  }

  static Uri? _parseUri(String rawUrl) {
    if (rawUrl.startsWith('//')) {
      return Uri.tryParse('https:$rawUrl');
    }
    if (!rawUrl.contains('://')) {
      return Uri.tryParse('https://$rawUrl');
    }
    return Uri.tryParse(rawUrl);
  }

  static int? _parseInt(String? value) {
    if (value == null) return null;
    return int.tryParse(value);
  }

  static bool _isDefaultPort(String scheme, int port) {
    return (scheme == 'http' && port == 80) ||
        (scheme == 'https' && port == 443);
  }
}
