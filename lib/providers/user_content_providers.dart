import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/topic.dart';
import '../pages/bookmarks/bookmarks_models.dart';
import '../services/discuz/equn_discuz_adapter.dart';
import '../utils/paged_async_notifier.dart';
import '../utils/pagination_helper.dart';
import 'bookmarks_reconciler.dart';
import 'equn_discuz_providers.dart';

final bookmarksPageLoaderProvider = Provider<BookmarkPageLoader>((ref) {
  final service = ref.read(equnDiscuzServiceProvider);
  return (page, limit) async {
    final response = await service.fetchFavoriteTopics(page: page + 1);
    return EqunDiscuzAdapter.userTopicsToResponse(response);
  };
});

/// 当前账号 username，作为本地书签缓存的隔离键；抽出来便于测试注入。
final currentUsernameProvider = FutureProvider<String?>((ref) async {
  return (await ref.read(equnDiscuzServiceProvider).fetchCurrentProfile())
      ?.username;
});

/// 分页助手（所有用户内容列表共用）
final _topicPaginationHelper = PaginationHelpers.forTopics<Topic>(
  keyExtractor: (topic) => topic.id,
);

/// 浏览历史 Notifier (支持分页)
class BrowsingHistoryNotifier extends AsyncNotifier<List<Topic>>
    with PagedAsyncNotifierMixin<Topic> {
  @override
  Future<List<Topic>> build() async {
    resetPagingState(hasMore: false);
    return const <Topic>[];
  }

  Future<void> refresh() async {
    resetPagingState(hasMore: false);
    state = const AsyncValue.data(<Topic>[]);
  }

  Future<void> loadMore() async {}

  Future<void> retryLoadMore() async {}
}

final browsingHistoryProvider =
    AsyncNotifierProvider.autoDispose<BrowsingHistoryNotifier, List<Topic>>(() {
      return BrowsingHistoryNotifier();
    });

/// 书签 Notifier：读取 Discuz 收藏主题列表。
class BookmarksNotifier extends AsyncNotifier<List<Topic>> {
  bool _isLoadingMore = false;
  bool _isLoadMoreFailed = false;
  List<Topic> _remoteTopics = const <Topic>[];
  int _remotePage = 1;
  bool _remoteHasMore = true;

  bool get isReconciling => false;
  bool get isLastReconcileFailed => false;
  ReconcileMode? get ongoingReconcileMode => null;

  bool get hasMore => _remoteHasMore;

  /// 上一次 [loadMore] 是否失败。
  bool get isLoadMoreFailed => _isLoadMoreFailed;

  /// 兼容旧 UI：映射到"对账进行中"。
  bool get isHydratingAll => false;

  @override
  Future<List<Topic>> build() async {
    return _loadRemoteFirstPage();
  }

  Future<List<Topic>> _loadRemoteFirstPage() async {
    _remotePage = 1;
    _isLoadMoreFailed = false;
    final response = await ref
        .read(equnDiscuzServiceProvider)
        .fetchFavoriteTopics(page: _remotePage);
    final adapted = EqunDiscuzAdapter.userTopicsToResponse(response);
    _remoteTopics = List<Topic>.unmodifiable(adapted.topics);
    _remoteHasMore = adapted.moreTopicsUrl != null && adapted.topics.isNotEmpty;
    return _remoteTopics;
  }

  /// 下拉刷新：重新读取 Discuz 收藏主题第一页。
  Future<void> refresh() async {
    state = const AsyncLoading<List<Topic>>();
    state = await AsyncValue.guard(_loadRemoteFirstPage);
  }

  /// 兼容旧 API。Discuz 收藏没有 Discourse 本地对账流程。
  Future<ReconcileReport?> manualFullReconcile() async {
    await refresh();
    return null;
  }

  /// 加载下一页 Discuz 收藏主题。
  Future<void> loadMore() async {
    if (_isLoadingMore) return;
    if (!hasMore) return;
    _isLoadingMore = true;
    _isLoadMoreFailed = false;
    try {
      final nextPage = _remotePage + 1;
      final response = await ref
          .read(equnDiscuzServiceProvider)
          .fetchFavoriteTopics(page: nextPage);
      final adapted = EqunDiscuzAdapter.userTopicsToResponse(response);
      if (!ref.mounted) return;
      final existingIds = _remoteTopics.map((topic) => topic.id).toSet();
      final newTopics = adapted.topics
          .where((topic) => existingIds.add(topic.id))
          .toList();
      final merged = <Topic>[..._remoteTopics, ...newTopics];
      _remoteTopics = List<Topic>.unmodifiable(merged);
      _remotePage = nextPage;
      _remoteHasMore = adapted.moreTopicsUrl != null && newTopics.isNotEmpty;
      state = AsyncValue.data(List<Topic>.unmodifiable(merged));
    } catch (_) {
      _isLoadMoreFailed = true;
      _emit();
    } finally {
      _isLoadingMore = false;
    }
  }

  /// 上一次 [loadMore] 失败时让用户点击"重试"。
  void retryLoadMore() {
    if (_isLoadingMore) return;
    if (!_isLoadMoreFailed) return;
    loadMore();
  }

  /// 本地写穿透：编辑书签元数据（name / reminderAt）后调用，写入 repository。
  /// 实际 UI 刷新由 repository.watch 推送。
  Future<void> applyLocalEditResult(
    int bookmarkId, {
    required String? name,
    required DateTime? reminderAt,
  }) async {}

  /// 本地写穿透：删除书签后调用。
  Future<void> removeBookmarkLocally(int bookmarkId) async {}

  /// 兼容旧 API：同步移除本地某条书签（实际异步写入 repository）。
  void removeBookmarkById(int bookmarkId) {}

  /// 兼容旧 API：更新本地某条书签的元数据。
  void updateBookmarkMeta(
    int bookmarkId, {
    String? name,
    DateTime? reminderAt,
    bool clearName = false,
    bool clearReminderAt = false,
  }) {}

  void _emit() {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    // 重新打包同一个 list 让监听 notifier 状态的 widget 感知到状态字段变化。
    state = AsyncValue.data(List<Topic>.unmodifiable(current));
  }
}

final bookmarksProvider =
    AsyncNotifierProvider.autoDispose<BookmarksNotifier, List<Topic>>(() {
      return BookmarksNotifier();
    });

/// 我的话题 Notifier (支持分页)
class MyTopicsNotifier extends AsyncNotifier<List<Topic>>
    with PagedAsyncNotifierMixin<Topic> {
  String? _username;

  @override
  Future<List<Topic>> build() async {
    resetPagingState();
    final response = await _fetchMyTopics(1);

    final result = _topicPaginationHelper.processRefresh(
      PaginationResult(items: response.topics, moreUrl: response.moreTopicsUrl),
    );
    return completePagedRefresh(PagedPage.fromPagination(result));
  }

  Future<void> refresh() async {
    await runPagedRefresh(() async {
      final response = await _fetchMyTopics(1);

      final result = _topicPaginationHelper.processRefresh(
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );
      return PagedPage.fromPagination(result);
    });
  }

  Future<void> loadMore() async {
    await runPagedLoadMore((currentList, nextPage) async {
      final response = await _fetchMyTopics(nextPage + 1);

      final currentState = PaginationState(items: currentList);
      final paginationResult = _topicPaginationHelper.processLoadMore(
        currentState,
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );

      return PagedPage.fromPagination(
        paginationResult,
        advancePage: response.topics.isNotEmpty,
      );
    });
  }

  Future<void> retryLoadMore() {
    return retryPagedLoadMore(loadMore);
  }

  Future<TopicListResponse> _fetchMyTopics(int page) async {
    final service = ref.read(equnDiscuzServiceProvider);
    _username ??= (await service.fetchCurrentProfile())?.username;
    final response = await service.fetchMyTopics(
      page: page,
      username: _username,
    );
    return EqunDiscuzAdapter.userTopicsToResponse(response);
  }
}

final myTopicsProvider =
    AsyncNotifierProvider.autoDispose<MyTopicsNotifier, List<Topic>>(() {
      return MyTopicsNotifier();
    });
