// 通用分页加载工具
//
// 提供统一的分页逻辑处理，包括：
// - 多种 hasMore 判断策略
// - 自动去重
// - 加载状态管理

/// 分页结果包装
class PaginationResult<T> {
  final List<T> items;

  /// 更多数据的 URL（用于 Discourse topic list 等 API）
  final String? moreUrl;

  /// 总数据量（用于 notifications 等 API）
  final int? totalRows;

  /// 每页预期数量（用于基于数量判断的 API）
  final int? expectedPageSize;

  const PaginationResult({
    required this.items,
    this.moreUrl,
    this.totalRows,
    this.expectedPageSize,
  });
}

/// hasMore 判断上下文
class HasMoreContext<T> {
  /// API 返回的原始数据
  final List<T> responseItems;

  /// 去重后的新数据（仅在 loadMore 时有意义）
  final List<T> newItems;

  /// 合并后的总数据量
  final int totalCount;

  /// 是否是刷新操作
  final bool isRefresh;

  /// 原始分页结果
  final PaginationResult<T> result;

  const HasMoreContext({
    required this.responseItems,
    required this.newItems,
    required this.totalCount,
    required this.isRefresh,
    required this.result,
  });
}

/// 自定义 hasMore 判断函数类型
typedef HasMoreChecker<T> = bool Function(HasMoreContext<T> context);

/// hasMore 判断策略
enum HasMoreStrategy {
  /// 基于 moreUrl 是否为 null
  byMoreUrl,

  /// 基于当前数量是否小于 totalRows
  byTotalRows,

  /// 基于返回数量是否达到预期 + 去重后是否有新数据
  byCountAndNewItems,

  /// 使用自定义判断函数
  custom,
}

/// 分页状态
class PaginationState<T> {
  final List<T> items;
  final bool hasMore;
  final int currentOffset;

  const PaginationState({
    this.items = const [],
    this.hasMore = true,
    this.currentOffset = 0,
  });

  PaginationState<T> copyWith({
    List<T>? items,
    bool? hasMore,
    int? currentOffset,
  }) {
    return PaginationState(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      currentOffset: currentOffset ?? this.currentOffset,
    );
  }
}

/// 通用分页处理器
class PaginationHelper<T> {
  /// 用于去重的 key 提取器
  final Object Function(T item) keyExtractor;

  /// hasMore 判断策略
  final HasMoreStrategy strategy;

  /// 每页预期数量（用于 byCountAndNewItems 策略）
  final int expectedPageSize;

  /// 自定义 hasMore 判断函数（用于 custom 策略）
  final HasMoreChecker<T>? hasMoreChecker;

  const PaginationHelper({
    required this.keyExtractor,
    this.strategy = HasMoreStrategy.byMoreUrl,
    this.expectedPageSize = 30,
    this.hasMoreChecker,
  });

  /// 处理初始加载或刷新的结果
  PaginationState<T> processRefresh(PaginationResult<T> result) {
    final context = HasMoreContext(
      responseItems: result.items,
      newItems: result.items,
      totalCount: result.items.length,
      isRefresh: true,
      result: result,
    );

    return PaginationState(
      items: result.items,
      hasMore: _checkHasMore(context),
      currentOffset: result.items.length,
    );
  }

  /// 处理加载更多的结果
  PaginationState<T> processLoadMore(
    PaginationState<T> currentState,
    PaginationResult<T> result,
  ) {
    final currentItems = currentState.items;

    // 去重
    final existingKeys = currentItems.map(keyExtractor).toSet();
    final newItems = result.items
        .where((item) => !existingKeys.contains(keyExtractor(item)))
        .toList();

    final mergedItems = [...currentItems, ...newItems];

    final context = HasMoreContext(
      responseItems: result.items,
      newItems: newItems,
      totalCount: mergedItems.length,
      isRefresh: false,
      result: result,
    );

    return PaginationState(
      items: mergedItems,
      hasMore: _checkHasMore(context),
      currentOffset: mergedItems.length,
    );
  }

  /// 根据策略判断是否还有更多数据
  bool _checkHasMore(HasMoreContext<T> context) {
    switch (strategy) {
      case HasMoreStrategy.byMoreUrl:
        return context.result.moreUrl != null &&
            context.responseItems.isNotEmpty;

      case HasMoreStrategy.byTotalRows:
        return context.totalCount < (context.result.totalRows ?? 0);

      case HasMoreStrategy.byCountAndNewItems:
        final pageSize = context.result.expectedPageSize ?? expectedPageSize;
        if (context.isRefresh) {
          // 刷新时只检查返回数量
          return context.responseItems.length >= pageSize;
        }
        // 加载更多时检查返回数量 + 去重后是否有新数据
        return context.responseItems.length >= pageSize &&
            context.newItems.isNotEmpty;

      case HasMoreStrategy.custom:
        return hasMoreChecker?.call(context) ?? false;
    }
  }
}

/// 预定义的分页助手
class PaginationHelpers {
  /// Topic 分页助手（使用 moreTopicsUrl）
  static PaginationHelper<T> forTopics<T>({
    required Object Function(T item) keyExtractor,
  }) {
    return PaginationHelper<T>(
      keyExtractor: keyExtractor,
      strategy: HasMoreStrategy.byMoreUrl,
    );
  }

  /// Notification 分页助手（使用 totalRows）
  static PaginationHelper<T> forNotifications<T>({
    required Object Function(T item) keyExtractor,
  }) {
    return PaginationHelper<T>(
      keyExtractor: keyExtractor,
      strategy: HasMoreStrategy.byTotalRows,
    );
  }

  /// 通用列表分页助手（基于数量判断）
  static PaginationHelper<T> forList<T>({
    required Object Function(T item) keyExtractor,
    int expectedPageSize = 30,
  }) {
    return PaginationHelper<T>(
      keyExtractor: keyExtractor,
      strategy: HasMoreStrategy.byCountAndNewItems,
      expectedPageSize: expectedPageSize,
    );
  }

  /// 游标分页助手（支持自定义 hasMore 判断）
  static PaginationHelper<T> forCursor<T>({
    required Object Function(T item) keyExtractor,
    required HasMoreChecker<T> hasMoreChecker,
  }) {
    return PaginationHelper<T>(
      keyExtractor: keyExtractor,
      strategy: HasMoreStrategy.custom,
      hasMoreChecker: hasMoreChecker,
    );
  }
}
