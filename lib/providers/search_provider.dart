import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/search_result.dart';
import 'core_providers.dart';

/// 搜索结果 Provider
/// 使用 autoDispose 在页面销毁时自动清理
/// family 参数为搜索关键词
final searchResultProvider = FutureProvider.autoDispose
    .family<SearchResult?, String>((ref, query) async {
  if (query.trim().isEmpty) return null;
  final service = ref.read(discourseServiceProvider);
  return service.search(query: query);
});
