// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/s.dart';
import '../theme_provider.dart';

/// 话题排序字段
enum TopicSortOrder {
  /// 默认（不传 order 参数，由 API 决定）
  defaultOrder,
  /// 活跃度（bumped_at）
  activity,
  /// 创建时间
  created,
  /// 点赞数
  likes,
  /// 浏览量
  views,
  /// 回复数
  posts,
  /// 参与者数
  posters,
}

const List<TopicSortOrder> homeTopicSortOptions = [
  TopicSortOrder.created,
  TopicSortOrder.posts,
  TopicSortOrder.views,
];

extension TopicSortOrderX on TopicSortOrder {
  /// 返回 API order 参数值，defaultOrder 返回 null
  String? get apiValue {
    switch (this) {
      case TopicSortOrder.defaultOrder:
        return null;
      case TopicSortOrder.activity:
        return 'activity';
      case TopicSortOrder.created:
        return 'created';
      case TopicSortOrder.likes:
        return 'likes';
      case TopicSortOrder.views:
        return 'views';
      case TopicSortOrder.posts:
        return 'posts';
      case TopicSortOrder.posters:
        return 'posters';
    }
  }

  /// 显示名称
  String get label {
    switch (this) {
      case TopicSortOrder.defaultOrder:
        return S.current.topicSort_default;
      case TopicSortOrder.activity:
        return S.current.topicSort_activity;
      case TopicSortOrder.created:
        return S.current.topicSort_created;
      case TopicSortOrder.likes:
        return S.current.topicSort_likes;
      case TopicSortOrder.views:
        return S.current.topicSort_views;
      case TopicSortOrder.posts:
        return S.current.topicSort_posts;
      case TopicSortOrder.posters:
        return S.current.topicSort_posters;
    }
  }
}

/// 排序字段持久化 Notifier
class TopicSortOrderNotifier extends StateNotifier<TopicSortOrder> {
  static const String _key = 'topic_sort_order';
  final SharedPreferences _prefs;

  TopicSortOrderNotifier(this._prefs)
      : super(_fromName(_prefs.getString(_key)));

  static TopicSortOrder _fromName(String? name) {
    for (final order in TopicSortOrder.values) {
      if (order.name == name) return order;
    }
    return TopicSortOrder.defaultOrder;
  }

  void setOrder(TopicSortOrder order) {
    state = order;
    _prefs.setString(_key, order.name);
  }
}

/// 当前排序字段（持久化到 SharedPreferences）
final topicSortOrderProvider =
    StateNotifierProvider<TopicSortOrderNotifier, TopicSortOrder>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return TopicSortOrderNotifier(prefs);
});

/// 升降序持久化 Notifier
class TopicSortAscendingNotifier extends StateNotifier<bool> {
  static const String _key = 'topic_sort_ascending';
  final SharedPreferences _prefs;

  TopicSortAscendingNotifier(this._prefs)
      : super(_prefs.getBool(_key) ?? false);

  void setAscending(bool ascending) {
    state = ascending;
    _prefs.setBool(_key, ascending);
  }

  void toggle() {
    setAscending(!state);
  }
}

/// 排序方向（持久化到 SharedPreferences，默认 false 即降序）
final topicSortAscendingProvider =
    StateNotifierProvider<TopicSortAscendingNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return TopicSortAscendingNotifier(prefs);
});
