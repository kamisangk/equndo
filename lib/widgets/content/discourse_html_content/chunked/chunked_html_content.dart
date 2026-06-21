import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import '../discourse_html_content_widget.dart';
import '../image_utils.dart';
import '../../../../models/topic.dart';
import 'html_chunk.dart';
import 'html_chunk_cache.dart';

/// 分块 HTML 内容组件
///
/// 将长 HTML 内容分割为多个块，一次性构建所有块。
/// 短帖子走此路径，长帖子走 Sliver 虚拟化路径（PostItemSliver）。
class ChunkedHtmlContent extends StatefulWidget {
  final String html;
  final TextStyle? textStyle;

  /// 内部链接点击回调 (linux.do 话题链接)
  final void Function(int topicId, String? topicSlug, int? postNumber)? onInternalLinkTap;

  /// 链接点击统计数据
  final List<LinkCount>? linkCounts;

  /// 是否启用分块渲染（默认根据内容长度自动判断）
  final bool? enableChunking;

  /// 分块阈值（HTML 长度超过此值时启用分块）
  static const int chunkThreshold = 5000;

  /// 被提及用户列表（含状态 emoji）
  final List<MentionedUser>? mentionedUsers;

  /// Post 对象（用于投票数据和链接追踪）
  final Post? post;

  /// 话题 ID（用于链接点击追踪）
  final int? topicId;

  /// 文本选择变化回调
  final void Function(SelectedContent?)? onSelectionChanged;

  /// 自定义右键/长按菜单构建器
  final Widget Function(BuildContext, SelectableRegionState)? contextMenuBuilder;

  /// 图片引用回调（长按图片 → 引用 → 打开回复框）
  final void Function(String quote, Post post)? onQuoteImage;

  /// 获取 HTML 分块结果，不需要分块时返回 null
  static List<HtmlChunk>? getChunks(String html) {
    if (html.length <= chunkThreshold) return null;

    final cached = HtmlChunkCache.instance.get(html);
    final chunks = cached ?? HtmlChunkCache.instance.parseSync(html);

    if (chunks.length <= 1) return null;
    return chunks;
  }

  /// 提取画廊图片列表（与 GalleryInfo.fromHtml 一致，只收集 lightbox 图片）
  static List<String> extractGalleryImages(String html) {
    return GalleryInfo.fromHtml(html).images;
  }

  /// 预加载 HTML 分块（在获取帖子数据后调用）
  static void preload(String html) {
    if (html.length > chunkThreshold) {
      HtmlChunkCache.instance.preload(html);
    }
  }

  /// 批量预加载
  static void preloadAll(List<String> htmlList) {
    for (final html in htmlList) {
      preload(html);
    }
  }

  const ChunkedHtmlContent({
    super.key,
    required this.html,
    this.textStyle,
    this.onInternalLinkTap,
    this.linkCounts,
    this.enableChunking,
    this.mentionedUsers,
    this.post,
    this.topicId,
    this.onSelectionChanged,
    this.contextMenuBuilder,
    this.onQuoteImage,
  });

  @override
  State<ChunkedHtmlContent> createState() => _ChunkedHtmlContentState();
}

class _ChunkedHtmlContentState extends State<ChunkedHtmlContent> {
  List<HtmlChunk>? _chunks;
  late bool _useChunking;
  late List<String> _galleryImages;
  late Set<String> _spoilerImageUrls;
  /// 所有分块共享的已揭示图片 URL 集合
  final Set<String> _revealedImageUrls = {};

  @override
  void initState() {
    super.initState();
    _initChunks();
  }

  @override
  void didUpdateWidget(ChunkedHtmlContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html ||
        oldWidget.enableChunking != widget.enableChunking) {
      _initChunks();
    }
  }

  void _initChunks() {
    final galleryInfo = GalleryInfo.fromHtml(widget.html);
    _galleryImages = galleryInfo.images;
    _spoilerImageUrls = galleryInfo.spoilerImageUrls;

    _useChunking = widget.enableChunking ??
        (widget.html.length > ChunkedHtmlContent.chunkThreshold);

    if (_useChunking) {
      final cached = HtmlChunkCache.instance.get(widget.html);
      if (cached != null) {
        _chunks = cached;
      } else {
        _chunks = HtmlChunkCache.instance.parseSync(widget.html);
      }

      if (_chunks!.length <= 1) {
        _useChunking = false;
        _chunks = null;
      }
    } else {
      _chunks = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 不启用分块时，使用原有组件（传递已解析的画廊信息避免重复 DOM 解析）
    if (!_useChunking || _chunks == null) {
      return DiscourseHtmlContent(
        html: widget.html,
        textStyle: widget.textStyle,
        onInternalLinkTap: widget.onInternalLinkTap,
        linkCounts: widget.linkCounts,
        mentionedUsers: widget.mentionedUsers,
        post: widget.post,
        topicId: widget.topicId,
        onSelectionChanged: widget.onSelectionChanged,
        contextMenuBuilder: widget.contextMenuBuilder,
        onQuoteImage: widget.onQuoteImage,
        galleryImages: _galleryImages,
        spoilerImageUrls: _spoilerImageUrls,
        revealedImageUrls: _revealedImageUrls,
      );
    }

    // 一次性构建所有块
    final children = <Widget>[];
    for (int i = 0; i < _chunks!.length; i++) {
      final chunk = _chunks![i];
      children.add(HtmlChunkWidget(
        key: ValueKey('chunk-${chunk.index}'),
        chunk: chunk,
        textStyle: widget.textStyle,
        onInternalLinkTap: widget.onInternalLinkTap,
        linkCounts: widget.linkCounts,
        galleryImages: _galleryImages,
        spoilerImageUrls: _spoilerImageUrls,
        revealedImageUrls: _revealedImageUrls,
        mentionedUsers: widget.mentionedUsers,
        fullHtml: widget.html,
        post: widget.post,
        topicId: widget.topicId,
        onQuoteImage: widget.onQuoteImage,
      ));
    }

    return SelectionArea(
      onSelectionChanged: widget.onSelectionChanged,
      contextMenuBuilder: widget.contextMenuBuilder ?? (context, state) {
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: state.contextMenuButtonItems,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// 单个块的渲染 Widget（公开类，供 PostItemSliver 直接使用）
class HtmlChunkWidget extends StatelessWidget {
  final HtmlChunk chunk;
  final TextStyle? textStyle;
  final void Function(int topicId, String? topicSlug, int? postNumber)? onInternalLinkTap;
  final List<LinkCount>? linkCounts;
  final List<String> galleryImages;
  final Set<String>? spoilerImageUrls;
  final Set<String>? revealedImageUrls;
  final List<MentionedUser>? mentionedUsers;
  final String fullHtml;
  final Post? post;
  final int? topicId;

  /// 是否启用文本选择
  ///
  /// ChunkedHtmlContent 中由外层 SelectionArea 统一控制，此处传 false；
  /// PostItemSliver 中各块独立存在于 SliverList，需传 true 让每块自行支持选择。
  final bool enableSelectionArea;

  /// 文本选择变化回调
  final void Function(SelectedContent?)? onSelectionChanged;

  /// 自定义右键/长按菜单构建器
  final Widget Function(BuildContext, SelectableRegionState)? contextMenuBuilder;

  /// 图片引用回调
  final void Function(String quote, Post post)? onQuoteImage;

  const HtmlChunkWidget({
    super.key,
    required this.chunk,
    this.textStyle,
    this.onInternalLinkTap,
    this.linkCounts,
    required this.galleryImages,
    this.spoilerImageUrls,
    this.revealedImageUrls,
    this.mentionedUsers,
    required this.fullHtml,
    this.post,
    this.topicId,
    this.enableSelectionArea = false,
    this.onSelectionChanged,
    this.contextMenuBuilder,
    this.onQuoteImage,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DiscourseHtmlContent(
        html: chunk.html,
        textStyle: textStyle,
        onInternalLinkTap: onInternalLinkTap,
        linkCounts: linkCounts,
        galleryImages: galleryImages,
        spoilerImageUrls: spoilerImageUrls,
        revealedImageUrls: revealedImageUrls,
        enableSelectionArea: enableSelectionArea,
        mentionedUsers: mentionedUsers,
        fullHtml: fullHtml,
        isChunkChild: true,
        post: post,
        topicId: topicId,
        onSelectionChanged: onSelectionChanged,
        contextMenuBuilder: contextMenuBuilder,
        onQuoteImage: onQuoteImage,
      ),
    );
  }
}
