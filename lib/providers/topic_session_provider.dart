import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 话题会话状态（仅在当前会话有效）
/// 用于记录本次阅读过程中哪些帖子被标记为已读（通过 Timings 上报）
class TopicSessionState {
  /// 本次会话中已读的帖子编号集合
  final Set<int> readPostNumbers;

  /// 话题标题（用于基于话题的私信预填标题等）
  final String? topicTitle;

  const TopicSessionState({
    this.readPostNumbers = const {},
    this.topicTitle,
  });

  TopicSessionState copyWith({
    Set<int>? readPostNumbers,
    String? topicTitle,
  }) {
    return TopicSessionState(
      readPostNumbers: readPostNumbers ?? this.readPostNumbers,
      topicTitle: topicTitle ?? this.topicTitle,
    );
  }
}

class TopicSessionNotifier extends Notifier<TopicSessionState> {
  final int topicId;

  TopicSessionNotifier(this.topicId);

  @override
  TopicSessionState build() {
    return const TopicSessionState();
  }

  /// 标记帖子为已读（添加到已读集合）
  void markAsRead(Set<int> postNumbers) {
    if (postNumbers.isEmpty) return;

    final newRead = {...state.readPostNumbers, ...postNumbers};
    if (newRead.length != state.readPostNumbers.length) {
      state = state.copyWith(readPostNumbers: newRead);
    }
  }

  /// 记录话题标题（详情加载后调用）
  void setTopicTitle(String? title) {
    if (title == null || title.isEmpty || state.topicTitle == title) return;
    state = state.copyWith(topicTitle: title);
  }
}

/// 话题会话状态 Provider
/// family 参数为 topicId
final topicSessionProvider = NotifierProvider.family<TopicSessionNotifier, TopicSessionState, int>(
  TopicSessionNotifier.new,
);
