part of '../topic_detail_provider.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

/// Gaps 相关方法（拉黑用户的帖子加载）
extension GapMethods on TopicDetailNotifier {
  /// 加载某个帖子前面的 gap 帖子
  Future<void> fillGapBefore(int postId) async {
    final currentDetail = state.value;
    if (currentDetail == null) return;

    final gaps = currentDetail.postStream.gaps;
    if (gaps == null) return;

    final gapPostIds = gaps.before[postId];
    if (gapPostIds == null || gapPostIds.isEmpty) return;

    try {
      final service = ref.read(discourseServiceProvider);
      final newPostStream = await service.getPosts(arg.topicId, gapPostIds);

      if (!ref.mounted) return;
      final updatedDetail = state.value;
      if (updatedDetail == null) return;

      final currentPosts = updatedDetail.postStream.posts;
      final existingIds = currentPosts.map((p) => p.id).toSet();
      final newPosts = newPostStream.posts.where((p) => !existingIds.contains(p.id)).toList();

      if (newPosts.isEmpty) {
        // 即使没有新帖子也要移除 gap 条目
        _removeGapEntry(updatedDetail, before: postId);
        return;
      }

      // 找到目标帖子的位置，将新帖子插入到它前面
      final targetIndex = currentPosts.indexWhere((p) => p.id == postId);
      final mergedPosts = [...currentPosts];
      if (targetIndex != -1) {
        mergedPosts.insertAll(targetIndex, newPosts);
      } else {
        mergedPosts.addAll(newPosts);
      }
      mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));

      // 更新 stream
      final currentStream = updatedDetail.postStream.stream;
      final existingStreamIds = currentStream.toSet();
      final newStreamIds = newPosts.map((p) => p.id).where((id) => !existingStreamIds.contains(id)).toList();
      final mergedStream = [...currentStream, ...newStreamIds];

      // 移除已加载的 gap 条目
      final newBefore = Map<int, List<int>>.from(updatedDetail.postStream.gaps?.before ?? {});
      newBefore.remove(postId);
      final updatedGaps = PostStreamGaps(
        before: newBefore,
        after: Map<int, List<int>>.from(updatedDetail.postStream.gaps?.after ?? {}),
      );

      state = AsyncValue.data(updatedDetail.copyWith(
        postStream: PostStream(
          posts: mergedPosts,
          stream: mergedStream,
          gaps: updatedGaps.isEmpty ? null : updatedGaps,
        ),
      ));
    } catch (e) {
      debugPrint('[TopicDetail] fillGapBefore($postId) 失败: $e');
    }
  }

  /// 加载某个帖子后面的 gap 帖子
  Future<void> fillGapAfter(int postId) async {
    final currentDetail = state.value;
    if (currentDetail == null) return;

    final gaps = currentDetail.postStream.gaps;
    if (gaps == null) return;

    final gapPostIds = gaps.after[postId];
    if (gapPostIds == null || gapPostIds.isEmpty) return;

    try {
      final service = ref.read(discourseServiceProvider);
      final newPostStream = await service.getPosts(arg.topicId, gapPostIds);

      if (!ref.mounted) return;
      final updatedDetail = state.value;
      if (updatedDetail == null) return;

      final currentPosts = updatedDetail.postStream.posts;
      final existingIds = currentPosts.map((p) => p.id).toSet();
      final newPosts = newPostStream.posts.where((p) => !existingIds.contains(p.id)).toList();

      if (newPosts.isEmpty) {
        _removeGapEntry(updatedDetail, after: postId);
        return;
      }

      // 找到目标帖子的位置，将新帖子插入到它后面
      final targetIndex = currentPosts.indexWhere((p) => p.id == postId);
      final mergedPosts = [...currentPosts];
      if (targetIndex != -1) {
        mergedPosts.insertAll(targetIndex + 1, newPosts);
      } else {
        mergedPosts.addAll(newPosts);
      }
      mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));

      // 更新 stream
      final currentStream = updatedDetail.postStream.stream;
      final existingStreamIds = currentStream.toSet();
      final newStreamIds = newPosts.map((p) => p.id).where((id) => !existingStreamIds.contains(id)).toList();
      final mergedStream = [...currentStream, ...newStreamIds];

      // 移除已加载的 gap 条目
      final newAfter = Map<int, List<int>>.from(updatedDetail.postStream.gaps?.after ?? {});
      newAfter.remove(postId);
      final updatedGaps = PostStreamGaps(
        before: Map<int, List<int>>.from(updatedDetail.postStream.gaps?.before ?? {}),
        after: newAfter,
      );

      state = AsyncValue.data(updatedDetail.copyWith(
        postStream: PostStream(
          posts: mergedPosts,
          stream: mergedStream,
          gaps: updatedGaps.isEmpty ? null : updatedGaps,
        ),
      ));
    } catch (e) {
      debugPrint('[TopicDetail] fillGapAfter($postId) 失败: $e');
    }
  }

  /// 移除 gap 条目的辅助方法
  void _removeGapEntry(TopicDetail detail, {int? before, int? after}) {
    final currentGaps = detail.postStream.gaps;
    if (currentGaps == null) return;

    final newBefore = Map<int, List<int>>.from(currentGaps.before);
    final newAfter = Map<int, List<int>>.from(currentGaps.after);

    if (before != null) newBefore.remove(before);
    if (after != null) newAfter.remove(after);

    final updatedGaps = PostStreamGaps(before: newBefore, after: newAfter);

    state = AsyncValue.data(detail.copyWith(
      postStream: PostStream(
        posts: detail.postStream.posts,
        stream: detail.postStream.stream,
        gaps: updatedGaps.isEmpty ? null : updatedGaps,
      ),
    ));
  }

  /// 展开隐藏帖子的原始内容
  Future<void> expandHiddenPost(int postId) async {
    try {
      final service = ref.read(discourseServiceProvider);
      final cooked = await service.getPostCooked(postId);
      if (!ref.mounted) return;
      _updatePostById(postId, (post) => post.copyWith(
        cooked: cooked,
        cookedHidden: false,
      ));
    } catch (e) {
      debugPrint('[TopicDetail] expandHiddenPost($postId) 失败: $e');
    }
  }
}
