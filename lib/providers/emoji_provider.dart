import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/emoji.dart';
import 'core_providers.dart';

/// 表情列表 Provider (缓存)
final emojiGroupsProvider = FutureProvider<Map<String, List<Emoji>>>((ref) async {
  final service = ref.watch(discourseServiceProvider);
  return service.getEmojis();
});
