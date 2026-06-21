import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/web_bookmark.dart';
import 'theme_provider.dart'; // sharedPreferencesProvider

/// 网页收藏状态管理
class WebBookmarkNotifier extends StateNotifier<List<WebBookmark>> {
  static const String _storageKey = 'web_bookmarks';

  final SharedPreferences _prefs;

  WebBookmarkNotifier(this._prefs) : super(_load(_prefs));

  /// 从 SharedPreferences 加载列表
  static List<WebBookmark> _load(SharedPreferences prefs) {
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((e) => WebBookmark.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 添加网页收藏
  void add(WebBookmark item) {
    // 去重：已存在则移到头部
    final list = state.where((e) => e.url != item.url).toList();
    list.insert(0, item);
    state = list;
    _save();
  }

  /// 通过 URL 移除收藏
  void removeByUrl(String url) {
    state = state.where((e) => e.url != url).toList();
    _save();
  }

  /// 检查 URL 是否已收藏
  bool isBookmarked(String url) {
    return state.any((e) => e.url == url);
  }

  /// 切换收藏状态，返回操作后是否为已收藏
  bool toggle(String url, String title) {
    if (isBookmarked(url)) {
      removeByUrl(url);
      return false;
    } else {
      add(WebBookmark(url: url, title: title, createdAt: DateTime.now()));
      return true;
    }
  }

  /// 持久化到 SharedPreferences
  void _save() {
    final jsonStr = jsonEncode(state.map((e) => e.toJson()).toList());
    _prefs.setString(_storageKey, jsonStr);
  }
}

final webBookmarkProvider =
    StateNotifierProvider<WebBookmarkNotifier, List<WebBookmark>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return WebBookmarkNotifier(prefs);
});
