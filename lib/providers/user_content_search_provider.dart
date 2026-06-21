import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/search_filter.dart';
import '../models/search_result.dart';
import '../models/topic.dart';
import 'user_content_providers.dart';

/// 用户内容页面搜索状态
class UserContentSearchState {
  /// 是否处于搜索模式
  final bool isSearchMode;

  /// 当前搜索关键词
  final String query;

  /// 搜索过滤条件
  final SearchFilter filter;

  /// 搜索结果列表
  final List<SearchPost> results;

  /// 是否正在加载
  final bool isLoading;

  /// 是否有更多结果
  final bool hasMore;

  /// 加载更多是否失败
  final bool isLoadMoreFailed;

  /// 当前页码
  final int page;

  /// 错误信息
  final String? error;

  const UserContentSearchState({
    this.isSearchMode = false,
    this.query = '',
    this.filter = const SearchFilter(),
    this.results = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.isLoadMoreFailed = false,
    this.page = 1,
    this.error,
  });

  UserContentSearchState copyWith({
    bool? isSearchMode,
    String? query,
    SearchFilter? filter,
    List<SearchPost>? results,
    bool? isLoading,
    bool? hasMore,
    bool? isLoadMoreFailed,
    int? page,
    String? error,
    bool clearError = false,
  }) {
    return UserContentSearchState(
      isSearchMode: isSearchMode ?? this.isSearchMode,
      query: query ?? this.query,
      filter: filter ?? this.filter,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      isLoadMoreFailed: isLoadMoreFailed ?? this.isLoadMoreFailed,
      page: page ?? this.page,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 用户内容页面搜索 Notifier。
///
/// Equn Discuz 没有兼容原应用的用户内容搜索接口；这里对已适配的
/// “我的话题 / 我的书签”列表做本地过滤。
class UserContentSearchNotifier extends StateNotifier<UserContentSearchState> {
  static const int _pageSize = 50;

  final Ref _ref;
  final SearchInType _inType;
  List<SearchPost> _allMatches = const [];

  UserContentSearchNotifier(this._ref, this._inType)
    : super(UserContentSearchState(filter: SearchFilter(inType: _inType)));

  /// 进入搜索模式
  void enterSearchMode() {
    state = state.copyWith(isSearchMode: true);
  }

  /// 退出搜索模式，清除搜索状态
  void exitSearchMode() {
    _allMatches = const [];
    state = UserContentSearchState(filter: SearchFilter(inType: _inType));
  }

  /// 更新搜索关键词（不执行搜索）
  void updateQuery(String query) {
    state = state.copyWith(query: query);
  }

  /// 设置分类过滤
  void setCategory({
    int? categoryId,
    String? categorySlug,
    String? categoryName,
    String? parentCategorySlug,
  }) {
    state = state.copyWith(
      filter: state.filter.copyWith(
        categoryId: categoryId,
        categorySlug: categorySlug,
        categoryName: categoryName,
        parentCategorySlug: parentCategorySlug,
        clearCategory: categoryId == null,
      ),
    );
  }

  /// 设置标签过滤
  void setTags(List<String> tags) {
    state = state.copyWith(filter: state.filter.copyWith(tags: tags));
  }

  /// 切换标签选中状态
  void toggleTag(String tag) {
    final currentTags = List<String>.from(state.filter.tags);
    if (currentTags.contains(tag)) {
      currentTags.remove(tag);
    } else {
      currentTags.add(tag);
    }
    state = state.copyWith(filter: state.filter.copyWith(tags: currentTags));
  }

  /// 移除标签
  void removeTag(String tag) {
    final newTags = state.filter.tags.where((t) => t != tag).toList();
    state = state.copyWith(filter: state.filter.copyWith(tags: newTags));
  }

  /// 设置状态过滤
  void setStatus(SearchStatus? status) {
    state = state.copyWith(
      filter: state.filter.copyWith(
        status: status,
        clearStatus: status == null,
      ),
    );
  }

  /// 设置时间范围
  void setDateRange({DateTime? after, DateTime? before}) {
    state = state.copyWith(
      filter: state.filter.copyWith(
        afterDate: after,
        beforeDate: before,
        clearDateRange: after == null && before == null,
      ),
    );
  }

  /// 清除所有过滤条件
  void clearFilters() {
    state = state.copyWith(filter: state.filter.clear());
  }

  /// 执行本地搜索
  Future<void> search(String query) async {
    final trimmedQuery = query.trim();

    state = state.copyWith(
      query: trimmedQuery,
      isLoading: true,
      page: 1,
      results: [],
      hasMore: false,
      isLoadMoreFailed: false,
      clearError: true,
    );

    if (trimmedQuery.isEmpty) {
      _allMatches = const [];
      state = state.copyWith(isLoading: false);
      return;
    }

    try {
      final topics = await _loadSourceTopics();
      _allMatches = _filterTopics(
        topics,
        trimmedQuery,
      ).map(_topicToSearchPost).toList(growable: false);

      state = state.copyWith(
        results: _allMatches.take(_pageSize).toList(growable: false),
        hasMore: _allMatches.length > _pageSize,
        isLoading: false,
      );
    } catch (e) {
      _allMatches = const [];
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 加载更多本地结果
  Future<void> loadMore() async {
    if (state.isLoading ||
        !state.hasMore ||
        state.query.isEmpty ||
        state.isLoadMoreFailed) {
      return;
    }

    final nextPage = state.page + 1;
    final nextCount = nextPage * _pageSize;
    state = state.copyWith(
      results: _allMatches.take(nextCount).toList(growable: false),
      hasMore: _allMatches.length > nextCount,
      page: nextPage,
      isLoadMoreFailed: false,
      clearError: true,
    );
  }

  Future<void> retryLoadMore() async {
    if (!state.isLoadMoreFailed) return;
    state = state.copyWith(isLoadMoreFailed: false, clearError: true);
    await loadMore();
  }

  /// 使用当前过滤条件重新搜索
  Future<void> refreshWithCurrentFilters() async {
    if (state.query.isNotEmpty) {
      await search(state.query);
    }
  }

  Future<List<Topic>> _loadSourceTopics() async {
    switch (_inType) {
      case SearchInType.bookmarks:
        return _ref.read(bookmarksProvider.future);
      case SearchInType.created:
        return _ref.read(myTopicsProvider.future);
      case SearchInType.seen:
        return const <Topic>[];
    }
  }

  Iterable<Topic> _filterTopics(List<Topic> topics, String query) {
    final needle = query.toLowerCase();
    return topics.where((topic) {
      if (!_matchesText(topic, needle)) return false;
      if (!_matchesCategory(topic)) return false;
      if (!_matchesTags(topic)) return false;
      if (!_matchesStatus(topic)) return false;
      if (!_matchesDateRange(topic)) return false;
      return true;
    });
  }

  bool _matchesText(Topic topic, String needle) {
    final values = [
      topic.title,
      topic.excerpt,
      topic.lastPosterUsername,
      topic.bookmarkName,
      ...topic.tags.map((tag) => tag.name),
      ...topic.posters.map((poster) => poster.user?.username),
    ].whereType<String>();
    return values.any((value) => value.toLowerCase().contains(needle));
  }

  bool _matchesCategory(Topic topic) {
    final categoryId = state.filter.categoryId;
    if (categoryId == null) return true;
    return topic.categoryId == categoryId.toString();
  }

  bool _matchesTags(Topic topic) {
    final tags = state.filter.tags;
    if (tags.isEmpty) return true;
    final topicTags = topic.tags.map((tag) => tag.name).toSet();
    return tags.every(topicTags.contains);
  }

  bool _matchesStatus(Topic topic) {
    switch (state.filter.status) {
      case null:
        return true;
      case SearchStatus.open:
        return !topic.closed && !topic.archived;
      case SearchStatus.closed:
        return topic.closed;
      case SearchStatus.archived:
        return topic.archived;
      case SearchStatus.solved:
        return topic.hasAcceptedAnswer;
      case SearchStatus.unsolved:
        return topic.canHaveAnswer && !topic.hasAcceptedAnswer;
    }
  }

  bool _matchesDateRange(Topic topic) {
    final date = topic.createdAt ?? topic.lastPostedAt;
    if (date == null) return true;
    final after = state.filter.afterDate;
    if (after != null && date.isBefore(after)) return false;
    final before = state.filter.beforeDate;
    if (before != null && date.isAfter(before)) return false;
    return true;
  }

  SearchPost _topicToSearchPost(Topic topic) {
    final firstPoster = topic.posters.isEmpty ? null : topic.posters.first;
    final username =
        topic.lastPosterUsername ?? firstPoster?.user?.username ?? '';
    final avatarTemplate = firstPoster?.user?.avatarTemplate ?? '';
    return SearchPost(
      id: topic.id,
      username: username,
      avatarTemplate: avatarTemplate,
      createdAt: topic.lastPostedAt ?? topic.createdAt ?? DateTime.now(),
      likeCount: topic.likeCount,
      blurb: topic.excerpt ?? topic.title,
      postNumber: topic.bookmarkedPostNumber ?? topic.lastReadPostNumber ?? 1,
      topicTitleHeadline: topic.title,
      topic: SearchTopic(
        id: topic.id,
        title: topic.title,
        slug: topic.slug,
        categoryId: int.tryParse(topic.categoryId),
        tags: topic.tags,
        postsCount: topic.postsCount,
        views: topic.views,
        closed: topic.closed,
        archived: topic.archived,
      ),
    );
  }
}

/// 用户内容搜索 Provider
/// 使用 family 参数区分不同的页面类型
final userContentSearchProvider =
    StateNotifierProvider.family<
      UserContentSearchNotifier,
      UserContentSearchState,
      SearchInType
    >((ref, inType) => UserContentSearchNotifier(ref, inType));
