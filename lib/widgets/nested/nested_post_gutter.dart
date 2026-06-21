import 'package:flutter/material.dart';
import '../../models/topic.dart';
import '../../utils/url_helper.dart';
import '../common/smart_avatar.dart';
import '../user/user_card.dart';

/// 嵌套帖子左侧头像（点击弹出用户卡片）
class NestedPostAvatar extends StatefulWidget {
  final String avatarTemplate;
  final String username;
  final Post? post;
  final int? topicId;
  static const double size = 24.0;

  static String resolveUrl(String avatarTemplate) {
    return UrlHelper.resolveUrlWithCdn(
      avatarTemplate.replaceAll('{size}', '48'),
    );
  }

  const NestedPostAvatar({
    super.key,
    required this.avatarTemplate,
    required this.username,
    this.post,
    this.topicId,
  });

  @override
  State<NestedPostAvatar> createState() => _NestedPostAvatarState();
}

class _NestedPostAvatarState extends State<NestedPostAvatar> {
  final LayerLink _link = LayerLink();

  void _openUserCard() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final anchorRect = box.localToGlobal(Offset.zero) & box.size;
    showUserCard(
      context: context,
      anchorRect: anchorRect,
      layerLink: _link,
      username: widget.username,
      topicId: widget.topicId,
      postNumber: widget.post?.postNumber,
      avatarFallbackUrl:
          widget.post?.getAvatarUrl(size: 144) ??
          NestedPostAvatar.resolveUrl(widget.avatarTemplate),
      nameFallback: widget.post?.name,
      flairUrl: widget.post?.flairUrl,
      flairName: widget.post?.flairName,
      flairBgColor: widget.post?.flairBgColor,
      flairColor: widget.post?.flairColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openUserCard,
      child: CompositedTransformTarget(
        link: _link,
        child: SmartAvatar(
          imageUrl: widget.avatarTemplate.isNotEmpty
              ? UrlHelper.resolveUrlWithCdn(
                  widget.avatarTemplate.replaceAll('{size}', '48'),
                )
              : null,
          radius: NestedPostAvatar.size / 2,
          fallbackText: widget.username,
        ),
      ),
    );
  }
}
