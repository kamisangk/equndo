import 'canonical_cookie.dart';

class CdpCookieParser {
  static CanonicalCookie? parse(
    Map<String, dynamic> map, {
    String? originUrl,
    CookieSource source = CookieSource.webViewCdp,
  }) {
    final name = map['name']?.toString();
    final value = map['value']?.toString();
    if (name == null || name.isEmpty || value == null) return null;

    DateTime? expiresAt;
    final expiresRaw = map['expires'];
    if (expiresRaw is num && expiresRaw > 0 && expiresRaw < 1e12) {
      // CDP expires 是秒级 Unix 时间戳，上限保护避免极大值溢出
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        (expiresRaw * 1000).round(),
        isUtc: true,
      );
    }

    final rawDomain = map['domain']?.toString();
    final resolvedOriginUrl = originUrl ?? map['url']?.toString();
    final originHost = Uri.tryParse(resolvedOriginUrl ?? '')?.host;
    final hostOnly = map['hostOnly'] == true
        ? true
        : !(rawDomain?.startsWith('.') ?? false);
    final domain =
        (rawDomain == null || rawDomain.isEmpty) && hostOnly ? originHost : rawDomain;
    final sameSiteRaw = map['sameSite']?.toString();
    final partitionKey = _parsePartitionKey(map['partitionKey']);

    return CanonicalCookie(
      name: name,
      value: value,
      domain: domain,
      path: map['path']?.toString() ?? '/',
      expiresAt: expiresAt,
      secure: map['secure'] == true,
      httpOnly: map['httpOnly'] == true,
      sameSite: _parseSameSite(sameSiteRaw),
      hostOnly: hostOnly,
      persistent: map['session'] == true ? false : expiresAt != null,
      creationTime: _parseSeconds(map['creation']) ?? DateTime.now().toUtc(),
      lastAccessTime: _parseSeconds(map['lastAccess']) ?? DateTime.now().toUtc(),
      priority: map['priority']?.toString(),
      sameParty: map['sameParty'] == true,
      sourceScheme: map['sourceScheme']?.toString(),
      sourcePort: _parseInt(map['sourcePort']),
      partitionKey: partitionKey,
      partitioned: partitionKey != null || map['partitioned'] == true,
      originUrl: resolvedOriginUrl,
      source: source,
    );
  }

  static CookieSameSite _parseSameSite(String? value) {
    switch (value?.toLowerCase()) {
      case 'lax':
        return CookieSameSite.lax;
      case 'strict':
        return CookieSameSite.strict;
      case 'none':
      case 'no_restriction':
        return CookieSameSite.none;
      default:
        return CookieSameSite.unspecified;
    }
  }

  static String? _parsePartitionKey(Object? value) {
    if (value == null) return null;
    if (value is String) return value.isEmpty ? null : value;
    if (value is Map) {
      final topLevelSite = value['topLevelSite']?.toString();
      final hasCrossSiteAncestor = value['hasCrossSiteAncestor'];
      if (topLevelSite == null || topLevelSite.isEmpty) return null;
      return hasCrossSiteAncestor == null
          ? topLevelSite
          : '$topLevelSite|crossSite=$hasCrossSiteAncestor';
    }
    return value.toString();
  }

  /// CDP creation/lastAccess 是秒级 Unix 时间戳（与 expires 相同）
  static DateTime? _parseSeconds(Object? value) {
    if (value is num && value > 0 && value < 1e12) {
      return DateTime.fromMillisecondsSinceEpoch(
        (value * 1000).round(),
        isUtc: true,
      );
    }
    return null;
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
