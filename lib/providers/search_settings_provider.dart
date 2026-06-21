// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/s.dart';
import 'theme_provider.dart';

/// 搜索排序方式
enum SearchSortOrder {
  relevance(null),
  latest('latest'),
  likes('likes'),
  views('views'),
  latestTopic('latest_topic');

  final String? value;
  const SearchSortOrder(this.value);

  String get label {
    switch (this) {
      case SearchSortOrder.relevance:
        return S.current.search_sortRelevance;
      case SearchSortOrder.latest:
        return S.current.search_sortLatest;
      case SearchSortOrder.likes:
        return S.current.search_sortLikes;
      case SearchSortOrder.views:
        return S.current.search_sortViews;
      case SearchSortOrder.latestTopic:
        return S.current.search_sortLatestTopic;
    }
  }
}

/// 搜索设置数据类
class SearchSettings {
  final SearchSortOrder sortOrder;

  const SearchSettings({required this.sortOrder});

  SearchSettings copyWith({SearchSortOrder? sortOrder}) =>
      SearchSettings(sortOrder: sortOrder ?? this.sortOrder);
}

/// 搜索设置 StateNotifier，管理状态和持久化
class SearchSettingsNotifier extends StateNotifier<SearchSettings> {
  static const String _sortOrderKey = 'search_sort_order';

  SearchSettingsNotifier(this._prefs) : super(_loadFromPrefs(_prefs));

  final SharedPreferences _prefs;

  static SearchSettings _loadFromPrefs(SharedPreferences prefs) {
    final sortOrderValue = prefs.getString(_sortOrderKey);
    final sortOrder = SearchSortOrder.values.firstWhere(
      (e) => e.value == sortOrderValue,
      orElse: () => SearchSortOrder.relevance,
    );
    return SearchSettings(sortOrder: sortOrder);
  }

  Future<void> setSortOrder(SearchSortOrder order) async {
    state = state.copyWith(sortOrder: order);
    if (order.value == null) {
      await _prefs.remove(_sortOrderKey);
    } else {
      await _prefs.setString(_sortOrderKey, order.value!);
    }
  }
}

/// 搜索设置 Provider
final searchSettingsProvider =
    StateNotifierProvider<SearchSettingsNotifier, SearchSettings>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return SearchSettingsNotifier(prefs);
    });
