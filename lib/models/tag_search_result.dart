/// 标签搜索结果
class TagSearchResult {
  /// 标签列表
  final List<TagInfo> results;

  /// 必选标签组信息（如果有）
  final RequiredTagGroup? requiredTagGroup;

  TagSearchResult({required this.results, this.requiredTagGroup});

  factory TagSearchResult.fromJson(Map<String, dynamic> json) {
    return TagSearchResult(
      results: (json['results'] as List?)
              ?.map((e) => TagInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      requiredTagGroup: json['required_tag_group'] != null
          ? RequiredTagGroup.fromJson(
              json['required_tag_group'] as Map<String, dynamic>)
          : null,
    );
  }

  /// 获取标签名列表
  List<String> get tagNames => results.map((e) => e.name).toList();
}

/// 标签信息
class TagInfo {
  final String name;
  final String text;
  final int count;

  TagInfo({required this.name, required this.text, required this.count});

  factory TagInfo.fromJson(Map<String, dynamic> json) {
    return TagInfo(
      name: json['name'] as String,
      text: json['text'] as String? ?? json['name'] as String,
      count: json['count'] as int? ?? 0,
    );
  }
}

/// 必选标签组
class RequiredTagGroup {
  final String name;
  final int minCount;

  RequiredTagGroup({required this.name, required this.minCount});

  factory RequiredTagGroup.fromJson(Map<String, dynamic> json) {
    return RequiredTagGroup(
      name: json['name'] as String,
      minCount: json['min_count'] as int? ?? 1,
    );
  }
}
