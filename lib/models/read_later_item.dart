/// 稍后阅读项数据模型
class ReadLaterItem {
  final int topicId;
  final String title;
  final int? scrollToPostNumber; // 加入浮窗时的阅读位置
  final DateTime addedAt; // 加入时间（本地生成，不走 TimeUtils）

  const ReadLaterItem({
    required this.topicId,
    required this.title,
    this.scrollToPostNumber,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'topicId': topicId,
        'title': title,
        'scrollToPostNumber': scrollToPostNumber,
        'addedAt': addedAt.toIso8601String(),
      };

  factory ReadLaterItem.fromJson(Map<String, dynamic> json) => ReadLaterItem(
        topicId: json['topicId'] as int,
        title: json['title'] as String,
        scrollToPostNumber: json['scrollToPostNumber'] as int?,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );

  /// 创建一个更新了阅读位置的副本
  ReadLaterItem copyWith({int? scrollToPostNumber}) => ReadLaterItem(
        topicId: topicId,
        title: title,
        scrollToPostNumber: scrollToPostNumber ?? this.scrollToPostNumber,
        addedAt: addedAt,
      );
}
