/// 网页收藏项数据模型
class WebBookmark {
  final String url;
  final String title;
  final DateTime createdAt; // 收藏时间（本地生成，不走 TimeUtils）

  const WebBookmark({
    required this.url,
    required this.title,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
      };

  factory WebBookmark.fromJson(Map<String, dynamic> json) => WebBookmark(
        url: json['url'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
