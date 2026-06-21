import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/topic.dart';
import '../../services/discuz/equn_discuz_adapter.dart';
import '../../services/discuz/equn_discuz_models.dart';
import '../../services/discuz/equn_discuz_service.dart';
import '../../utils/paged_async_notifier.dart';
import '../../utils/pagination_helper.dart';
import '../equn_discuz_providers.dart';
import '../message_bus/topic_tracking_providers.dart';
import 'filter_provider.dart';
import 'sort_provider.dart';

/// 话题列表 Notifier (支持分页、静默刷新和筛选)
class TopicListNotifier extends AsyncNotifier<List<Topic>>
    with PagedAsyncNotifierMixin<Topic> {
  TopicListNotifier(this._categoryId);

  final int? _categoryId;

  /// 分页助手
  static final _paginationHelper = PaginationHelpers.forTopics<Topic>(
    keyExtractor: (topic) => topic.id,
  );

  @override
  Future<List<Topic>> build() async {
    // 所有参数使用 ref.read（不建立依赖），
    // 由 UI 层在参数变化时主动 invalidate provider
    final currentFilter = ref.read(topicFilterProvider);

    resetPagingState();

    final equnService = ref.read(equnDiscuzServiceProvider);
    final response = await _fetchEqunTopics(equnService, currentFilter, 0);
    final result = _paginationHelper.processRefresh(
      PaginationResult(items: response.topics, moreUrl: response.moreTopicsUrl),
    );
    return completePagedRefresh(PagedPage.fromPagination(result));
  }

  Future<TopicListResponse> _fetchEqunTopics(
    EqunDiscuzService service,
    TopicListFilter filter,
    int page,
  ) async {
    final equnPage = page + 1;
    if (_categoryId != null) {
      final response = await service.fetchForumTopics(
        _categoryId,
        page: equnPage,
        orderBy: _currentForumOrderBy,
      );
      final hasMore =
          response.topics.isNotEmpty &&
          response.topics.length >= response.pageSize;
      return EqunDiscuzAdapter.forumTopicsToResponse(
        response,
        hasMore: hasMore,
      );
    }

    final topics = await service.fetchGuideTopics(
      EqunDiscuzAdapter.guideFilterForTopicFilter(filter),
      page: equnPage,
    );
    return EqunDiscuzAdapter.guideTopicsToResponse(
      topics,
      hasMore: topics.isNotEmpty,
    );
  }

  /// 获取当前筛选模式
  TopicListFilter get _currentFilter => ref.read(topicFilterProvider);

  /// Equn Discuz 论坛列表使用的排序字段。
  /// 首页分类 tab 只暴露发帖时间、回复/查看、查看；历史持久化的其它排序值
  /// 回退到发帖时间，避免出现 UI 显示和请求排序不一致。
  String get _currentForumOrderBy {
    switch (ref.read(topicSortOrderProvider)) {
      case TopicSortOrder.posts:
        return 'replies';
      case TopicSortOrder.views:
        return 'views';
      case TopicSortOrder.defaultOrder:
      case TopicSortOrder.created:
      case TopicSortOrder.activity:
      case TopicSortOrder.likes:
      case TopicSortOrder.posters:
        return 'dateline';
    }
  }

  /// 刷新列表
  Future<void> refresh() async {
    await runPagedRefresh(() async {
      final service = ref.read(equnDiscuzServiceProvider);
      final response = await _fetchEqunTopics(service, _currentFilter, 0);

      final result = _paginationHelper.processRefresh(
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );
      return PagedPage.fromPagination(result);
    });
  }

  /// 静默刷新
  Future<void> silentRefresh() async {
    final service = ref.read(equnDiscuzServiceProvider);
    try {
      final response = await _fetchEqunTopics(service, _currentFilter, 0);

      final result = _paginationHelper.processRefresh(
        PaginationResult(
          items: response.topics,
          moreUrl: response.moreTopicsUrl,
        ),
      );
      state = AsyncValue.data(
        completePagedRefresh(PagedPage.fromPagination(result)),
      );
    } catch (e) {
      debugPrint('Silent refresh failed: $e');
    }
  }

  /// 按 topic_ids 加载并插入到列表顶部（对齐网页版 loadBefore）
  ///
  /// 1. 请求 /latest.json?topic_ids=xxx 获取这些话题的最新数据
  /// 2. 从当前列表中移除同 ID 旧数据（处理"更新的话题"）
  /// 3. 将 API 返回的话题全部插入列表顶部
  ///
  /// 返回实际被插入到顶部的 topic IDs（用于 UI 高亮）
  Future<List<int>> loadBefore(List<int> topicIds) async {
    if (topicIds.isEmpty) return [];
    final currentTopics = state.value;
    if (currentTopics == null) return [];

    try {
      final service = ref.read(equnDiscuzServiceProvider);
      final topics = await service.fetchGuideTopics(
        EqunDiscuzAdapter.guideFilterForTopicFilter(_currentFilter),
      );
      final wanted = topicIds.toSet();
      final newTopics = topics
          .where((topic) => wanted.contains(topic.tid))
          .map(EqunDiscuzAdapter.guideTopicToTopic)
          .toList();
      if (newTopics.isEmpty) return [];

      // 移除列表中已存在的同 ID 话题（刷新重复项，与网页版 removeValuesFromArray 一致）
      final newTopicIds = newTopics.map((t) => t.id).toSet();
      final remaining = currentTopics
          .where((t) => !newTopicIds.contains(t.id))
          .toList();
      // 将新话题全部插入列表顶部
      state = AsyncValue.data([...newTopics, ...remaining]);
      return newTopics.map((t) => t.id).toList();
    } catch (e) {
      debugPrint('[TopicList] loadBefore 失败: $e');
      return [];
    }
  }

  /// 加载更多
  Future<void> loadMore() async {
    await runPagedLoadMore((currentTopics, nextPage) async {
      final service = ref.read(equnDiscuzServiceProvider);
      final response = await _fetchEqunTopics(
        service,
        _currentFilter,
        nextPage,
      );

      final currentState = PaginationState(items: currentTopics);
      final paginationResult = _paginationHelper.processLoadMore(
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

  /// 手动重试加载更多
  Future<void> retryLoadMore() {
    return retryPagedLoadMore(loadMore);
  }

  /// 刷新单条话题状态（用于 MessageBus 更新）
  Future<void> refreshTopic(int topicId) async {
    final currentTopics = state.value;
    if (currentTopics == null) return;

    final existingIndex = currentTopics.indexWhere((t) => t.id == topicId);
    if (existingIndex == -1) {
      return;
    }

    try {
      final service = ref.read(equnDiscuzServiceProvider);
      final detail = await service.fetchThreadDetail(topicId);

      final updatedTopic = EqunDiscuzAdapter.guideTopicToTopic(
        EqunTopicSummary(
          tid: detail.tid,
          forumId: detail.fid,
          title: detail.title,
          author: detail.author ?? '',
          replyCount: detail.replyCount,
          viewCount: detail.viewCount,
          lastPoster: detail.posts.isNotEmpty ? detail.posts.last.author : null,
          lastPostText: detail.posts.isNotEmpty
              ? detail.posts.last.dateline
              : null,
          readPermission: detail.readPermission,
          readPermissionText:
              detail.readPermission == null || detail.readPermission == 0
              ? null
              : '阅读权限 ${detail.readPermission}',
          url: 'https://equn.com/forum/thread-${detail.tid}-1-1.html',
        ),
      );

      final newList = currentTopics.map((t) {
        return t.id == topicId ? updatedTopic : t;
      }).toList();

      state = AsyncValue.data(newList);
    } catch (e) {
      debugPrint('[TopicList] 刷新话题 $topicId 失败: $e');
    }
  }

  /// 忽略全部（新话题或未读话题）
  Future<void> dismissAll() async {
    state = AsyncValue.data(
      completePagedRefresh(
        const PagedPage<Topic>(items: <Topic>[], hasMore: false),
      ),
    );
  }

  void updateSeen(int topicId, int highestSeen) {
    final topics = state.value;
    if (topics == null) return;

    final index = topics.indexWhere((t) => t.id == topicId);
    if (index == -1) return;

    final topic = topics[index];
    final currentRead = topic.lastReadPostNumber ?? 0;

    if (highestSeen <= currentRead) return;

    final newUnread = (topic.highestPostNumber - highestSeen).clamp(
      0,
      topic.highestPostNumber,
    );

    final updated = Topic(
      id: topic.id,
      title: topic.title,
      slug: topic.slug,
      postsCount: topic.postsCount,
      replyCount: topic.replyCount,
      views: topic.views,
      likeCount: topic.likeCount,
      excerpt: topic.excerpt,
      createdAt: topic.createdAt,
      lastPostedAt: topic.lastPostedAt,
      lastPosterUsername: topic.lastPosterUsername,
      categoryId: topic.categoryId,
      pinned: topic.pinned,
      visible: topic.visible,
      closed: topic.closed,
      archived: topic.archived,
      tags: topic.tags,
      posters: topic.posters,
      unseen: false,
      unread: newUnread,
      newPosts: 0,
      lastReadPostNumber: highestSeen,
      highestPostNumber: topic.highestPostNumber,
    );

    final newList = [...topics];
    newList[index] = updated;
    state = AsyncValue.data(newList);

    // 同步更新追踪状态计数（阅读后减少 new/unread 计数）
    ref
        .read(topicTrackingStateProvider.notifier)
        .updateTopicRead(topicId, highestSeen, topic.highestPostNumber);
  }
}

final topicListProvider =
    AsyncNotifierProvider.family<TopicListNotifier, List<Topic>, int?>(
      TopicListNotifier.new,
    );
