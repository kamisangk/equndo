import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';
import '../pages/equn_thread_detail_page.dart';
import '../pages/user_profile_page.dart';
import '../services/local_notification_service.dart';

NavigatorState? _rootNavigator(BuildContext context) {
  return navigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
}

void _pushOnRootNavigator(BuildContext context, Widget page) {
  _rootNavigator(context)?.push(MaterialPageRoute(builder: (_) => page));
}

/// 处理通知点击：标记已读 + 按类型跳转
/// 快捷面板和历史列表页面共用
void handleNotificationTap(
  BuildContext context,
  WidgetRef _,
  DiscourseNotification notification,
) {
  // 根据通知类型决定跳转逻辑
  switch (notification.notificationType) {
    case NotificationType.inviteeAccepted:
    case NotificationType.following:
      if (notification.username != null) {
        _pushOnRootNavigator(
          context,
          UserProfilePage(username: notification.username!),
        );
      }
      break;

    case NotificationType.grantedBadge:
      break;

    case NotificationType.membershipRequestAccepted:
      break;

    case NotificationType.boost:
      if (notification.topicId != null) {
        _pushOnRootNavigator(
          context,
          EqunThreadDetailPage(
            tid: notification.topicId!,
            initialTitle: notification.data.topicTitle ?? notification.fancyTitle,
            scrollToPostNumber: notification.postNumber,
          ),
        );
      }
      break;

    default:
      if (notification.topicId != null) {
        _pushOnRootNavigator(
          context,
          EqunThreadDetailPage(
            tid: notification.topicId!,
            initialTitle: notification.data.topicTitle ?? notification.fancyTitle,
            scrollToPostNumber: notification.postNumber,
          ),
        );
      }
      break;
  }
}
