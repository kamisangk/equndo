import 'dart:convert';
import 'dart:io' as io;

const _encodedCookiePrefix = '~enc~';

enum CookieSameSite { unspecified, lax, strict, none }

enum CookieSource { unknown, dioResponse, setCookieHeader, webViewCdp, webViewManager, manualRestore }

class CanonicalCookie {
  CanonicalCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path = '/',
    this.expiresAt,
    this.maxAge,
    this.secure = false,
    this.httpOnly = false,
    this.sameSite = CookieSameSite.unspecified,
    this.hostOnly = true,
    this.persistent = false,
    DateTime? creationTime,
    DateTime? lastAccessTime,
    this.priority,
    this.sameParty = false,
    this.sourceScheme,
    this.sourcePort,
    this.partitionKey,
    this.partitioned = false,
    this.originUrl,
    this.source = CookieSource.unknown,
    this.version = 1,
    this.lastSyncedToWebViewAt,
    this.lastSyncedFromWebViewAt,
    this.rawSetCookie,
  }) : creationTime = creationTime ?? DateTime.now().toUtc(),
       lastAccessTime = lastAccessTime ?? DateTime.now().toUtc();

  final String name;
  final String value;
  final String? domain;
  final String path;
  final DateTime? expiresAt;
  final int? maxAge;
  final bool secure;
  final bool httpOnly;
  final CookieSameSite sameSite;
  final bool hostOnly;
  final bool persistent;
  final DateTime creationTime;
  final DateTime lastAccessTime;
  final String? priority;
  final bool sameParty;
  final String? sourceScheme;
  final int? sourcePort;
  final String? partitionKey;
  final bool partitioned;
  final String? originUrl;
  final CookieSource source;
  final int version;
  final DateTime? lastSyncedToWebViewAt;
  final DateTime? lastSyncedFromWebViewAt;
  final String? rawSetCookie;

  String? get normalizedDomain {
    final trimmed = domain?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      if (!hostOnly) return null;
      final originHost = Uri.tryParse(originUrl ?? '')?.host.trim();
      if (originHost == null || originHost.isEmpty) return null;
      return originHost.toLowerCase();
    }
    return trimmed.startsWith('.') ? trimmed.substring(1).toLowerCase() : trimmed.toLowerCase();
  }

  bool get isExpired {
    final now = DateTime.now().toUtc();
    if (maxAge != null) {
      final expiry = creationTime.add(Duration(seconds: maxAge!));
      return !expiry.isAfter(now);
    }
    if (expiresAt != null) return !expiresAt!.toUtc().isAfter(now);
    return false;
  }

  /// Cookie 唯一标识为 (name, normalizedDomain, path, partitionKey)。
  /// 故意不含 hostOnly：同域名同名 cookie 只保留一份，新的替换旧的。
  /// 虽然 RFC 6265bis 将 host-only-flag 纳入 identity，但各平台 WebView API
  /// 无法可靠还原 hostOnly，保留它会导致同名 cookie 以不同 hostOnly 共存（多副本 bug）。
  String get storageKey => jsonEncode([
    name,
    normalizedDomain,
    path,
    partitionKey,
  ]);

  /// 同 storageKey 覆盖决策：本 cookie 是否比 [other] 更应保留（更新鲜）。
  ///
  /// 判定顺序：version 更高 > expiresAt 更晚 > creationTime 更晚。
  /// 用于防止 WebView 泛读到的旧值覆盖 jar 中由可信来源（dio Set-Cookie /
  /// CF challenge）写入的权威新值。
  bool isFresherThan(CanonicalCookie other) {
    if (version != other.version) return version > other.version;
    final a = expiresAt;
    final b = other.expiresAt;
    if (a != null && b != null) {
      if (a != b) return a.isAfter(b);
    } else if (a != null || b != null) {
      // 有过期时间的视为更完整/更新，优先保留
      return a != null;
    }
    return creationTime.isAfter(other.creationTime);
  }

  /// 从字段重建 Set-Cookie 头字符串
  /// 如果有 rawSetCookie 原始头则直接返回，否则从字段拼接
  String toSetCookieHeader() {
    if (rawSetCookie != null && rawSetCookie!.isNotEmpty) {
      return rawSetCookie!;
    }
    final buf = StringBuffer('$name=$value');
    if (!hostOnly && domain != null && domain!.isNotEmpty) {
      buf.write('; Domain=$domain');
    }
    if (path.isNotEmpty && path != '/') {
      buf.write('; Path=$path');
    } else {
      buf.write('; Path=/');
    }
    if (expiresAt != null) {
      buf.write('; Expires=${io.HttpDate.format(expiresAt!)}');
    }
    if (maxAge != null) {
      buf.write('; Max-Age=$maxAge');
    }
    if (secure) buf.write('; Secure');
    if (httpOnly) buf.write('; HttpOnly');
    switch (sameSite) {
      case CookieSameSite.lax:
        buf.write('; SameSite=Lax');
      case CookieSameSite.strict:
        buf.write('; SameSite=Strict');
      case CookieSameSite.none:
        buf.write('; SameSite=None');
      case CookieSameSite.unspecified:
        break;
    }
    if (partitioned) buf.write('; Partitioned');
    return buf.toString();
  }

  io.Cookie toIoCookie() {
    late final io.Cookie cookie;
    try {
      cookie = io.Cookie(name, value);
    } catch (_) {
      cookie = io.Cookie(name, '$_encodedCookiePrefix${Uri.encodeComponent(value)}');
    }
    cookie
      ..path = path
      ..secure = secure
      ..httpOnly = httpOnly;
    if (!hostOnly && domain != null && domain!.trim().isNotEmpty) {
      cookie.domain = domain!.trim();
    }
    if (expiresAt != null) cookie.expires = expiresAt!.toUtc();
    if (maxAge != null) cookie.maxAge = maxAge;
    return cookie;
  }

  CanonicalCookie copyWith({
    String? value,
    String? domain,
    String? path,
    DateTime? expiresAt,
    int? maxAge,
    bool? secure,
    bool? httpOnly,
    CookieSameSite? sameSite,
    bool? hostOnly,
    bool? persistent,
    DateTime? creationTime,
    DateTime? lastAccessTime,
    String? priority,
    bool? sameParty,
    String? sourceScheme,
    int? sourcePort,
    String? partitionKey,
    bool? partitioned,
    String? originUrl,
    CookieSource? source,
    int? version,
    DateTime? lastSyncedToWebViewAt,
    DateTime? lastSyncedFromWebViewAt,
    String? rawSetCookie,
  }) {
    return CanonicalCookie(
      name: name,
      value: value ?? this.value,
      domain: domain ?? this.domain,
      path: path ?? this.path,
      expiresAt: expiresAt ?? this.expiresAt,
      maxAge: maxAge ?? this.maxAge,
      secure: secure ?? this.secure,
      httpOnly: httpOnly ?? this.httpOnly,
      sameSite: sameSite ?? this.sameSite,
      hostOnly: hostOnly ?? this.hostOnly,
      persistent: persistent ?? this.persistent,
      creationTime: creationTime ?? this.creationTime,
      lastAccessTime: lastAccessTime ?? this.lastAccessTime,
      priority: priority ?? this.priority,
      sameParty: sameParty ?? this.sameParty,
      sourceScheme: sourceScheme ?? this.sourceScheme,
      sourcePort: sourcePort ?? this.sourcePort,
      partitionKey: partitionKey ?? this.partitionKey,
      partitioned: partitioned ?? this.partitioned,
      originUrl: originUrl ?? this.originUrl,
      source: source ?? this.source,
      version: version ?? this.version,
      lastSyncedToWebViewAt: lastSyncedToWebViewAt ?? this.lastSyncedToWebViewAt,
      lastSyncedFromWebViewAt: lastSyncedFromWebViewAt ?? this.lastSyncedFromWebViewAt,
      rawSetCookie: rawSetCookie ?? this.rawSetCookie,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'maxAge': maxAge,
    'secure': secure,
    'httpOnly': httpOnly,
    'sameSite': sameSite.name,
    'hostOnly': hostOnly,
    'persistent': persistent,
    'creationTime': creationTime.toUtc().toIso8601String(),
    'lastAccessTime': lastAccessTime.toUtc().toIso8601String(),
    'priority': priority,
    'sameParty': sameParty,
    'sourceScheme': sourceScheme,
    'sourcePort': sourcePort,
    'partitionKey': partitionKey,
    'partitioned': partitioned,
    'originUrl': originUrl,
    'source': source.name,
    'version': version,
    'lastSyncedToWebViewAt': lastSyncedToWebViewAt?.toUtc().toIso8601String(),
    'lastSyncedFromWebViewAt': lastSyncedFromWebViewAt?.toUtc().toIso8601String(),
    'rawSetCookie': rawSetCookie,
  };

  factory CanonicalCookie.fromJson(Map<String, dynamic> json) {
    return CanonicalCookie(
      name: json['name'] as String,
      value: json['value'] as String? ?? '',
      domain: json['domain'] as String?,
      path: json['path'] as String? ?? '/',
      expiresAt: _parseDateTime(json['expiresAt']),
      maxAge: json['maxAge'] as int?,
      secure: json['secure'] as bool? ?? false,
      httpOnly: json['httpOnly'] as bool? ?? false,
      sameSite: _parseSameSite(json['sameSite'] as String?),
      hostOnly: json['hostOnly'] as bool? ?? true,
      persistent: json['persistent'] as bool? ?? false,
      creationTime: _parseDateTime(json['creationTime']) ?? DateTime.now().toUtc(),
      lastAccessTime: _parseDateTime(json['lastAccessTime']) ?? DateTime.now().toUtc(),
      priority: json['priority'] as String?,
      sameParty: json['sameParty'] as bool? ?? false,
      sourceScheme: json['sourceScheme'] as String?,
      sourcePort: json['sourcePort'] as int?,
      partitionKey: json['partitionKey'] as String?,
      partitioned: json['partitioned'] as bool? ?? false,
      originUrl: json['originUrl'] as String?,
      source: _parseSource(json['source'] as String?),
      version: json['version'] as int? ?? 1,
      lastSyncedToWebViewAt: _parseDateTime(json['lastSyncedToWebViewAt']),
      lastSyncedFromWebViewAt: _parseDateTime(json['lastSyncedFromWebViewAt']),
      rawSetCookie: json['rawSetCookie'] as String?,
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static CookieSameSite _parseSameSite(String? value) {
    for (final item in CookieSameSite.values) {
      if (item.name == value) return item;
    }
    return CookieSameSite.unspecified;
  }

  static CookieSource _parseSource(String? value) {
    for (final item in CookieSource.values) {
      if (item.name == value) return item;
    }
    return CookieSource.unknown;
  }
}
