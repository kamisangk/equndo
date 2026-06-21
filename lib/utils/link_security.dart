import '../config/site_customization.dart';

/// URL 解析信息
class LinkUrlInfo {
  /// 完整 URL
  final String url;

  /// 协议（http/https）
  final String scheme;

  /// 主机名
  final String host;

  /// 路径
  final String path;

  /// 查询参数
  final String query;

  /// 完整路径（含查询参数）
  final String fullPath;

  LinkUrlInfo({
    required this.url,
    required this.scheme,
    required this.host,
    required this.path,
    required this.query,
    required this.fullPath,
  });

  /// 从 URL 字符串解析
  static LinkUrlInfo? parse(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;

    return LinkUrlInfo(
      url: url,
      scheme: uri.scheme,
      host: uri.host.toLowerCase(),
      path: uri.path,
      query: uri.query,
      fullPath: uri.query.isEmpty ? uri.path : '${uri.path}?${uri.query}',
    );
  }
}

/// 链接安全检查工具
class LinkSecurity {
  /// 检查 URL 的风险等级
  static LinkRiskLevel checkUrl(String url, LinkSecurityConfig config) {
    final urlInfo = LinkUrlInfo.parse(url);
    if (urlInfo == null) return LinkRiskLevel.normal;

    // 按优先级检查（与 JS 一致）：阻止 > 危险 > 风险 > 信任 > 内部
    // 阻止域名
    if (_matchAnyRule(urlInfo, config.blockedDomains)) {
      return LinkRiskLevel.blocked;
    }

    // 危险域名
    if (_matchAnyRule(urlInfo, config.dangerousDomains)) {
      return LinkRiskLevel.dangerous;
    }

    // 风险域名
    if (_matchAnyRule(urlInfo, config.riskyDomains)) {
      return LinkRiskLevel.risky;
    }

    // 信任域名
    if (_matchAnyRule(urlInfo, config.trustedDomains)) {
      return LinkRiskLevel.trusted;
    }

    // 内部域名
    if (_matchAnyRule(urlInfo, config.internalDomains)) {
      return LinkRiskLevel.internal;
    }

    // 默认为普通外部链接
    return LinkRiskLevel.normal;
  }

  /// 检查是否匹配任一规则
  static bool _matchAnyRule(LinkUrlInfo urlInfo, List<String> rules) {
    for (final rule in rules) {
      if (_matchRule(urlInfo, rule)) return true;
    }
    return false;
  }

  /// 匹配单个规则
  ///
  /// 规则语法：
  /// - `^regex` - 正则表达式匹配完整 URL
  /// - `**keyword` - URL 中包含关键词
  /// - `*.domain.com` - 通配符匹配子域名
  /// - `domain.com/path/*` - 路径通配符
  /// - `domain.com` - 精确匹配域名
  static bool _matchRule(LinkUrlInfo urlInfo, String rule) {
    // 正则匹配
    if (rule.startsWith('^')) {
      try {
        final regex = RegExp(rule.substring(1));
        return regex.hasMatch(urlInfo.url);
      } catch (_) {
        return false;
      }
    }

    // URL 包含关键词（与 JS 一致，忽略大小写）
    if (rule.startsWith('**')) {
      final keyword = rule.substring(2).trim().toLowerCase();
      return urlInfo.url.toLowerCase().contains(keyword);
    }

    // 解析规则
    String domainPattern;
    String? pathPattern;

    final slashIndex = rule.indexOf('/');
    if (slashIndex != -1) {
      domainPattern = rule.substring(0, slashIndex);
      pathPattern = rule.substring(slashIndex);
    } else {
      domainPattern = rule;
    }

    // 匹配域名
    if (!_matchDomain(urlInfo.host, domainPattern)) {
      return false;
    }

    // 如果有路径模式，还需匹配路径
    if (pathPattern != null) {
      return _matchPath(urlInfo.fullPath, pathPattern);
    }

    return true;
  }

  /// 匹配域名
  ///
  /// - `*.domain.com` - 匹配子域名（包括 domain.com 本身）
  /// - `domain.com` - 精确匹配
  static bool _matchDomain(String host, String pattern) {
    // 通配符匹配子域名
    if (pattern.startsWith('*.')) {
      final baseDomain = pattern.substring(2).toLowerCase();
      return host == baseDomain || host.endsWith('.$baseDomain');
    }

    // 精确匹配
    return host == pattern.toLowerCase();
  }

  /// 匹配路径
  ///
  /// - `/path/*` - 路径前缀匹配
  /// - `/path/file` - 精确匹配
  static bool _matchPath(String path, String pattern) {
    // 路径通配符
    if (pattern.endsWith('/*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      return path.startsWith(prefix);
    }

    // 精确匹配
    return path == pattern || path.startsWith('$pattern?');
  }

  /// 检查是否是本地 IP 地址
  static bool isLocalIp(String host) {
    // localhost
    if (host == 'localhost') return true;

    // .local 域名
    if (host.endsWith('.local')) return true;

    // IP 地址检查
    final parts = host.split('.');
    if (parts.length != 4) return false;

    final nums = <int>[];
    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
      nums.add(num);
    }

    // 127.x.x.x (loopback)
    if (nums[0] == 127) return true;

    // 10.x.x.x (Class A private)
    if (nums[0] == 10) return true;

    // 192.168.x.x (Class C private)
    if (nums[0] == 192 && nums[1] == 168) return true;

    // 172.16-31.x.x (Class B private)
    if (nums[0] == 172 && nums[1] >= 16 && nums[1] <= 31) return true;

    return false;
  }
}
