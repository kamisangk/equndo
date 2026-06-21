import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../l10n/s.dart';
import '../../../../models/topic.dart';
import '../../../../services/discourse_cache_manager.dart';
import '../../../../services/emoji_handler.dart';
import '../../../../utils/platform_utils.dart';

/// 获取 emoji 图片 URL（未加载完成时返回空字符串，由 errorBuilder 处理）
String _getEmojiUrl(String emojiName) {
  return EmojiHandler().getEmojiUrl(emojiName);
}

/// 帖子底部操作栏
class PostActionBar extends StatefulWidget {
  final Post post;
  final bool isGuest;
  final bool isOwnPost;
  final bool isLiking;
  final List<PostReaction> reactions;
  final PostReaction? currentUserReaction;
  final GlobalKey likeButtonKey;
  final List<Post> replies;
  final ValueNotifier<bool> isLoadingRepliesNotifier;
  final ValueNotifier<bool> showRepliesNotifier;
  final VoidCallback onToggleLike;
  final VoidCallback onShowReactionPicker;
  final void Function(String? reactionId) onShowReactionUsers;
  final VoidCallback? onReply;
  final VoidCallback onShowMoreMenu;
  final VoidCallback onToggleReplies;
  final bool hideRepliesButton;
  final VoidCallback? onAddBoost;
  final bool canBoost;
  final bool hasBoosts;

  const PostActionBar({
    super.key,
    required this.post,
    required this.isGuest,
    required this.isOwnPost,
    required this.isLiking,
    required this.reactions,
    required this.currentUserReaction,
    required this.likeButtonKey,
    required this.replies,
    required this.isLoadingRepliesNotifier,
    required this.showRepliesNotifier,
    required this.onToggleLike,
    required this.onShowReactionPicker,
    required this.onShowReactionUsers,
    this.onReply,
    required this.onShowMoreMenu,
    required this.onToggleReplies,
    this.hideRepliesButton = false,
    this.onAddBoost,
    this.canBoost = false,
    this.hasBoosts = false,
  });

  @override
  State<PostActionBar> createState() => _PostActionBarState();
}

class _PostActionBarState extends State<PostActionBar> {
  Timer? _hoverTimer;

  /// 防止 hover 重复触发选择器（选择器显示期间 + 关闭后短暂冷却）
  bool _pickerCooldown = false;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _onHoverEnter() {
    if (widget.isOwnPost || _pickerCooldown) return;
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 300), () {
      _pickerCooldown = true;
      widget.onShowReactionPicker();
    });
  }

  void _onHoverExit() {
    _hoverTimer?.cancel();
    // 鼠标离开后重置冷却，允许下次 hover 重新触发
    _pickerCooldown = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final leftButton = (widget.post.replyCount > 0 && !widget.hideRepliesButton)
        ? _buildRepliesButton(theme)
        : null;
    final rightActions = _buildRightActions(theme);

    // 右侧整组放进 Wrap：放得下时单行右对齐，放不下时自动换行，
    // 不做宽度估算，由布局系统自己决定
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leftButton != null) ...[
          leftButton,
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: rightActions,
          ),
        ),
      ],
    );
  }

  Widget _buildRepliesButton(ThemeData theme) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isLoadingRepliesNotifier,
      builder: (context, isLoadingReplies, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: widget.showRepliesNotifier,
          builder: (context, showReplies, _) {
            return GestureDetector(
              onTap: isLoadingReplies ? null : widget.onToggleReplies,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: showReplies
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: showReplies
                        ? theme.colorScheme.primary.withValues(alpha: 0.2)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLoadingReplies && widget.replies.isEmpty)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 15,
                        color: showReplies
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.post.replyCount}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: showReplies
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        showReplies
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                        color: showReplies
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildRightActions(ThemeData theme) {
    final actions = <Widget>[];
    if (!widget.isGuest) {
      if (!widget.isOwnPost || widget.reactions.isNotEmpty) {
        actions.add(_buildLikeReactionArea(theme));
      }
      if (!widget.isOwnPost && widget.canBoost && !widget.hasBoosts) {
        actions.add(_iconCircle(
          theme,
          tooltip: 'Boost',
          icon: Icons.rocket_launch_outlined,
          onTap: widget.onAddBoost,
        ));
      }
      actions.add(_iconCircle(
        theme,
        tooltip: context.l10n.common_reply,
        icon: Icons.reply,
        onTap: widget.onReply,
      ));
    }
    actions.add(_iconCircle(
      theme,
      icon: Icons.more_horiz,
      onTap: widget.onShowMoreMenu,
    ));
    return actions;
  }

  Widget _iconCircle(
    ThemeData theme, {
    String? tooltip,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    Widget child = GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        width: 36,
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    if (tooltip != null) {
      child = Tooltip(message: tooltip, child: child);
    }
    return child;
  }

  /// 表情叠叠乐：最多 3 个重叠排列，第一个在最上层。
  /// 描边沿表情自身轮廓（贴纸效果）：把表情染成底色后向四周偏移绘制在底层，
  /// 再叠原图，避免圆形底盘的生硬感。
  Widget _buildReactionStack(ThemeData theme) {
    final shown = widget.reactions.take(3).toList();
    const double size = 16;
    const double step = 11; // 相邻表情的水平偏移
    return SizedBox(
      width: size + (shown.length - 1) * step,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 倒序绘制，让靠前的表情盖在上层
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: i * step,
              child: _OutlinedEmoji(
                image: emojiImageProvider(_getEmojiUrl(shown[i].id)),
                // 描边的作用是「咬掉」压在下面的表情一圈，
                // 最下层没有压着任何表情，无需描边
                outlineColor:
                    i == shown.length - 1 ? null : theme.colorScheme.surface,
                size: size,
              ),
            ),
        ],
      ),
    );
  }

  /// 构建点赞/回应区域，桌面端支持 hover 触发表情选择器
  Widget _buildLikeReactionArea(ThemeData theme) {
    Widget area = Container(
      key: widget.likeButtonKey,
      height: 36,
      decoration: BoxDecoration(
        color: widget.currentUserReaction != null
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.currentUserReaction != null
              ? theme.colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 左侧区域：回应表情 + 数量 → 查看回应人
          if (widget.reactions.isNotEmpty)
            GestureDetector(
              onTap: () => widget.onShowReactionUsers(null),
              onLongPress: widget.isOwnPost ? null : widget.onShowReactionPicker,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 36,
                padding: const EdgeInsets.only(left: 12),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!(widget.reactions.length == 1 && widget.reactions.first.id == 'heart')) ...[
                      _buildReactionStack(theme),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      '${widget.reactions.fold(0, (sum, r) => sum + r.count)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: widget.currentUserReaction != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),

          // 右侧区域：点赞/回应图标 → 点赞/取消
          GestureDetector(
            onTap: widget.isOwnPost ? null : (widget.isLiking ? null : widget.onToggleLike),
            onLongPress: widget.isOwnPost ? null : widget.onShowReactionPicker,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 36,
              padding: EdgeInsets.only(
                left: widget.reactions.isNotEmpty ? 0 : 12,
                right: 12,
              ),
              alignment: Alignment.center,
              child: widget.currentUserReaction != null
                  ? Image(
                      image: emojiImageProvider(_getEmojiUrl(widget.currentUserReaction!.id)),
                      width: 20,
                      height: 20,
                      errorBuilder: (_, _, _) => const Icon(Icons.favorite, size: 20),
                    )
                  : Icon(
                      Icons.favorite_border,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
          ),
        ],
      ),
    );

    // 桌面端：hover 延迟触发表情选择器
    if (PlatformUtils.isDesktop && !widget.isOwnPost) {
      area = MouseRegion(
        onEnter: (_) => _onHoverEnter(),
        onExit: (_) => _onHoverExit(),
        child: area,
      );
    }

    return area;
  }
}

/// 带轮廓描边的表情：底层用染成 outlineColor 的表情副本向 8 个方向偏移，
/// 形成沿图形轮廓的描边（贴纸效果）；outlineColor 为 null 时只画原图。
class _OutlinedEmoji extends StatelessWidget {
  final ImageProvider image;
  final Color? outlineColor;
  final double size;

  const _OutlinedEmoji({
    required this.image,
    required this.outlineColor,
    required this.size,
  });

  static const List<Offset> _outlineOffsets = [
    Offset(-1.5, 0),
    Offset(1.5, 0),
    Offset(0, -1.5),
    Offset(0, 1.5),
    Offset(-1.1, -1.1),
    Offset(1.1, -1.1),
    Offset(-1.1, 1.1),
    Offset(1.1, 1.1),
  ];

  @override
  Widget build(BuildContext context) {
    final emoji = Image(
      image: image,
      width: size,
      height: size,
      errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
    );
    if (outlineColor == null) return emoji;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final offset in _outlineOffsets)
          Transform.translate(
            offset: offset,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(outlineColor!, BlendMode.srcIn),
              child: emoji,
            ),
          ),
        emoji,
      ],
    );
  }
}
