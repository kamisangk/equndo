import '../l10n/s.dart';

/// 搜索范围类型（用于用户内容页面）
enum SearchInType {
  /// 书签
  bookmarks('bookmarks'),
  /// 用户创建的话题
  created('created'),
  /// 浏览过的
  seen('seen');

  final String value;
  const SearchInType(this.value);

  String get label {
    switch (this) {
      case SearchInType.bookmarks: return S.current.search_filterBookmarks;
      case SearchInType.created: return S.current.search_filterCreated;
      case SearchInType.seen: return S.current.search_filterSeen;
    }
  }
}

/// 话题状态过滤
enum SearchStatus {
  /// 未关闭
  open('open'),
  /// 已关闭
  closed('closed'),
  /// 已归档
  archived('archived'),
  /// 已解决
  solved('solved'),
  /// 未解决
  unsolved('unsolved');

  final String value;
  const SearchStatus(this.value);

  String get label {
    switch (this) {
      case SearchStatus.open: return S.current.search_statusOpen;
      case SearchStatus.closed: return S.current.search_statusClosed;
      case SearchStatus.archived: return S.current.search_statusArchived;
      case SearchStatus.solved: return S.current.search_statusSolved;
      case SearchStatus.unsolved: return S.current.search_statusUnsolved;
    }
  }
}

/// 高级搜索过滤参数
class SearchFilter {
  /// 分类 ID
  final int? categoryId;

  /// 分类 slug
  final String? categorySlug;

  /// 分类名称（用于显示）
  final String? categoryName;

  /// 父分类 slug
  final String? parentCategorySlug;

  /// 选中的标签列表
  final List<String> tags;

  /// 话题状态
  final SearchStatus? status;

  /// 搜索时间范围：在此日期之前
  final DateTime? beforeDate;

  /// 搜索时间范围：在此日期之后
  final DateTime? afterDate;

  /// 搜索范围类型（用于用户内容页面）
  final SearchInType? inType;

  const SearchFilter({
    this.categoryId,
    this.categorySlug,
    this.categoryName,
    this.parentCategorySlug,
    this.tags = const [],
    this.status,
    this.beforeDate,
    this.afterDate,
    this.inType,
  });

  /// 检查是否为空（没有任何过滤条件）
  bool get isEmpty =>
      categoryId == null &&
      tags.isEmpty &&
      status == null &&
      beforeDate == null &&
      afterDate == null;

  /// 检查是否有过滤条件
  bool get isNotEmpty => !isEmpty;

  /// 获取激活的过滤条件数量（不包括 inType）
  int get activeFilterCount {
    int count = 0;
    if (categoryId != null) count++;
    count += tags.length;
    if (status != null) count++;
    if (beforeDate != null || afterDate != null) count++;
    return count;
  }

  /// 复制并修改
  SearchFilter copyWith({
    int? categoryId,
    String? categorySlug,
    String? categoryName,
    String? parentCategorySlug,
    List<String>? tags,
    SearchStatus? status,
    DateTime? beforeDate,
    DateTime? afterDate,
    SearchInType? inType,
    bool clearCategory = false,
    bool clearStatus = false,
    bool clearDateRange = false,
  }) {
    return SearchFilter(
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      categorySlug: clearCategory ? null : (categorySlug ?? this.categorySlug),
      categoryName: clearCategory ? null : (categoryName ?? this.categoryName),
      parentCategorySlug:
          clearCategory ? null : (parentCategorySlug ?? this.parentCategorySlug),
      tags: tags ?? this.tags,
      status: clearStatus ? null : (status ?? this.status),
      beforeDate: clearDateRange ? null : (beforeDate ?? this.beforeDate),
      afterDate: clearDateRange ? null : (afterDate ?? this.afterDate),
      inType: inType ?? this.inType,
    );
  }

  /// 清除所有过滤条件（保留 inType）
  SearchFilter clear() {
    return SearchFilter(inType: inType);
  }

  /// 转换为 Discourse 搜索查询字符串
  /// 例如：in:bookmarks #分类 tags:flutter status:open after:2024-01-01
  String toQueryString() {
    final parts = <String>[];

    // 搜索范围
    if (inType != null) {
      parts.add('in:${inType!.value}');
    }

    // 分类
    if (categorySlug != null) {
      if (parentCategorySlug != null) {
        parts.add('#$parentCategorySlug:$categorySlug');
      } else {
        parts.add('#$categorySlug');
      }
    }

    // 标签
    for (final tag in tags) {
      parts.add('tags:$tag');
    }

    // 状态
    if (status != null) {
      parts.add('status:${status!.value}');
    }

    // 时间范围
    if (afterDate != null) {
      parts.add('after:${_formatDate(afterDate!)}');
    }
    if (beforeDate != null) {
      parts.add('before:${_formatDate(beforeDate!)}');
    }

    return parts.join(' ');
  }

  /// 格式化日期为 YYYY-MM-DD
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchFilter &&
          categoryId == other.categoryId &&
          status == other.status &&
          beforeDate == other.beforeDate &&
          afterDate == other.afterDate &&
          inType == other.inType &&
          _listEquals(tags, other.tags);

  @override
  int get hashCode => Object.hash(
        categoryId,
        status,
        beforeDate,
        afterDate,
        inType,
        Object.hashAll(tags),
      );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() {
    return 'SearchFilter(categoryId: $categoryId, tags: $tags, status: $status, '
        'beforeDate: $beforeDate, afterDate: $afterDate, inType: $inType)';
  }
}
