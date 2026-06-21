import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/web_history_item.dart';
import 'theme_provider.dart'; // sharedPreferencesProvider

/// 浏览历史最大条数
const int maxWebHistoryItems = 200;

/// 内置浏览器浏览历史状态管理
class WebHistoryNotifier extends StateNotifier<List<WebHistoryItem>> {
  static const String _storageKey = 'web_history_items';

  final SharedPreferences _prefs;

  WebHistoryNotifier(this._prefs) : super(_load(_prefs));

  static List<WebHistoryItem> _load(SharedPreferences prefs) {
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((e) => WebHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 记录一条浏览历史
  /// 同 URL 去重：更新标题和时间，移到头部
  void record(String url, String title) {
    if (url.isEmpty) return;
    // 过滤掉 about:blank 等无意义页面
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;

    final now = DateTime.now();
    final list = state.where((e) => e.url != url).toList();
    list.insert(
      0,
      WebHistoryItem(url: url, title: title, visitedAt: now),
    );
    // 超出上限则截断
    if (list.length > maxWebHistoryItems) {
      state = list.sublist(0, maxWebHistoryItems);
    } else {
      state = list;
    }
    _save();
  }

  /// 删除单条历史
  void removeByUrl(String url) {
    state = state.where((e) => e.url != url).toList();
    _save();
  }

  /// 清空全部历史
  void clearAll() {
    state = [];
    _save();
  }

  void _save() {
    final jsonStr = jsonEncode(state.map((e) => e.toJson()).toList());
    _prefs.setString(_storageKey, jsonStr);
  }
}

final webHistoryProvider =
    StateNotifierProvider<WebHistoryNotifier, List<WebHistoryItem>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return WebHistoryNotifier(prefs);
});
