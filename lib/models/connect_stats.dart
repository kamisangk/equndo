import 'package:html/parser.dart' as html_parser;

/// connect.linux.do 信任等级周期统计模型
class ConnectStats {
  final int daysVisited;
  final int topicsRepliedTo; // 独有：回复主题数
  final int topicsViewed;
  final int postsRead;
  final int likesGiven;
  final int likesReceived;
  final int likesReceivedDays; // 独有：获赞天数
  final int likesReceivedUsers; // 独有：获赞人数
  final int timePeriod; // 时间周期（天数）

  const ConnectStats({
    this.daysVisited = 0,
    this.topicsRepliedTo = 0,
    this.topicsViewed = 0,
    this.postsRead = 0,
    this.likesGiven = 0,
    this.likesReceived = 0,
    this.likesReceivedDays = 0,
    this.likesReceivedUsers = 0,
    this.timePeriod = 100,
  });

  /// 从 connect.linux.do HTML 解析
  factory ConnectStats.fromHtml(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final cardDiv = document.querySelector('div.card');
    if (cardDiv == null) {

      throw Exception('未找到统计卡片');
    }

    // 收集所有指标：label → value
    final metrics = <String, int>{};

    // 环形指标（ring）
    final ringEls = cardDiv.querySelectorAll('.tl3-ring');

    for (final el in ringEls) {
      final label = el.querySelector('.tl3-ring-label')?.text.trim() ?? '';
      final circle = el.querySelector('.tl3-ring-circle');
      final style = circle?.attributes['style'] ?? '';
      final val = _parseCssVar(style, '--val');

      if (label.isNotEmpty) metrics[label] = val;
    }

    // 条形指标（bar）
    final barEls = cardDiv.querySelectorAll('.tl3-bar-item');

    for (final el in barEls) {
      final label = el.querySelector('.tl3-bar-label')?.text.trim() ?? '';
      final fill = el.querySelector('.tl3-bar-fill');
      final style = fill?.attributes['style'] ?? '';
      final val = _parseCssVar(style, '--val');
      // 同时尝试 nums 文本
      final numsText = el.querySelector('.tl3-bar-nums')?.text.trim() ?? '';
      final numsVal = _parseFirstNumber(numsText);
      final finalVal = numsVal > 0 ? numsVal : val;

      if (label.isNotEmpty) metrics[label] = finalVal;
    }


    // 从副标题解析时间周期
    int timePeriod = 100;
    final subtitle = cardDiv.querySelector('.card-subtitle')?.text.trim() ?? '';
    final periodMatch = RegExp(r'(\d+)\s*[天days]').firstMatch(subtitle);
    if (periodMatch != null) {
      timePeriod = int.tryParse(periodMatch.group(1) ?? '100') ?? 100;
    }

    // 通过标签名模糊匹配字段
    return ConnectStats(
      daysVisited: _match(metrics, ['访问天数', 'days visited']),
      topicsRepliedTo: _match(metrics, ['回复话题', '回复主题', 'topics replied']),
      topicsViewed: _match(metrics, ['浏览话题', 'topics viewed', '浏览主题']),
      postsRead: _match(metrics, ['浏览帖子', '已读帖子', 'posts read']),
      likesGiven: _matchExclude(metrics, ['点赞', '送赞', 'likes given'], ['获', 'received']),
      likesReceived: _matchExclude(metrics, ['获赞', 'likes received'], ['天数', '用户', '人数', 'days', 'users']),
      likesReceivedDays: _match(metrics, ['获赞天数', 'liked days']),
      likesReceivedUsers: _match(metrics, ['获赞用户', '获赞人数', 'liked users']),
      timePeriod: timePeriod,
    );
  }

  /// 解析 CSS 变量
  static int _parseCssVar(String style, String varName) {
    final regex = RegExp('$varName:\\s*([0-9.]+)');
    final match = regex.firstMatch(style);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '0')?.toInt() ?? 0;
    }
    return 0;
  }

  /// 从文本中提取第一个整数
  static int _parseFirstNumber(String text) {
    if (text.isEmpty) return 0;
    final cleaned = text.replaceAll(RegExp(r'[,，\s]'), '');
    final match = RegExp(r'-?\d+').firstMatch(cleaned);
    return match != null ? (int.tryParse(match.group(0)!) ?? 0) : 0;
  }

  /// 模糊匹配 label
  static int _match(Map<String, int> data, List<String> keywords) {
    for (final entry in data.entries) {
      final lower = entry.key.toLowerCase();
      if (keywords.any((kw) => lower.contains(kw.toLowerCase()))) {
        return entry.value;
      }
    }
    return 0;
  }

  /// 模糊匹配 label，排除含特定关键词的项
  static int _matchExclude(
    Map<String, int> data,
    List<String> keywords,
    List<String> exclude,
  ) {
    for (final entry in data.entries) {
      final lower = entry.key.toLowerCase();
      final matched = keywords.any((kw) => lower.contains(kw.toLowerCase()));
      if (!matched) continue;
      final excluded = exclude.any((ex) => lower.contains(ex.toLowerCase()));
      if (excluded) continue;
      return entry.value;
    }
    return 0;
  }
}
