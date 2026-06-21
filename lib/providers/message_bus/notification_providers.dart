import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/s.dart';
import '../../services/message_bus_service.dart';
import '../../services/local_notification_service.dart';
import '../../models/notification.dart';
import '../discourse_providers.dart';
import 'models.dart';
import 'message_bus_service_provider.dart';
import 'topic_tracking_providers.dart';

/// 通知计数 Notifier
/// 优先使用 MessageBus 推送的计数，初始值从 currentUser 获取
class NotificationCountNotifier extends Notifier<NotificationCountState> {
  static NotificationCountState? _lastState;
  static bool _hasLiveUpdate = false;

  @override
  NotificationCountState build() {
    final user = ref.watch(currentUserProvider).value;
    if (user == null) {
      _hasLiveUpdate = false;
      _lastState = null;
      return const NotificationCountState();
    }
    final initial = NotificationCountState(
      allUnread: user.allUnreadNotificationsCount,
      unread: user.unreadNotifications,
      highPriority: user.unreadHighPriorityNotifications,
    );
    if (_hasLiveUpdate && _lastState != null) {
      return _lastState!;
    }
    _lastState = initial;
    return initial;
  }

  void update({int? allUnread, int? unread, int? highPriority}) {
    state = state.copyWith(
      allUnread: allUnread,
      unread: unread,
      highPriority: highPriority,
    );
    _hasLiveUpdate = true;
    _lastState = state;
  }
  
  /// 标记所有已读后重置计数
  void markAllRead() {
    state = const NotificationCountState();
    _hasLiveUpdate = true;
    _lastState = state;
  }
}

final notificationCountStateProvider =
    NotifierProvider<NotificationCountNotifier, NotificationCountState>(() {
  return NotificationCountNotifier();
});

/// 通知频道监听器
/// 当收到通知消息时更新计数。Equn 适配不再保留 Discourse 通知列表 UI。
class NotificationChannelNotifier extends Notifier<void> {
  String? _subscribedChannel;
  MessageBusCallback? _callback;

  @override
  void build() {
    // 确保 MessageBus 已 configure（域名配置），避免用主站域名轮询
    ref.watch(messageBusInitProvider);
    final messageBus = ref.watch(messageBusServiceProvider);
    final currentUser = ref.watch(currentUserProvider).value;
    
    // 清理之前的订阅
    if (_subscribedChannel != null && _callback != null) {
      debugPrint('[NotificationChannel] 清理旧订阅: $_subscribedChannel');
      messageBus.unsubscribe(_subscribedChannel!, _callback);
      _subscribedChannel = null;
      _callback = null;
    }
    
    if (currentUser == null) {
      debugPrint('[NotificationChannel] 用户未登录，跳过订阅');
      return;
    }
    
    final channel = '/notification/${currentUser.id}';
    final initialMessageId = currentUser.notificationChannelPosition;
    
    debugPrint('[NotificationChannel] 订阅频道: $channel, 初始 messageId: $initialMessageId');
    
    void onMessage(MessageBusMessage message) {
      final data = message.data;
      if (data is Map<String, dynamic>) {
        final allUnreadCount = data['all_unread_notifications_count'] as int?;
        final unreadCount = data['unread_notifications'] as int?;
        final unreadHighPriority = data['unread_high_priority_notifications'] as int?;

        debugPrint('[Notification] 计数更新: allUnread=$allUnreadCount, unread=$unreadCount, highPriority=$unreadHighPriority');

        // 更新通知计数
        if (allUnreadCount != null || unreadCount != null || unreadHighPriority != null) {
          ref.read(notificationCountStateProvider.notifier).update(
            allUnread: allUnreadCount,
            unread: unreadCount,
            highPriority: unreadHighPriority,
          );
        }

      }
    }
    
    _subscribedChannel = channel;
    _callback = onMessage;
    
    messageBus.subscribeWithMessageId(channel, onMessage, initialMessageId);
    
    ref.onDispose(() {
      if (_subscribedChannel != null && _callback != null) {
        debugPrint('[NotificationChannel] 取消订阅频道: $_subscribedChannel');
        messageBus.unsubscribe(_subscribedChannel!, _callback);
      }
    });
  }
}

final notificationChannelProvider = NotifierProvider<NotificationChannelNotifier, void>(
  NotificationChannelNotifier.new,
);

/// 通知提醒频道监听器（复刻 Discourse 官方实现）
/// 订阅 /notification-alert/{userId} 频道，用于触发系统通知
class NotificationAlertChannelNotifier extends Notifier<void> {
  String? _subscribedChannel;
  MessageBusCallback? _callback;

  @override
  void build() {
    // 确保 MessageBus 已 configure（域名配置），避免用主站域名轮询
    ref.watch(messageBusInitProvider);
    final messageBus = ref.watch(messageBusServiceProvider);
    final currentUser = ref.watch(currentUserProvider).value;
    
    // 清理之前的订阅
    if (_subscribedChannel != null && _callback != null) {
      debugPrint('[NotificationAlert] 清理旧订阅: $_subscribedChannel');
      messageBus.unsubscribe(_subscribedChannel!, _callback);
      _subscribedChannel = null;
      _callback = null;
    }
    
    if (currentUser == null) {
      debugPrint('[NotificationAlert] 用户未登录，跳过订阅');
      return;
    }
    
    // Discourse 官方使用 /notification-alert/{userId} 频道触发桌面通知
    final channel = '/notification-alert/${currentUser.id}';
    
    debugPrint('[NotificationAlert] 订阅频道: $channel');
    
    void onAlert(MessageBusMessage message) {
      final data = message.data;
      debugPrint('[NotificationAlert] 收到提醒: $data');
      
      if (data is Map<String, dynamic>) {
        // Discourse payload 格式:
        // {
        //   notification_type: int,
        //   post_number: int,
        //   topic_title: String,
        //   topic_id: int,
        //   excerpt: String,
        //   username: String,
        //   post_url: String,
        // }
        final topicTitle = data['topic_title'] as String? ?? '';
        final topicId = data['topic_id'] as int?;
        final postNumber = data['post_number'] as int?;
        final excerpt = data['excerpt'] as String? ?? '';
        final username = data['username'] as String? ?? '';
        final notificationType = data['notification_type'] as int?;

        // 构建通知标题（参考 desktop-notifications.js 的 i18nKey 逻辑）
        String title = topicTitle;
        if (title.isEmpty) {
          title = _getNotificationTypeLabel(notificationType);
        }

        // 构建通知内容
        String body = excerpt;
        if (body.isEmpty && username.isNotEmpty) {
          body = username;
        }

        debugPrint('[NotificationAlert] 发送系统通知: title=$title, body=$body, topicId=$topicId, postNumber=$postNumber');

        LocalNotificationService().show(
          title: title,
          body: body,
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          topicId: topicId,
          postNumber: postNumber,
        );
      }
    }
    
    _subscribedChannel = channel;
    _callback = onAlert;
    
    messageBus.subscribe(channel, onAlert);
    
    ref.onDispose(() {
      if (_subscribedChannel != null && _callback != null) {
        debugPrint('[NotificationAlert] 取消订阅频道: $_subscribedChannel');
        messageBus.unsubscribe(_subscribedChannel!, _callback);
      }
    });
  }
  
  /// 获取通知类型标签
  String _getNotificationTypeLabel(int? type) {
    if (type == null) return S.current.notification_newNotification;
    final notificationType = NotificationType.fromId(type);
    return notificationType.label;
  }
}

final notificationAlertChannelProvider = NotifierProvider<NotificationAlertChannelNotifier, void>(
  NotificationAlertChannelNotifier.new,
);
