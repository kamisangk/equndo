import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:jovial_svg/jovial_svg.dart';
import '../../../models/topic.dart';
import '../../../services/discourse_cache_manager.dart';
import '../../common/image_context_menu.dart';

import 'builders/video_builder.dart';
import 'image_utils.dart';
import 'lazy_image.dart';
import 'selectable_adapter.dart';

/// 自定义 WidgetFactory，仅用于接管图片渲染
class DiscourseWidgetFactory extends WidgetFactory {
  final BuildContext context;
  GalleryInfo? galleryInfo;

  /// 已揭示的 spoiler 图片 URL 集合（引用 State 的 Set，实时反映揭示状态）
  final Set<String> revealedImageUrls;

  /// Post 上下文（用于引用功能）
  final Post? post;
  final int? topicId;

  /// 引用图片回调（插入回复框）
  final void Function(String quote, Post post)? onQuoteImage;

  /// 获取画廊图片列表（原图 URL）
  List<String> get galleryImages => galleryInfo?.images ?? [];

  /// SVG 加载 Future 缓存：确保同一 URL 只加载一次，且 FutureBuilder 不会重复创建 Future
  final Map<String, Future<ScalableImage?>> _svgFutures = {};

  DiscourseWidgetFactory({
    required this.context,
    this.galleryInfo,
    Set<String>? revealedImageUrls,
    this.post,
    this.topicId,
    this.onQuoteImage,
  }) : revealedImageUrls = revealedImageUrls ?? {};

  @override
  Widget? buildListMarker(
    BuildTree tree,
    InheritedProperties resolved,
    String listStyleType,
    int index,
  ) {
    final markerText = getListMarkerText(listStyleType, index);
    // 有序列表：使用等宽数字，避免 "1" 比其他数字窄导致的对齐问题
    if (markerText.isNotEmpty) {
      return Text(
        markerText,
        style: resolved.prepareTextStyle().copyWith(
          // 启用表格数字特性，让所有数字宽度一致
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    return super.buildListMarker(tree, resolved, listStyleType, index);
  }

  @override
  Widget? buildImage(BuildTree tree, ImageMetadata data) {
    final url = data.sources.firstOrNull?.url;
    if (url == null) return super.buildImage(tree, data);

    // 尝试获取宽高信息
    final double? width = data.sources.firstOrNull?.width;
    final double? height = data.sources.firstOrNull?.height;

    // 检查是否是显式的 emoji class
    final bool isEmoji = tree.element.classes.contains('emoji');
    // 独立大表情：消息仅包含 emoji 时 Discourse 会添加 only-emoji class
    final bool isOnlyEmoji = isEmoji && tree.element.classes.contains('only-emoji');

    // 获取 emoji title（用于 SelectableAdapter，使 emoji 可被选中）
    final String? emojiTitle = isEmoji
        ? (tree.element.attributes['title'] ?? tree.element.attributes['alt'])
        : null;

    // 通过 CSS 继承链直接解析 emoji 的 1em 字号
    // InheritanceResolvers 包含完整的 h1~h6、inline style 等继承信息
    double? emojiFontSize;
    if (isEmoji) {
      try {
        emojiFontSize = tree.inheritanceResolvers
            .resolve(context)
            .prepareTextStyle()
            .fontSize;
      } catch (_) {}
    }

    // 普通 URL：直接构建 widget，无需 FutureBuilder
    if (!DiscourseImageUtils.isUploadUrl(url)) {
      return _buildImageWidget(url, url, width, height, isEmoji, isOnlyEmoji: isOnlyEmoji, emojiTitle: emojiTitle, emojiFontSize: emojiFontSize);
    }

    // upload:// 短链接：命中缓存直接渲染（缓存仅含成功结果）
    final cachedUrl = DiscourseImageUtils.getCachedUploadUrl(url);
    if (cachedUrl != null) {
      return _buildImageWidget(cachedUrl, url, width, height, isEmoji, isOnlyEmoji: isOnlyEmoji, emojiTitle: emojiTitle, emojiFontSize: emojiFontSize);
    }

    // upload:// 短链接首次加载：使用 FutureBuilder 解析
    return FutureBuilder<String?>(
      future: DiscourseImageUtils.resolveUploadUrl(url),
      builder: (context, snapshot) {

        // 解析失败
        if (snapshot.connectionState == ConnectionState.done && snapshot.data == null) {
          return Icon(
            Icons.broken_image,
            color: Theme.of(context).colorScheme.outline,
            size: 24,
          );
        }

        return _buildImageWidget(snapshot.data, url, width, height, isEmoji, isOnlyEmoji: isOnlyEmoji, emojiTitle: emojiTitle, emojiFontSize: emojiFontSize);
      },
    );
  }

  /// 构建图片 widget（从缓存或 FutureBuilder 调用）
  Widget _buildImageWidget(String? resolvedUrl, String originalUrl, double? width, double? height, bool isEmoji, {bool isOnlyEmoji = false, String? emojiTitle, double? emojiFontSize}) {
    // 检查是否是 SVG（处理带查询参数的 URL）
    final isSvg = _isSvgUrl(resolvedUrl) || _isSvgUrl(originalUrl);

    // SVG emoji 直接渲染，不需要画廊逻辑
    if (isSvg && resolvedUrl != null && isEmoji) {
      return _buildSvgWidget(resolvedUrl, width, height, true, isOnlyEmoji: isOnlyEmoji, emojiFontSize: emojiFontSize);
    }

    // 使用自定义的鉴权 ImageProvider（emoji 使用独立缓存池）
    final imageProvider = resolvedUrl != null && !isSvg
        ? (isEmoji ? emojiImageProvider(resolvedUrl) : discourseImageProvider(resolvedUrl))
        : null;

    // 检查是否在画廊列表中（使用 findIndex 支持缩略图→原图的多种 URL 变体匹配）
    final int galleryIndex = resolvedUrl != null ? (galleryInfo?.findIndex(resolvedUrl) ?? -1) : -1;
    final bool isGalleryImage = galleryIndex != -1;

    // 生成唯一 Tag
    // 画廊图片使用确定性 tag（基于画廊内容和索引），以便切换图片后 Hero 动画能正确返回
    // 非画廊图片使用 UniqueKey 避免冲突
    final String heroTag;
    if (isGalleryImage) {
      final int galleryHash = Object.hashAll(galleryImages);
      heroTag = "gallery_${galleryHash}_$galleryIndex";
    } else {
      heroTag = "${resolvedUrl ?? originalUrl}_${UniqueKey().toString()}";
    }

    return Builder(
      builder: (context) {
        // 基准字号（1em，跟随 h1~h6、inline style 等缩放）
        final double emojiBaseSize = emojiFontSize
            ?? DefaultTextStyle.of(context).style.fontSize
            ?? 16.0;
        // only-emoji: 独立大表情 32dp（Discourse CSS: img.emoji.only-emoji { width: 32px; height: 32px }）
        // 普通 emoji: 1em
        final double displaySize = isOnlyEmoji ? 32.0 : emojiBaseSize;

        // 如果不是画廊图片（通常是 Emoji 或预览中的 upload:// 图片）
        if (!isGalleryImage || isEmoji) {
           // SVG 非 emoji、非画廊图片：渲染 SVG 并支持长按菜单
           if (isSvg && resolvedUrl != null) {
             final svgWidget = _buildSvgWidget(resolvedUrl, width, height, false);
             return GestureDetector(
               onLongPress: () {
                 _showImageContextMenu(context, resolvedUrl, heroTag);
               },
               onSecondaryTapUp: (details) {
                 _showImageContextMenu(context, resolvedUrl, heroTag, position: details.globalPosition);
               },
               child: svgWidget,
             );
           }

           Widget imageWidget = imageProvider != null
               ? Image(
                   image: imageProvider,
                   fit: BoxFit.contain,
                   // Emoji 使用固定尺寸，普通图片让其自适应（由外层约束控制）
                   width: isEmoji ? displaySize : null,
                   height: isEmoji ? displaySize : null,
                   loadingBuilder: (context, child, loadingProgress) {
                     if (loadingProgress == null) return child;
                     return SizedBox(
                       width: isEmoji ? displaySize : width ?? 24,
                       height: isEmoji ? displaySize : height ?? 24,
                       child: Center(
                         child: SizedBox(
                           width: 12,
                           height: 12,
                           child: CircularProgressIndicator(
                             strokeWidth: 1.5,
                             value: loadingProgress.expectedTotalBytes != null
                                 ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                 : null,
                           ),
                         ),
                       ),
                     );
                   },
                   errorBuilder: (context, error, stackTrace) {
                     return Icon(
                       Icons.broken_image,
                       color: Theme.of(context).colorScheme.outline,
                       size: isEmoji ? displaySize : 24,
                     );
                   },
                 )
               : SizedBox(
                   width: isEmoji ? displaySize : width ?? 24,
                   height: isEmoji ? displaySize : height ?? 24,
                   child: const Center(
                     child: SizedBox(
                       width: 12,
                       height: 12,
                       child: CircularProgressIndicator(strokeWidth: 1.5),
                     ),
                   ),
                 );

           if (isEmoji) {
             Widget emojiWidget = Container(
               // only-emoji: 独立大表情添加垂直间距（Discourse CSS: margin: .5em 0）
               margin: isOnlyEmoji
                   ? EdgeInsets.symmetric(vertical: emojiBaseSize * 0.5, horizontal: 1.0)
                   : const EdgeInsets.symmetric(horizontal: 2.0),
               child: imageWidget,
             );
             // 用 SelectableAdapter 包裹，使 emoji 参与文本选择
             if (emojiTitle != null && emojiTitle.isNotEmpty) {
               emojiWidget = SelectableAdapter(
                 selectedText: emojiTitle,
                 child: emojiWidget,
               );
             }
             return emojiWidget;
           }

           // 非画廊图片：不添加点击查看功能，但支持长按/右键菜单查看大图
           if (resolvedUrl != null) {
             return GestureDetector(
               onLongPress: () {
                 _showImageContextMenu(context, resolvedUrl, heroTag);
               },
               onSecondaryTapUp: (details) {
                 _showImageContextMenu(context, resolvedUrl, heroTag, position: details.globalPosition);
               },
               child: imageWidget,
             );
           }
           return imageWidget;
        }

        // 画廊图片处理
        Widget buildGalleryImage() {
          // SVG 画廊图片：用 _buildSvgWidget 渲染，包裹点击/长按手势
          if (isSvg && resolvedUrl != null) {
            final svgWidget = _buildSvgWidget(resolvedUrl, width, height, false);
            return GestureDetector(
              onTap: () {
                DiscourseImageUtils.openViewerFiltered(
                  context: context,
                  galleryInfo: galleryInfo!,
                  revealedImageUrls: revealedImageUrls,
                  imageUrl: resolvedUrl,
                  heroTag: heroTag,
                  fullGalleryIndex: galleryIndex,
                  thumbnailUrl: resolvedUrl,
                );
              },
              onLongPress: () {
                _showImageContextMenu(context, resolvedUrl, heroTag);
              },
              onSecondaryTapUp: (details) {
                _showImageContextMenu(context, resolvedUrl, heroTag, position: details.globalPosition);
              },
              child: svgWidget,
            );
          }

          if (imageProvider == null) {
            // URL 解析中，显示占位符
            final screenWidth = MediaQuery.of(context).size.width;
            final double displayWidth = screenWidth - 32;
            final double displayHeight = width != null && height != null && height > 0
                ? displayWidth * (height / width)
                : 200.0;

            return Container(
              width: displayWidth,
              height: displayHeight,
              alignment: Alignment.center,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha:0.2),
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          // 使用 LazyImage 懒加载
          return LazyImage(
            imageProvider: imageProvider,
            width: width,
            height: height,
            heroTag: heroTag,
            cacheKey: resolvedUrl, // 使用稳定的 URL 作为缓存 key
            onTap: () {
              DiscourseImageUtils.openViewerFiltered(
                context: context,
                galleryInfo: galleryInfo!,
                revealedImageUrls: revealedImageUrls,
                imageUrl: resolvedUrl!,
                heroTag: heroTag,
                fullGalleryIndex: galleryIndex,
                thumbnailUrl: resolvedUrl,
              );
            },
            onLongPress: () {
              _showImageContextMenu(context, resolvedUrl!, heroTag);
            },
            onSecondaryTapUp: (details) {
              _showImageContextMenu(context, resolvedUrl!, heroTag, position: details.globalPosition);
            },
          );
        }

        return buildGalleryImage();
      }
    );
  }

  @override
  Widget? buildGestureDetector(
    BuildTree tree,
    Widget child,
    GestureRecognizer recognizer,
  ) {
    // 对 a.lightbox 不包裹手势，避免与内部图片的 GestureDetector 冲突
    // 图片的点击由 buildImage 中的 LazyImage/HeroImage 处理
    final element = tree.element;
    if (element.localName == 'a' &&
        element.classes.contains('lightbox')) {
      return child;
    }
    return super.buildGestureDetector(tree, child, recognizer);
  }



  @override
  Widget? buildVideoPlayer(
    BuildTree tree,
    String url, {
    required bool autoplay,
    required bool controls,
    double? height,
    required bool loop,
    String? posterUrl,
    double? width,
  }) {
    final dimensOk = height != null && height > 0 && width != null && width > 0;
    final poster = posterUrl != null
        ? buildImage(tree, ImageMetadata(sources: [ImageSource(posterUrl)]))
        : null;
    return DiscourseVideoPlayer(
      url,
      aspectRatio: dimensOk ? width / height : 16 / 9,
      autoResize: !dimensOk,
      autoplay: autoplay,
      controls: controls,
      errorBuilder: (context, _, error) =>
          onErrorBuilder(context, tree, error, url) ?? widget0,
      loadingBuilder: (context, _, child) =>
          onLoadingBuilder(context, tree, null, url) ?? widget0,
      loop: loop,
      poster: poster,
    );
  }

  /// 显示图片长按菜单
  void _showImageContextMenu(BuildContext context, String imageUrl, String heroTag, {Offset? position}) {
    ImageContextMenu.show(
      context: context,
      imageUrl: imageUrl,
      post: post,
      topicId: topicId,
      onQuoteImage: onQuoteImage,
      position: position,
    );
  }

  /// 检查 URL 是否为 SVG（处理带查询参数的情况）
  bool _isSvgUrl(String? url) {
    if (url == null) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.path.toLowerCase().endsWith('.svg');
  }

  /// 构建 SVG 图片 widget
  ///
  /// 使用 FutureBuilder + 缓存 Future，确保异步加载完成后自动刷新显示。
  /// Future 缓存和 DiscourseWidgetFactory 实例同生命周期（跟随 DiscourseHtmlContent State）。
  Widget _buildSvgWidget(String url, double? width, double? height, bool isEmoji, {bool isOnlyEmoji = false, double? emojiFontSize}) {
    final future = _svgFutures.putIfAbsent(url, () => _loadSvg(url));

    return FutureBuilder<ScalableImage?>(
      future: future,
      builder: (context, snapshot) {
        // 基准字号（1em）
        final emojiBaseSize = emojiFontSize
            ?? DefaultTextStyle.of(context).style.fontSize
            ?? 16.0;
        // only-emoji: 独立大表情 32dp; 普通 emoji: 1em
        final emojiSize = isOnlyEmoji ? 32.0 : emojiBaseSize;

        final si = snapshot.data;
        if (si != null) {
          if (isEmoji) {
            return Container(
              margin: isOnlyEmoji
                  ? EdgeInsets.symmetric(vertical: emojiBaseSize * 0.5, horizontal: 1.0)
                  : const EdgeInsets.symmetric(horizontal: 2.0),
              child: SizedBox(
                width: emojiSize,
                height: emojiSize,
                child: ScalableImageWidget(si: si, fit: BoxFit.contain),
              ),
            );
          }
          // 非 emoji SVG 图片：使用 ScalableImage 自带的 viewport 尺寸
          final siWidth = width ?? si.viewport.width;
          final siHeight = height ?? si.viewport.height;
          return SizedBox(
            width: siWidth,
            height: siHeight,
            child: ScalableImageWidget(si: si, fit: BoxFit.contain),
          );
        }

        // 加载中或失败：占位
        final size = isEmoji ? emojiSize : (width ?? 24.0);
        return SizedBox(width: size, height: isEmoji ? emojiSize : (height ?? 24.0));
      },
    );
  }

  /// 异步加载 SVG 文件并解析为 ScalableImage
  Future<ScalableImage?> _loadSvg(String url) async {
    try {
      final file = await DiscourseCacheManager().getSingleFile(url);
      final content = await file.readAsString();
      return ScalableImage.fromSvgString(content, warnF: (_) {});
    } catch (_) {
      return null;
    }
  }
}
