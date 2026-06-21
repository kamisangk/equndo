import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/search_result.dart';
import 'core_providers.dart';
import 'search_settings_provider.dart';

/// 话题内搜索状态
class TopicSearchState {
  /// 话题 ID
  final int topicId;

  /// 是否处于搜索模式
  final bool isSearchMode;

  /// 当前搜索关键词
  final String query;

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

  const TopicSearchState({
    required this.topicId,
    this.isSearchMode = false,
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.isLoadMoreFailed = false,
    this.page = 1,
    this.error,
  });

  TopicSearchState copyWith({
    bool? isSearchMode,
    String? query,
    List<SearchPost>? results,
    bool? isLoading,
    bool? hasMore,
    bool? isLoadMoreFailed,
    int? page,
    String? error,
    bool clearError = false,
  }) {
    return TopicSearchState(
      topicId: topicId,
      isSearchMode: isSearchMode ?? this.isSearchMode,
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      isLoadMoreFailed: isLoadMoreFailed ?? this.isLoadMoreFailed,
      page: page ?? this.page,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 话题内搜索 Notifier
class TopicSearchNotifier extends StateNotifier<TopicSearchState> {
  final Ref _ref;

  TopicSearchNotifier(this._ref, int topicId)
      : super(TopicSearchState(topicId: topicId));

  /// 进入搜索模式
  void enterSearchMode() {
    state = state.copyWith(isSearchMode: true);
  }

  /// 退出搜索模式，清除搜索状态
  void exitSearchMode() {
    state = TopicSearchState(topicId: state.topicId);
  }

  /// 执行搜索
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
      state = state.copyWith(isLoading: false);
      return;
    }

    try {
      final service = _ref.read(discourseServiceProvider);
      final sortOrder = _ref.read(searchSettingsProvider).sortOrder;

      // 构建带 topic: 前缀的搜索查询
      String fullQuery = '$trimmedQuery topic:${state.topicId}';
      if (sortOrder.value != null) {
        fullQuery = '$fullQuery order:${sortOrder.value}';
      }

      final result = await service.search(query: fullQuery, page: 1, typeFilter: 'topic');

      state = state.copyWith(
        results: result.posts,
        hasMore: result.hasMorePosts && result.posts.isNotEmpty,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 加载更多结果
  Future<void> loadMore() async {
    if (state.isLoading ||
        !state.hasMore ||
        state.query.isEmpty ||
        state.isLoadMoreFailed) {
      return;
    }

    final nextPage = state.page + 1;
    state = state.copyWith(
      isLoading: true,
      isLoadMoreFailed: false,
      page: nextPage,
      clearError: true,
    );

    try {
      final service = _ref.read(discourseServiceProvider);
      final sortOrder = _ref.read(searchSettingsProvider).sortOrder;

      // 构建带 topic: 前缀的搜索查询
      String fullQuery = '${state.query} topic:${state.topicId}';
      if (sortOrder.value != null) {
        fullQuery = '$fullQuery order:${sortOrder.value}';
      }

      final result = await service.search(query: fullQuery, page: nextPage, typeFilter: 'topic');

      state = state.copyWith(
        results: [...state.results, ...result.posts],
        hasMore: result.hasMorePosts && result.posts.isNotEmpty,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        page: state.page - 1,
        isLoadMoreFailed: true,
        error: e.toString(),
      );
    }
  }

  Future<void> retryLoadMore() async {
    if (!state.isLoadMoreFailed) return;
    state = state.copyWith(isLoadMoreFailed: false, clearError: true);
    await loadMore();
  }
}

/// 话题内搜索 Provider
/// 使用 family 参数区分不同话题
final topicSearchProvider =
    StateNotifierProvider.family<TopicSearchNotifier, TopicSearchState, int>(
  (ref, topicId) => TopicSearchNotifier(ref, topicId),
);
