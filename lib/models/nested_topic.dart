import 'topic.dart';

/// 树形节点：帖子 + 预加载的子节点
class NestedNode {
  final Post post;
  final List<NestedNode> children;
  final int directReplyCount;
  final int totalDescendantCount;
  final bool isDeletedPlaceholder;

  const NestedNode({
    required this.post,
    this.children = const [],
    this.directReplyCount = 0,
    this.totalDescendantCount = 0,
    this.isDeletedPlaceholder = false,
  });

  factory NestedNode.fromJson(Map<String, dynamic> json) {
    final childrenJson = json['children'] as List<dynamic>? ?? [];
    return NestedNode(
      post: Post.fromJson(json),
      children: childrenJson
          .map((e) => NestedNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      directReplyCount: json['direct_reply_count'] as int? ?? 0,
      totalDescendantCount: json['total_descendant_count'] as int? ?? 0,
      isDeletedPlaceholder: json['deleted_post_placeholder'] as bool? ?? false,
    );
  }

  /// 是否有未加载的子回复
  bool get hasMoreChildren => directReplyCount > children.length;

  NestedNode copyWith({
    Post? post,
    List<NestedNode>? children,
    int? directReplyCount,
    int? totalDescendantCount,
    bool? isDeletedPlaceholder,
  }) {
    return NestedNode(
      post: post ?? this.post,
      children: children ?? this.children,
      directReplyCount: directReplyCount ?? this.directReplyCount,
      totalDescendantCount: totalDescendantCount ?? this.totalDescendantCount,
      isDeletedPlaceholder: isDeletedPlaceholder ?? this.isDeletedPlaceholder,
    );
  }
}

/// 根帖子列表 API 响应
class NestedRootsResponse {
  final Map<String, dynamic>? topicJson; // page=0 时有话题元数据
  final Post? opPost;
  final String? sort;
  final List<NestedNode> roots;
  final bool hasMoreRoots;
  final int page;
  final int? pinnedPostNumber;

  const NestedRootsResponse({
    this.topicJson,
    this.opPost,
    this.sort,
    required this.roots,
    required this.hasMoreRoots,
    required this.page,
    this.pinnedPostNumber,
  });

  factory NestedRootsResponse.fromJson(Map<String, dynamic> json) {
    final rootsJson = json['roots'] as List<dynamic>? ?? [];
    final opPostJson = json['op_post'] as Map<String, dynamic>?;

    return NestedRootsResponse(
      topicJson: json['topic'] as Map<String, dynamic>?,
      opPost: opPostJson != null ? Post.fromJson(opPostJson) : null,
      sort: json['sort'] as String?,
      roots: rootsJson
          .map((e) => NestedNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMoreRoots: json['has_more_roots'] as bool? ?? false,
      page: json['page'] as int? ?? 0,
      pinnedPostNumber: json['pinned_post_number'] as int?,
    );
  }
}

/// 子回复创建事件（用于通知 NestedPostCard 组件插入新子帖子）
class NestedChildCreatedEvent {
  final Post post;
  final int parentPostNumber;
  final int _id;

  NestedChildCreatedEvent({
    required this.post,
    required this.parentPostNumber,
  }) : _id = _nextId++;

  static int _nextId = 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NestedChildCreatedEvent && _id == other._id;

  @override
  int get hashCode => _id.hashCode;
}

/// 子回复 API 响应
class NestedChildrenResponse {
  final List<NestedNode> children;
  final bool hasMore;
  final int page;

  const NestedChildrenResponse({
    required this.children,
    required this.hasMore,
    required this.page,
  });

  factory NestedChildrenResponse.fromJson(Map<String, dynamic> json) {
    final childrenJson = json['children'] as List<dynamic>? ?? [];
    return NestedChildrenResponse(
      children: childrenJson
          .map((e) => NestedNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: json['has_more'] as bool? ?? false,
      page: json['page'] as int? ?? 0,
    );
  }
}
