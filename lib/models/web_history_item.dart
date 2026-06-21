/// 内置浏览器浏览历史项
class WebHistoryItem {
  final String url;
  final String title;
  final DateTime visitedAt; // 最近访问时间（本地生成，不走 TimeUtils）

  const WebHistoryItem({
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'visitedAt': visitedAt.toIso8601String(),
      };

  factory WebHistoryItem.fromJson(Map<String, dynamic> json) =>
      WebHistoryItem(
        url: json['url'] as String,
        title: json['title'] as String,
        visitedAt: DateTime.parse(json['visitedAt'] as String),
      );

  WebHistoryItem copyWith({String? title, DateTime? visitedAt}) =>
      WebHistoryItem(
        url: url,
        title: title ?? this.title,
        visitedAt: visitedAt ?? this.visitedAt,
      );
}
