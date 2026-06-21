import 'package:flutter/material.dart';

import '../../../l10n/s.dart';
import '../../../providers/preferences_provider.dart';

/// 进度悬浮条手势动作的元数据（图标 + 本地化标签）
/// 半圆菜单、设置 picker、subtitle 等多处共用
({IconData icon, String label}) progressGestureActionMeta(
  BuildContext context,
  ProgressGestureAction action,
) {
  final l = context.l10n;
  switch (action) {
    case ProgressGestureAction.none:
      return (
        icon: Icons.do_not_disturb_alt_outlined,
        label: l.progressGesture_action_none,
      );
    case ProgressGestureAction.openTimeline:
      return (
        icon: Icons.unfold_more_rounded,
        label: l.progressGesture_action_openTimeline,
      );
    case ProgressGestureAction.scrollToTop:
      return (
        icon: Icons.vertical_align_top_rounded,
        label: l.progressGesture_action_scrollToTop,
      );
    case ProgressGestureAction.jumpToUnread:
      return (
        icon: Icons.mark_chat_unread_outlined,
        label: l.progressGesture_action_jumpToUnread,
      );
    case ProgressGestureAction.nextPost:
      return (
        icon: Icons.south_rounded,
        label: l.progressGesture_action_nextPost,
      );
    case ProgressGestureAction.previousPost:
      return (
        icon: Icons.north_rounded,
        label: l.progressGesture_action_previousPost,
      );
    case ProgressGestureAction.reply:
      return (icon: Icons.reply_rounded, label: l.progressGesture_action_reply);
    case ProgressGestureAction.share:
      return (icon: Icons.link_rounded, label: l.progressGesture_action_share);
    case ProgressGestureAction.shareImage:
      return (
        icon: Icons.image_outlined,
        label: l.progressGesture_action_shareImage,
      );
    case ProgressGestureAction.exportArticle:
      return (
        icon: Icons.download_outlined,
        label: l.progressGesture_action_exportArticle,
      );
    case ProgressGestureAction.openInBrowser:
      return (
        icon: Icons.language_rounded,
        label: l.progressGesture_action_openInBrowser,
      );
    case ProgressGestureAction.bookmark:
      return (
        icon: Icons.bookmark_border_rounded,
        label: l.progressGesture_action_bookmark,
      );
    case ProgressGestureAction.readLater:
      return (
        icon: Icons.layers_outlined,
        label: l.progressGesture_action_readLater,
      );
    case ProgressGestureAction.notification:
      return (
        icon: Icons.notifications_none_rounded,
        label: l.progressGesture_action_notification,
      );
    case ProgressGestureAction.filter:
      return (
        icon: Icons.filter_list_rounded,
        label: l.progressGesture_action_filter,
      );
    case ProgressGestureAction.toggleNestedView:
      return (
        icon: Icons.account_tree_outlined,
        label: l.progressGesture_action_toggleNestedView,
      );
    case ProgressGestureAction.readingSettings:
      return (
        icon: Icons.auto_stories_rounded,
        label: l.progressGesture_action_readingSettings,
      );
    case ProgressGestureAction.search:
      return (
        icon: Icons.search_rounded,
        label: l.progressGesture_action_search,
      );
    case ProgressGestureAction.refresh:
      return (
        icon: Icons.refresh_rounded,
        label: l.progressGesture_action_refresh,
      );
  }
}
