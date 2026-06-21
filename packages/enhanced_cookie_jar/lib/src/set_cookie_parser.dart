import 'dart:io' as io;

import 'canonical_cookie.dart';

class SetCookieParser {
  static CanonicalCookie parse(String header, {required Uri uri, CookieSource source = CookieSource.setCookieHeader}) {
    final parts = header.split(';');
    if (parts.isEmpty) {
      throw FormatException('Invalid Set-Cookie header: ');
    }

    final nameValue = parts.first;
    final separator = nameValue.indexOf('=');
    if (separator <= 0) {
      throw FormatException('Invalid Set-Cookie header: ');
    }

    final name = nameValue.substring(0, separator).trim();
    final value = nameValue.substring(separator + 1).trim();

    String? domain;
    var path = _defaultPath(uri);
    DateTime? expiresAt;
    int? maxAge;
    var secure = false;
    var httpOnly = false;
    var sameSite = CookieSameSite.unspecified;
    var sameParty = false;
    String? priority;
    String? partitionKey;
    var partitioned = false;
    String? sourceScheme;
    int? sourcePort;

    for (final rawAttribute in parts.skip(1)) {
      final attribute = rawAttribute.trim();
      if (attribute.isEmpty) continue;
      final index = attribute.indexOf('=');
      final key = (index == -1 ? attribute : attribute.substring(0, index)).trim().toLowerCase();
      final attrValue = index == -1 ? '' : attribute.substring(index + 1).trim();

      switch (key) {
        case 'domain':
          domain = attrValue.isEmpty ? null : attrValue;
          break;
        case 'path':
          if (attrValue.isNotEmpty) path = attrValue;
          break;
        case 'expires':
          try {
            expiresAt = io.HttpDate.parse(attrValue).toUtc();
          } catch (_) {}
          break;
        case 'max-age':
          maxAge = int.tryParse(attrValue);
          break;
        case 'secure':
          secure = true;
          break;
        case 'httponly':
          httpOnly = true;
          break;
        case 'samesite':
          sameSite = _parseSameSite(attrValue);
          break;
        case 'priority':
          priority = attrValue.isEmpty ? null : attrValue;
          break;
        case 'sameparty':
          sameParty = true;
          break;
        case 'partitioned':
          partitioned = true;
          break;
        case 'partitionkey':
          partitionKey = attrValue.isEmpty ? null : attrValue;
          break;
        case 'sourcescheme':
          sourceScheme = attrValue.isEmpty ? null : attrValue;
          break;
        case 'sourceport':
          sourcePort = int.tryParse(attrValue);
          break;
      }
    }

    final normalizedDomain =
        domain == null || domain.isEmpty ? uri.host : domain;

    return CanonicalCookie(
      name: name,
      value: value,
      domain: normalizedDomain,
      path: path,
      expiresAt: expiresAt,
      maxAge: maxAge,
      secure: secure,
      httpOnly: httpOnly,
      sameSite: sameSite,
      hostOnly: domain == null || domain.isEmpty,
      persistent: expiresAt != null || maxAge != null,
      sameParty: sameParty,
      priority: priority,
      partitionKey: partitionKey,
      partitioned: partitioned,
      sourceScheme: sourceScheme,
      sourcePort: sourcePort,
      originUrl: uri.toString(),
      source: source,
      rawSetCookie: header,
    );
  }

  static CanonicalCookie fromIoCookie(io.Cookie cookie, {required Uri uri, CookieSource source = CookieSource.dioResponse}) {
    final normalizedDomain =
        cookie.domain == null || cookie.domain!.trim().isEmpty
            ? uri.host
            : cookie.domain;

    return CanonicalCookie(
      name: cookie.name,
      value: cookie.value,
      domain: normalizedDomain,
      path: cookie.path ?? _defaultPath(uri),
      expiresAt: cookie.expires?.toUtc(),
      maxAge: cookie.maxAge,
      secure: cookie.secure,
      httpOnly: cookie.httpOnly,
      hostOnly: cookie.domain == null || cookie.domain!.trim().isEmpty,
      persistent: cookie.expires != null || cookie.maxAge != null,
      originUrl: uri.toString(),
      source: source,
    );
  }

  static String _defaultPath(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (path == '/' || !path.contains('/')) return '/';
    final index = path.lastIndexOf('/');
    if (index <= 0) return '/';
    return path.substring(0, index);
  }

  static CookieSameSite _parseSameSite(String value) {
    switch (value.toLowerCase()) {
      case 'lax':
        return CookieSameSite.lax;
      case 'strict':
        return CookieSameSite.strict;
      case 'none':
        return CookieSameSite.none;
      default:
        return CookieSameSite.unspecified;
    }
  }
}
