import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/message_bus_service.dart';
import '../../services/discourse/discourse_service.dart';
import '../../utils/time_utils.dart';
import '../discourse_providers.dart';
import 'message_bus_service_provider.dart';
import 'models.dart';
import 'topic_tracking_providers.dart';


/// 话题频道监听器
/// 监听新回复和正在输入的用户
class TopicChannelNotifier extends Notifier<TopicChannelState> {
  TopicChannelNotifier(this.topicId);
  final int topicId;
  
  @override
  TopicChannelState build() {
    // 确保 MessageBus 已 configure（域名配置），避免用主站域名轮询
    ref.watch(messageBusInitProvider);
    final messageBus = ref.watch(messageBusServiceProvider);
    final service = ref.watch(discourseServiceProvider);
    final topicChannel = '/topic/$topicId';
    final reactionsChannel = '/topic/$topicId/reactions';
    final presenceChannel = '/presence/discourse-presence/reply/$topicId';
    
    void onTopicMessage(MessageBusMessage message) {
      final data = message.data;
      if (data is! Map<String, dynamic>) return;

      // 1. reload_topic 消息（话题状态变更：关闭/打开/固定等）
      final reloadTopic = data['reload_topic'] as bool? ?? false;
      if (reloadTopic) {
        final refreshStream = data['refresh_stream'] as bool? ?? false;
        debugPrint('[TopicChannel] reload_topic, refreshStream=$refreshStream');
        state = state.copyWith(reloadRequested: true, refreshStreamRequested: refreshStream);
        return;
      }

      // 2. notification_level_change（通知级别变更）
      final notifLevel = data['notification_level_change'] as int?;
      if (notifLevel != null) {
        debugPrint('[TopicChannel] notification_level_change: $notifLevel');
        state = state.copyWith(notificationLevelChange: notifLevel);
        return;
      }

      final type = data['type'] as String?;
      final postId = data['id'] as int?;
      final updatedAtStr = data['updated_at'] as String?;
      final updatedAt = TimeUtils.parseUtcTime(updatedAtStr) ?? DateTime.now();

      debugPrint('[TopicChannel] 收到消息: type=$type, postId=$postId');

      switch (type) {
        case 'created':
          state = state.copyWith(hasNewReplies: true);
          if (postId != null) {
            final createdUserId = data['user_id'] as int?;
            _addPostUpdate(postId, TopicMessageType.created, updatedAt, userId: createdUserId);
          }
          break;

        case 'revised':
        case 'rebaked':
          if (postId != null) {
            final msgType = type == 'revised'
                ? TopicMessageType.revised
                : TopicMessageType.rebaked;
            _addPostUpdate(postId, msgType, updatedAt);
          }
          break;

        case 'deleted':
          if (postId != null) {
            _addPostUpdate(postId, TopicMessageType.deleted, updatedAt);
          }
          break;

        case 'destroyed':
          if (postId != null) {
            _addPostUpdate(postId, TopicMessageType.destroyed, updatedAt);
          }
          break;

        case 'recovered':
          if (postId != null) {
            _addPostUpdate(postId, TopicMessageType.recovered, updatedAt);
          }
          break;

        case 'acted':
          if (postId != null) {
            _addPostUpdate(postId, TopicMessageType.acted, updatedAt);
          }
          break;

        case 'liked':
        case 'unliked':
          if (postId != null) {
            final likesCount = data['likes_count'] as int?;
            final userId = data['user_id'] as int?;
            final msgType = type == 'liked'
                ? TopicMessageType.liked
                : TopicMessageType.unliked;
            _addPostUpdate(
              postId,
              msgType,
              updatedAt,
              likesCount: likesCount,
              userId: userId,
            );
          }
          break;

        case 'read':
          if (postId != null) {
            final readersCount = data['readers_count'] as int?;
            _addPostUpdate(
              postId,
              TopicMessageType.read,
              updatedAt,
              readersCount: readersCount,
            );
          }
          break;

        case 'stats':
          final postsCount = data['posts_count'] as int?;
          final likeCount = data['like_count'] as int?;
          final lastPostedAtStr = data['last_posted_at'] as String?;
          final lastPostedAt = TimeUtils.parseUtcTime(lastPostedAtStr);

          state = state.copyWith(
            statsUpdate: TopicStatsUpdate(
              postsCount: postsCount,
              likeCount: likeCount,
              lastPostedAt: lastPostedAt,
            ),
          );
          break;

        case 'move_to_inbox':
          state = state.copyWith(messageArchived: false);
          break;

        case 'archived':
          state = state.copyWith(messageArchived: true);
          break;

        case 'remove_allowed_user':
          debugPrint('[TopicChannel] 用户被移出私信');
          break;

        case 'boost_added':
          if (postId != null) {
            final boostData = data['boost'] as Map<String, dynamic>?;
            _addBoostUpdate(postId, TopicMessageType.boostAdded, boostData: boostData);
          }
          break;

        case 'boost_removed':
          if (postId != null) {
            final boostId = data['boost_id'] as int?;
            _addBoostUpdate(postId, TopicMessageType.boostRemoved, boostId: boostId);
          }
          break;

        case 'policy_change':
          // discourse-policy 插件：接受/撤销状态变更。
          // 服务端 publish 时 post.updated_at 不会改（policy 不改帖子内容），
          // 所以不传 updatedAt，避免下游 refreshPost 因 updated_at 未变 short-circuit。
          if (postId != null) {
            _addPostUpdate(postId, TopicMessageType.policyChanged, DateTime.now());
          }
          break;

        case 'shared_issue':
          // discourse-solved 的 "俺也一样" 推送。
          // 注意: 服务端广播的 user_created_shared_issue 是 *操作用户* 的最新状态,
          // 对所有订阅者一视同仁,因此接收端不能用它覆写本地 userCreated 状态,
          // 只用 count 更新计数即可。本地 userCreated 状态由点击响应直接维护。
          final sharedCount = data['count'] as int?;
          if (sharedCount != null) {
            state = state.copyWith(
              sharedIssueUpdate: SharedIssueUpdate(
                count: sharedCount,
                userCreated: data['user_created_shared_issue'] as bool? ?? false,
              ),
            );
          }
          break;

        default:
          debugPrint('[TopicChannel] 未知消息类型: $type');
      }
    }
    
    void onPresenceMessage(MessageBusMessage message) {
      final data = message.data;
      debugPrint('[Presence] 收到消息: $data');
      
      if (data is! Map<String, dynamic>) return;
      
      // 获取当前用户 ID，用于过滤掉自己
      final currentUser = ref.read(currentUserProvider).value;
      final currentUserId = currentUser?.id;
      
      final currentUsers = List<TypingUser>.from(state.typingUsers);
      bool changed = false;
      
      final enteringUsersList = data['entering_users'] as List<dynamic>?;
      if (enteringUsersList != null) {
        for (final u in enteringUsersList) {
          final userMap = u as Map<String, dynamic>;
          final user = TypingUser(
            id: userMap['id'] as int? ?? 0,
            username: userMap['username'] as String? ?? '',
            avatarTemplate: userMap['avatar_template'] as String? ?? '',
          );
          
          // 过滤掉当前用户自己
          if (user.username.isNotEmpty && user.id > 0 && user.id != currentUserId) {
            if (!currentUsers.any((element) => element.id == user.id)) {
              currentUsers.add(user);
              changed = true;
            }
          }
        }
      }
      
      final leavingUserIds = data['leaving_user_ids'] as List<dynamic>?;
      if (leavingUserIds != null) {
        for (final id in leavingUserIds) {
          if (id is int) {
            final beforeCount = currentUsers.length;
            currentUsers.removeWhere((u) => u.id == id);
            if (currentUsers.length != beforeCount) {
              changed = true;
            }
          }
        }
      }
      
      if (changed) {
        state = state.copyWith(typingUsers: currentUsers);
      }
    }
    
    void onReactionsMessage(MessageBusMessage message) {
      final data = message.data;
      if (data is! Map<String, dynamic>) return;

      final postId = data['post_id'] as int?;
      if (postId == null) return;

      debugPrint('[TopicChannel] 收到 reactions 消息: postId=$postId');
      _addPostUpdate(postId, TopicMessageType.acted, DateTime.now());
    }

    messageBus.subscribe(topicChannel, onTopicMessage);
    messageBus.subscribe(reactionsChannel, onReactionsMessage);
    messageBus.subscribe(presenceChannel, onPresenceMessage);

    // 异步加载初始 presence 状态
    _loadInitialPresence(service, messageBus, presenceChannel, topicId, onPresenceMessage);

    ref.onDispose(() {
      messageBus.unsubscribe(topicChannel, onTopicMessage);
      messageBus.unsubscribe(reactionsChannel, onReactionsMessage);
      messageBus.unsubscribe(presenceChannel, onPresenceMessage);
    });

    return const TopicChannelState();
  }

  Future<void> _loadInitialPresence(
    DiscourseService service,
    MessageBusService messageBus,
    String presenceChannel,
    int topicId,
    void Function(MessageBusMessage) onMessage,
  ) async {
    try {
      final presence = await service.getPresence(topicId);
      debugPrint('[Presence] 初始状态: users=${presence.users.length}, messageId=${presence.messageId}');

      // 过滤掉当前用户
      final currentUser = ref.read(currentUserProvider).value;
      final currentUserId = currentUser?.id;
      final filteredUsers = presence.users.where((u) => u.id != currentUserId).toList();

      state = state.copyWith(typingUsers: filteredUsers);

      // 更新订阅的 messageId，避免重复接收旧消息
      messageBus.unsubscribe(presenceChannel, onMessage);
      messageBus.subscribeWithMessageId(presenceChannel, onMessage, presence.messageId);
    } catch (e) {
      debugPrint('[Presence] 初始化失败: $e');
      // 订阅已经在 build() 中完成，这里不需要再次订阅
    }
  }
  
  void clearNewReplies() {
    state = state.copyWith(hasNewReplies: false);
  }

  void clearReloadRequest() {
    state = state.copyWith(reloadRequested: false, refreshStreamRequested: false);
  }

  void clearNotificationLevelChange() {
    state = state.copyWith(clearNotificationLevelChange: true);
  }

  void _addPostUpdate(
    int postId,
    TopicMessageType type,
    DateTime updatedAt, {
    int? likesCount,
    int? readersCount,
    int? userId,
  }) {
    // 去重：如果最近 2 秒内已有相同 postId + type 的更新，跳过
    final updates = List<PostUpdate>.from(state.postUpdates);
    if (updates.isNotEmpty) {
      final last = updates.last;
      if (last.postId == postId && last.type == type &&
          updatedAt.difference(last.updatedAt).inSeconds.abs() < 2) {
        return;
      }
    }

    final update = PostUpdate(
      postId: postId,
      type: type,
      updatedAt: updatedAt,
      likesCount: likesCount,
      readersCount: readersCount,
      userId: userId,
    );

    updates.add(update);
    if (updates.length > 50) {
      updates.removeAt(0);
    }

    state = state.copyWith(postUpdates: updates);
  }
  
  void _addBoostUpdate(
    int postId,
    TopicMessageType type, {
    Map<String, dynamic>? boostData,
    int? boostId,
  }) {
    final updates = List<PostUpdate>.from(state.postUpdates);
    final update = PostUpdate(
      postId: postId,
      type: type,
      updatedAt: DateTime.now(),
      boostData: boostData,
      boostId: boostId,
    );
    updates.add(update);
    if (updates.length > 50) {
      updates.removeAt(0);
    }
    state = state.copyWith(postUpdates: updates);
  }

  void clearPostUpdates() {
    state = state.copyWith(postUpdates: []);
  }
  
  void clearStatsUpdate() {
    state = state.copyWith(clearStatsUpdate: true);
  }

  void clearSharedIssueUpdate() {
    state = state.copyWith(clearSharedIssueUpdate: true);
  }
  
  void clearTypingUsers() {
    state = state.copyWith(typingUsers: []);
  }
}

final topicChannelProvider = NotifierProvider.family.autoDispose<TopicChannelNotifier, TopicChannelState, int>(
  TopicChannelNotifier.new,
);
