import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:pangutext/pangutext.dart';
import '../../../models/topic.dart';
import '../../../providers/preferences_provider.dart';
import '../../../services/discourse/discourse_service.dart';
import '../../../services/emoji_handler.dart';
import '../../../providers/download_provider.dart';
import '../../../utils/discourse_url_parser.dart';
import '../../../utils/link_launcher.dart';
import '../../../utils/url_helper.dart';
import 'discourse_widget_factory.dart';
import 'builders/quote_card_builder.dart';
import 'builders/onebox_card_builder.dart';
import 'builders/blockquote_builder.dart';
import 'builders/code_block_builder.dart';
import 'builders/spoiler_builder.dart';
import 'builders/table_builder.dart';
import 'builders/details_builder.dart';
import 'builders/footnote_builder.dart';
import 'builders/poll_builder.dart';
import 'builders/math_builder.dart';
import 'builders/chat_transcript_builder.dart';
import 'builders/iframe_builder.dart';
import 'builders/lazy_video_builder.dart';
import 'builders/image_grid_builder.dart';
import 'builders/combined_decorator_overlay.dart';
import 'builders/local_date_builder.dart';
import 'builders/mention_builder.dart';
import 'builders/policy_builder.dart';
import 'builders/scan_boundary.dart';
import 'current_post_scope.dart';
import 'image_utils.dart';

/// Discourse HTML 内容渲染 Widget
/// 封装了所有自定义渲染逻辑
class DiscourseHtmlContent extends ConsumerStatefulWidget {
  final String html;
  final TextStyle? textStyle;
  final bool compact; // 紧凑模式：移除段落边距
  /// 内部链接点击回调 (linux.do 话题链接)
  final void Function(int topicId, String? topicSlug, int? postNumber)? onInternalLinkTap;
  /// 链接点击统计数据
  final List<LinkCount>? linkCounts;
  /// 外部传入的画廊图片列表（用于分块渲染时共享完整画廊）
  final List<String>? galleryImages;
  /// 外部传入的 spoiler 图片 URL 集合（与 galleryImages 配合使用）
  final Set<String>? spoilerImageUrls;
  /// 外部共享的已揭示图片 URL 集合（跨分块/嵌套共享状态）
  final Set<String>? revealedImageUrls;
  /// 是否启用选择区域（分块渲染时由外层统一控制）
  final bool enableSelectionArea;
  /// 被提及用户列表（含状态 emoji）
  final List<MentionedUser>? mentionedUsers;
  /// 完整 HTML（用于脚注匹配，分块渲染时传递）
  final String? fullHtml;
  /// 是否是分块渲染的子块（子块仍需注入点击数，与嵌套渲染区分）
  final bool isChunkChild;
  /// Post 对象（用于投票数据）
  final Post? post;
  /// 话题 ID（用于链接点击追踪）
  final int? topicId;
  /// 覆盖混排优化开关（null 表示使用全局设置）
  final bool? enablePanguSpacing;
  /// 截图模式：展开代码块、表格等滚动区域，确保完整显示
  final bool screenshotMode;
  /// 文本选择变化回调
  final void Function(SelectedContent?)? onSelectionChanged;
  /// 自定义右键/长按菜单构建器
  final Widget Function(BuildContext, SelectableRegionState)? contextMenuBuilder;
  /// 图片引用回调（长按图片 → 引用 → 打开回复框）
  final void Function(String quote, Post post)? onQuoteImage;

  const DiscourseHtmlContent({
    super.key,
    required this.html,
    this.textStyle,
    this.compact = false,
    this.onInternalLinkTap,
    this.linkCounts,
    this.galleryImages,
    this.spoilerImageUrls,
    this.revealedImageUrls,
    this.enableSelectionArea = true,
    this.mentionedUsers,
    this.fullHtml,
    this.isChunkChild = false,
    this.post,
    this.topicId,
    this.enablePanguSpacing,
    this.screenshotMode = false,
    this.onSelectionChanged,
    this.contextMenuBuilder,
    this.onQuoteImage,
  });

  /// 批量预热 Pangu 混排处理（在 isolate 中执行，避免首次渲染阻塞主线程）
  static void preloadPangu(List<String> htmlList) {
    _DiscourseHtmlContentState._preloadPangu(htmlList);
  }

  @override
  ConsumerState<DiscourseHtmlContent> createState() => _DiscourseHtmlContentState();
}

class _DiscourseHtmlContentState extends ConsumerState<DiscourseHtmlContent> {
  late final DiscourseWidgetFactory _widgetFactory;
  late final GalleryInfo _galleryInfo;

  /// 已揭示的内联 spoiler ID 集合
  final Set<String> _revealedSpoilers = {};

  /// 附件链接 URL → 显示文件名 映射（由 customWidgetBuilder 填充）
  final Map<String, String> _attachmentFileNames = {};

  /// 已揭示的 spoiler 内的图片 URL 集合（用于画廊过滤）
  /// 优先使用外部共享集合，否则创建本地集合
  late final Set<String> _revealedImageUrls;

  /// 预处理后的 HTML 缓存，避免每次 build 都重新执行正则替换
  String? _cachedProcessedHtml;
  /// 缓存对应的原始输入快照，用于判断是否需要重新计算
  String? _cachedRawHtml;
  List<MentionedUser>? _cachedMentionedUsers;
  List<LinkCount>? _cachedLinkCounts;
  bool? _cachedPanguSpacing;

  /// 全局预处理 HTML 缓存（跨 State 实例共享）
  /// 当帖子滑出再滑回时新 State 可直接命中，避免重复正则 + Pangu 处理
  static final Map<int, String> _globalPreprocessCache = {};
  static const int _maxGlobalCacheSize = 200;

  /// Pangu 预处理缓存（支持 isolate 预热，避免首次渲染阻塞主线程）
  static final Map<(int, int), String> _panguCache = {};
  static const int _maxPanguCacheSize = 200;
  static final Set<(int, int)> _pendingPanguKeys = {};

  static (int, int) _panguKeyOf(String html) => (html.hashCode, html.length);

  /// 批量预热 Pangu（在 isolate 中执行）
  static void _preloadPangu(List<String> htmlList) {
    final toProcess = <String>[];
    for (final html in htmlList) {
      final key = _panguKeyOf(html);
      if (_panguCache.containsKey(key) || _pendingPanguKeys.contains(key)) {
        continue;
      }
      toProcess.add(html);
      _pendingPanguKeys.add(key);
    }
    if (toProcess.isEmpty) return;

    compute(_batchPanguInIsolate, toProcess).then((results) {
      for (int i = 0; i < toProcess.length; i++) {
        final key = _panguKeyOf(toProcess[i]);
        _panguCache[key] = results[i];
        _pendingPanguKeys.remove(key);
      }
      while (_panguCache.length > _maxPanguCacheSize) {
        _panguCache.remove(_panguCache.keys.first);
      }
    });
  }

  /// 获取 Pangu 处理结果（优先缓存，回退同步处理）
  static String _applyPangu(String html) {
    final key = _panguKeyOf(html);
    final cached = _panguCache[key];
    if (cached != null) {
      _panguCache.remove(key);
      _panguCache[key] = cached;
      return cached;
    }
    // 缓存未命中，同步处理并缓存
    final result = Pangu().spacingText(html);
    while (_panguCache.length >= _maxPanguCacheSize) {
      _panguCache.remove(_panguCache.keys.first);
    }
    _panguCache[key] = result;
    return result;
  }

  @override
  void initState() {
    super.initState();
    // 使用外部共享的已揭示集合，或创建本地集合
    _revealedImageUrls = widget.revealedImageUrls ?? {};
    // 优先使用外部传入的画廊图片列表，否则从 HTML 提取
    if (widget.galleryImages != null && widget.galleryImages!.isNotEmpty) {
      // 从外部传入的画廊列表构建 GalleryInfo（附带 spoiler 标记）
      _galleryInfo = GalleryInfo.fromImages(
        widget.galleryImages!,
        spoilerImageUrls: widget.spoilerImageUrls,
      );
    } else {
      // 从 HTML 提取画廊信息（包含缩略图到索引的映射和 spoiler 标记）
      _galleryInfo = GalleryInfo.fromHtml(widget.html);
    }
    _widgetFactory = DiscourseWidgetFactory(
      context: context,
      galleryInfo: _galleryInfo,
      revealedImageUrls: _revealedImageUrls,
      post: widget.post,
      topicId: widget.topicId,
      onQuoteImage: widget.onQuoteImage,
    );
  }



  /// 预处理 HTML：注入用户状态 emoji、链接点击次数，添加内联元素 padding
  String _preprocessHtml(String html, bool enablePanguSpacing) {
    // 检查全局缓存
    final globalKey = _computeGlobalCacheKey(html, enablePanguSpacing);
    final globalCached = _globalPreprocessCache[globalKey];
    if (globalCached != null) {
      // LRU: 移到末尾
      _globalPreprocessCache.remove(globalKey);
      _globalPreprocessCache[globalKey] = globalCached;
      return globalCached;
    }

    // Pangu 混排优先处理（命中 isolate 预热缓存时无主线程开销）
    var processedHtml = enablePanguSpacing ? _applyPangu(html) : html;

    // 0. 将资源类属性转换为绝对路径。
    // 只处理 src/poster，避免把附件 href 也错误改到 CDN。
    processedHtml = processedHtml.replaceAllMapped(
      RegExp(r'''(src|poster)=(["'])(/[^"']+)\2''', caseSensitive: false),
      (match) {
        final attr = match.group(1)!;
        final quote = match.group(2)!;
        final path = match.group(3)!;
        return '$attr=$quote${UrlHelper.resolveUrlWithCdn(path)}$quote';
      },
    );

    // 1. 注入用户状态 emoji 到 mention 链接
    if (widget.mentionedUsers != null && widget.mentionedUsers!.isNotEmpty) {
      for (final user in widget.mentionedUsers!) {
        if (user.statusEmoji != null) {
          final emojiUrl = EmojiHandler().getEmojiUrl(user.statusEmoji!);
          {
            // 查找该用户的 mention 链接，在 </a> 前注入 emoji 图片
            final escapedUsername = RegExp.escape(user.username);
            final pattern = RegExp(
              '(<a[^>]*class="[^"]*mention[^"]*"[^>]*href="[^"]*\\/u\\/$escapedUsername"[^>]*>)(@[^<]*)(</a>)',
              caseSensitive: false,
            );
            processedHtml = processedHtml.replaceAllMapped(pattern, (match) {
              final openTag = match.group(1)!;
              final content = match.group(2)!;
              final closeTag = match.group(3)!;
              return '$openTag$content<img src="$emojiUrl" class="emoji mention-status" style="width:14px;height:14px;vertical-align:middle;margin-left:2px">$closeTag';
            });
          }
        }
      }
    }

    // 2. 给内联代码前后添加不换行空格（\u00A0）作为粘性内边距
    // 在 code 外部使用普通字体渲染（宽度可控），不换行特性确保和 code 粘在一起
    // 同时匹配 \u00A0 和 &nbsp;（innerHtml 会将 \u00A0 序列化为 &nbsp;）
    processedHtml = processedHtml.replaceAllMapped(
      RegExp('(?:\u00A0|&nbsp;)?<code>([^<]*)</code>(?:\u00A0|&nbsp;)?', caseSensitive: false),
      (match) {
        final content = match.group(1)!;
        return '\u00A0<code>$content</code>\u00A0';
      },
    );

    // 3. 给 mention 链接后面添加零宽度空格，确保右边圆角正确渲染
    processedHtml = processedHtml.replaceAllMapped(
      RegExp(r'(<a[^>]*class="[^"]*mention[^"]*"[^>]*>.*?</a>)'),
      (match) => '${match.group(1)}\u200B',
    );

    // 4. 将 lightbox-wrapper 后面紧跟的 <br> 替换为自定义占位标记
    //    在 customWidgetBuilder 中渲染为固定高度 SizedBox，确保分块内外间距一致
    processedHtml = processedHtml.replaceAllMapped(
      RegExp(r'(</a>\s*</div>)\s*<br\s*/?>', caseSensitive: false),
      (match) => '${match.group(1)}<div class="lb-spacer"></div>',
    );

    // 5. 注入链接点击数（顶层处理或分块子块处理，避免嵌套重复）
    // - fullHtml == null: 顶层渲染
    // - isChunkChild: 分块子块（需要注入，因为分块时顶层没有处理 HTML）
    if (widget.linkCounts != null && (widget.fullHtml == null || widget.isChunkChild)) {
      processedHtml = _injectClickCounts(processedHtml);
    }

    // 存入全局缓存
    while (_globalPreprocessCache.length >= _maxGlobalCacheSize) {
      _globalPreprocessCache.remove(_globalPreprocessCache.keys.first);
    }
    _globalPreprocessCache[globalKey] = processedHtml;

    return processedHtml;
  }

  /// 计算全局缓存 key（综合所有影响预处理结果的输入）
  int _computeGlobalCacheKey(String html, bool enablePanguSpacing) {
    var key = html.hashCode;
    key = key * 37 + html.length;
    key = key * 37 + (enablePanguSpacing ? 1 : 0);
    // 是否注入链接点击数
    final injectLinks = widget.linkCounts != null &&
        (widget.fullHtml == null || widget.isChunkChild);
    key = key * 37 + (injectLinks ? 1 : 0);
    // mentionedUsers 的 statusEmoji 影响注入结果
    if (widget.mentionedUsers != null) {
      for (final u in widget.mentionedUsers!) {
        key = key * 37 + u.username.hashCode;
        key = key * 37 + (u.statusEmoji?.hashCode ?? 0);
      }
    }
    // linkCounts 影响点击数注入
    if (widget.linkCounts != null && injectLinks) {
      for (final l in widget.linkCounts!) {
        key = key * 37 + l.url.hashCode;
        key = key * 37 + l.clicks;
      }
    }
    return key;
  }

  /// 注入链接点击数到 HTML
  String _injectClickCounts(String html) {
    if (widget.linkCounts == null) return html;

    var result = html;
    for (final lc in widget.linkCounts!) {
      if (lc.clicks <= 0) continue;

      // 匹配链接（排除已有点击数标记的、mention、hashtag 等特殊链接）
      // 使用 data-clicks 属性标记已处理
      final escapedUrl = RegExp.escape(lc.url);
      final pattern = RegExp(
        '(<a(?![^>]*data-clicks)[^>]*href="[^"]*$escapedUrl[^"]*"[^>]*>)(.*?)(</a>)(?!\\s*<span[^>]*class="[^"]*click-count)',
        caseSensitive: false,
      );

      final formattedCount = _formatClickCount(lc.clicks);
      result = result.replaceAllMapped(pattern, (match) {
        final openTag = match.group(1)!;
        final content = match.group(2)!;
        final closeTag = match.group(3)!;
        // 添加 data-clicks 属性防止重复处理，追加点击数 span
        final newOpenTag = openTag.replaceFirst('<a', '<a data-clicks="$formattedCount"');
        return '$newOpenTag$content$closeTag <span class="click-count">\u2009$formattedCount\u2009</span>';
      });
    }
    return result;
  }

  /// 追踪链接点击
  /// 仅当有 topicId 和 post 时才追踪
  void _trackClick(String url) {
    if (widget.topicId == null || widget.post == null) return;

    // 不追踪以下类型的链接：
    // 1. 用户链接 (/u/username) - 相当于 mention
    if (DiscourseUrlParser.isUserLink(url)) return;
    // 2. 附件/上传链接
    if (url.startsWith('upload://') ||
        url.contains('/uploads/') ||
        url.contains('/secure-uploads/') ||
        url.contains('/secure-media-uploads/')) {
      return;
    }
    // 3. Email 链接
    if (url.startsWith('mailto:')) return;
    // 4. 锚点链接
    if (url.startsWith('#')) return;

    DiscourseService().trackClick(
      url: url,
      postId: widget.post!.id,
      topicId: widget.topicId!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkColor = theme.colorScheme.primary.toARGB32().toRadixString(16).substring(2);
    final enablePanguSpacing =
        widget.enablePanguSpacing ?? ref.watch(preferencesProvider).displayPanguSpacing;
    // 仅当输入变化时才重新执行正则预处理，避免每次 build 都重复计算
    if (_cachedProcessedHtml == null ||
        _cachedRawHtml != widget.html ||
        _cachedMentionedUsers != widget.mentionedUsers ||
        _cachedLinkCounts != widget.linkCounts ||
        _cachedPanguSpacing != enablePanguSpacing) {
      _cachedRawHtml = widget.html;
      _cachedMentionedUsers = widget.mentionedUsers;
      _cachedLinkCounts = widget.linkCounts;
      _cachedPanguSpacing = enablePanguSpacing;
      _cachedProcessedHtml = _preprocessHtml(widget.html, enablePanguSpacing);
    }
    final processedHtml = _cachedProcessedHtml!;

    final htmlWidget = HtmlWidget(
      processedHtml,
      textStyle: widget.textStyle,
      factoryBuilder: () => _widgetFactory,
      customWidgetBuilder: (element) => _buildCustomWidget(context, element),
      customStylesBuilder: (element) {
        final isDark = theme.brightness == Brightness.dark;

        // 检查元素是否在 spoiler 内
        bool isInSpoiler = false;
        var parent = element.parent;
        while (parent != null) {
          if (parent.classes.contains('spoiler') || parent.classes.contains('spoiled')) {
            isInSpoiler = true;
            break;
          }
          parent = parent.parent;
        }

        // img 垂直居中（与 Discourse 一致：img { vertical-align: middle }）
        if (element.localName == 'img') {
          if (element.classes.contains('emoji')) {

            return {'vertical-align': 'middle', 'width': 'auto', 'height': 'auto'};
          }
          return {'vertical-align': 'middle'};
        }

        // 内联代码样式：回归文档流，支持自然换行
        // 注意：padding 和 border-radius 会导致 WidgetSpan，只使用可内联的属性
        if (element.localName == 'code' && element.parent?.localName != 'pre') {
          return getInlineCodeStyles(isDark, isInSpoiler: isInSpoiler);
        }

        // Callout 标题内的链接继承标题颜色
        if (element.localName == 'a') {
          final parentClasses =
              (element.parent?.classes ?? const <String>[]).cast<String>();
          if (parentClasses.contains('callout-title')) {
            return {
              'color': 'inherit',
              'text-decoration': 'none',
            };
          }
        }

        // 紧凑模式下移除段落边距
        if (widget.compact && element.localName == 'p') {
          return {'margin': '0'};
        }
        // 优化链接样式
        if (element.localName == 'a') {
          // 含有 emoji 图片的链接使用 inline-block 渲染，
          // 绕过 flutter_widget_from_html 的 Flattener._getInlineRecognizer bug：
          // 当链接内有 <img>（WidgetBit）时，isIdenticalWith 会错误地将链接的
          // recognizer 判定为与根 resolvers 相同，导致 recognizer 丢失。
          // inline-block 让链接走 onRenderBlock 路径，由 TagA.onRenderBlock
          // 正确地用 GestureDetector 包裹整个链接。
          final hasEmojiImg = element.getElementsByTagName('img')
              .any((img) => img.classes.contains('emoji'));
          if (hasEmojiImg) {
            return {
              'color': '#$linkColor',
              'text-decoration': 'none',
              'display': 'inline-block',
            };
          }
          return {
            'color': '#$linkColor',
            'text-decoration': 'none',
          };
        }
        // 无序列表样式
        if (element.localName == 'ul') {
          return {
            'padding-left': '20px',
            'margin': '8px 0',
          };
        }
        // 有序列表样式
        if (element.localName == 'ol') {
          return {
            'padding-left': '20px',
            'margin': '8px 0',
          };
        }
        // 列表项样式
        if (element.localName == 'li') {
          return {
            'margin': '4px 0',
            'line-height': '1.5',
          };
        }
        // 内联 spoiler：使用特殊 font-family 标记，让文本正常渲染但可被识别
        if (element.localName == 'span' &&
            (element.classes.contains('spoiler') || element.classes.contains('spoiled'))) {
          return getSpoilerStyles();
        }
        return {};
      },
      onTapUrl: (url) async {
        // 兜底拦截 lightbox 链接：如果 URL 对应画廊中的图片，打开查看器
        // buildGestureDetector 已从源头阻止 a.lightbox 的手势包裹，
        // 但 inline span 的 recognizer 传递不经过 buildGestureDetector，需要这里兜底
        final galleryIndex = _galleryInfo.findIndex(url);
        if (galleryIndex != null) {
          final allHeroTags = _galleryInfo.heroTags;

          DiscourseImageUtils.openViewerFiltered(
            context: context,
            galleryInfo: _galleryInfo,
            revealedImageUrls: _revealedImageUrls,
            imageUrl: url,
            heroTag: allHeroTags[galleryIndex],
            fullGalleryIndex: galleryIndex,
          );
          return true;
        }

        // 追踪链接点击（fire-and-forget）
        _trackClick(url);

        // 统一链接处理逻辑
        await launchContentLink(
          context,
          url,
          onInternalLinkTap: widget.onInternalLinkTap,
          onDownloadAttachment: (downloadUrl) {
            ref.read(downloadProvider.notifier).startDownload(
                  url: downloadUrl,
                  suggestedFilename: _attachmentFileNames[downloadUrl],
                );
          },
        );
        return true;
      },
    );

    // 检测是否需要内联装饰（code 背景 / spoiler 粒子）
    // 快速字符串检测，避免对无 code/spoiler 的帖子创建 Ticker + 扫描 RenderTree
    final needsOverlay = processedHtml.contains('<code>') ||
        processedHtml.contains('"spoiler"') ||
        processedHtml.contains('"spoiled"');

    Widget result;
    if (needsOverlay) {
      // 用 CombinedDecoratorOverlay 包裹（合并处理内联代码背景和 spoiler 粒子效果）
      result = CombinedDecoratorOverlay(
        revealedSpoilers: _revealedSpoilers,
        onReveal: (id) {
          // 仅更新 Set，不触发父组件 rebuild
          // CombinedDecoratorOverlay 自身的 setState 已处理视觉更新
          // 避免父 rebuild 导致 HtmlWidget 重建 → rescan → spoiler ID 变化 → 闪回
          _revealedSpoilers.add(id);
        },
        child: htmlWidget,
      );
    } else {
      result = htmlWidget;
    }

    // 把当前 Post 通过 InheritedWidget 广播给 HTML 子树的自定义组件
    // （如 PolicyWidget），让它们能响应外层 Post 引用变化——绕开
    // HtmlWidget 在 cooked 未变时复用子树导致 widget.post 冻住的问题。
    if (widget.post != null) {
      result = CurrentPostScope(post: widget.post!, child: result);
    }

    // 根据参数决定是否包裹 SelectionArea
    if (widget.enableSelectionArea) {
      return SelectionArea(
        onSelectionChanged: widget.onSelectionChanged,
        contextMenuBuilder: widget.contextMenuBuilder ?? (context, state) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: state.contextMenuButtonItems,
          );
        },
        child: result,
      );
    }
    return result;
  }

  Widget? _buildCustomWidget(BuildContext context, dynamic element) {
    final theme = Theme.of(context);

    // lightbox 图片间距占位：固定高度，确保分块内外一致
    if (element.localName == 'div' && element.classes.contains('lb-spacer')) {
      final fontSize = widget.textStyle?.fontSize ?? 14.0;
      return SizedBox(height: fontSize * 0.5);
    }

    // 处理 iframe：统一使用 InAppWebView 渲染
    // flutter_widget_from_html 的实现全屏退出后高度异常
    if (element.localName == 'iframe') {
      final iframe = buildIframe(context: context, element: element);
      if (iframe != null) return iframe;
    }

    // 处理 Discourse 懒加载视频 (div.lazy-video-container)
    if (element.localName == 'div' && element.classes.contains('lazy-video-container')) {
      return buildLazyVideo(
        context: context,
        theme: theme,
        element: element,
        linkCounts: widget.linkCounts,
      );
    }

    // 屏蔽 Discourse Lightbox 的元数据区域和 UI 图标
    if (element.classes.contains('meta') ||
        element.classes.contains('d-icon')) {
      return const SizedBox.shrink();
    }

    // 内联 SVG 渲染
    if (element.localName == 'svg') {
      return _buildInlineSvg(element);
    }

    // 附件链接 (a.attachment)：提取显示文件名，供下载时使用
    if (element.localName == 'a' && element.classes.contains('attachment')) {
      final href = element.attributes['href'];
      if (href != null) {
        final text = element.text.trim();
        if (text.isNotEmpty) {
          _attachmentFileNames[UrlHelper.resolveUrl(href)] = text;
        }
      }
      // 返回 null，保持默认渲染
    }

    // 用户提及链接 (a.mention)：直接 WidgetSpan 渲染
    if (element.localName == 'a' && element.classes.contains('mention')) {
      return buildMention(
        context: context,
        theme: theme,
        element: element,
        baseFontSize: widget.textStyle?.fontSize ?? 14.0,
      );
    }

    // Discourse 本地日期 (span.discourse-local-date)：转为设备本地时区渲染
    if (element.localName == 'span' &&
        element.classes.contains('discourse-local-date')) {
      final localDate = buildLocalDate(
        context: context,
        theme: theme,
        element: element,
        baseFontSize: widget.textStyle?.fontSize ?? 14.0,
      );
      if (localDate != null) return localDate;
    }

    // 链接点击数 (span.click-count)：直接 WidgetSpan 渲染
    if (element.localName == 'span' && element.classes.contains('click-count')) {
      final count = element.text.trim();
      final isDark = theme.brightness == Brightness.dark;

      return InlineCustomWidget(
        child: buildClickCountWidget(
          count: count,
          isDark: isDark,
        ),
      );
    }

    // 内联代码：通过扫描方案渲染背景

    // HTML 构建器：用于嵌套渲染
    // 用 ScanBoundary 包裹，阻止外层 overlay 扫描进入嵌套内容
    // 每个 DiscourseHtmlContent 自带独立的 CombinedDecoratorOverlay
    Widget htmlBuilder(String html, TextStyle? textStyle) {
      return ScanBoundary(
        child: DiscourseHtmlContent(
          html: html,
          compact: true,
          textStyle: textStyle,
          galleryImages: _galleryInfo.images,
          spoilerImageUrls: _galleryInfo.spoilerImageUrls,
          revealedImageUrls: _revealedImageUrls,
          onInternalLinkTap: widget.onInternalLinkTap,
          post: widget.post,
          topicId: widget.topicId,
          linkCounts: widget.linkCounts,
          mentionedUsers: widget.mentionedUsers,
          enableSelectionArea: widget.enableSelectionArea,
          enablePanguSpacing: widget.enablePanguSpacing,
          screenshotMode: widget.screenshotMode,
          onQuoteImage: widget.onQuoteImage,
        ),
      );
    }

    // 处理投票块 (div.poll)
    if (element.localName == 'div' && element.classes.contains('poll')) {
      if (widget.post != null) {
        return buildPoll(
          context: context,
          theme: theme,
          element: element,
          post: widget.post!,
        );
      }
      return const SizedBox.shrink();
    }

    // 处理 Policy 块 (div.policy)
    if (element.localName == 'div' && element.classes.contains('policy')) {
      if (widget.post != null) {
        return buildPolicy(
          context: context,
          theme: theme,
          element: element,
          post: widget.post!,
          htmlBuilder: htmlBuilder,
        );
      }
      return const SizedBox.shrink();
    }

    // 处理 Discourse 图片网格 (div.d-image-grid)
    if (element.localName == 'div' && element.classes.contains('d-image-grid')) {
      return buildImageGrid(
        context: context,
        theme: theme,
        element: element,
        galleryInfo: _galleryInfo,
      );
    }

    // 处理 table：自定义渲染避免布局问题
    if (element.localName == 'table') {
      return buildTable(
        context: context,
        theme: theme,
        element: element,
        galleryImages: _galleryInfo.images,
        screenshotMode: widget.screenshotMode,
      );
    }

    // 处理 Discourse 回复引用块 (aside.quote)
    if (element.localName == 'aside' && element.classes.contains('quote')) {
      return buildQuoteCard(
        context: context,
        theme: theme,
        element: element,
        htmlBuilder: htmlBuilder,
      );
    }

    // 处理 Discourse 链接卡片 (aside.onebox)
    if (element.localName == 'aside' && element.classes.contains('onebox')) {
      return buildOneboxCard(
        context: context,
        theme: theme,
        element: element,
        linkCounts: widget.linkCounts,
      );
    }

    // 处理 Discourse Chat Transcript (div.chat-transcript)
    if (isChatTranscript(element)) {
      return buildChatTranscript(
        context: context,
        theme: theme,
        element: element,
        htmlBuilder: htmlBuilder,
      );
    }

    // 处理普通引用块 (可能是 Obsidian Callout)
    if (element.localName == 'blockquote') {
      return buildBlockquote(
        context: context,
        theme: theme,
        element: element,
        htmlBuilder: htmlBuilder,
      );
    }

    // 处理代码块
    if (element.localName == 'pre') {
      final codeElements = element.getElementsByTagName('code');
      if (codeElements.isNotEmpty) {
        return buildCodeBlock(
          context: context,
          theme: theme,
          codeElement: codeElements.first,
          screenshotMode: widget.screenshotMode,
        );
      }
    }

    // 处理 Spoiler 隐藏内容
    if (element.classes.contains('spoiler') || element.classes.contains('spoiled')) {
      // span.spoiler：返回 null 让文本正常渲染（样式由 customStylesBuilder 设置）
      // 粒子效果由外层的 SpoilerOverlay 通过 RenderTree 扫描实现
      if (element.localName == 'span') {
        return null;
      }
      // div.spoiler 等块级元素使用块级方案
      final innerHtml = element.innerHtml as String;
      final spoilerId = 'block_spoiler_${innerHtml.hashCode}';
      final isRevealed = _revealedSpoilers.contains(spoilerId);

      return buildSpoiler(
        context: context,
        theme: theme,
        element: element,
        htmlBuilder: htmlBuilder,
        textStyle: widget.textStyle,
        isRevealed: isRevealed,
        onReveal: () {
          setState(() {
            _revealedSpoilers.add(spoilerId);
            // 提取 spoiler 内的 lightbox 图片 URL，加入已揭示集合
            _extractSpoilerImageUrls(element);
          });
        },
      );
    }

    // 处理 details 折叠块
    if (element.localName == 'details') {
      return buildDetails(
        context: context,
        theme: theme,
        element: element,
        htmlBuilder: htmlBuilder,
      );
    }

    // 处理脚注引用 (sup.footnote-ref)
    if (element.localName == 'sup' && element.classes.contains('footnote-ref')) {
      final footnoteRef = buildFootnoteRef(
        context: context,
        theme: theme,
        element: element,
        fullHtml: widget.fullHtml ?? widget.html,
        galleryImages: _galleryInfo.images,
      );
      return InlineCustomWidget(child: footnoteRef);
    }

    // 处理脚注分隔线 (.footnotes-sep) - 隐藏
    if (element.localName == 'hr' && element.classes.contains('footnotes-sep')) {
      return buildFootnotesSep();
    }

    // 处理脚注列表 (section.footnotes / ol.footnotes-list)
    if (element.localName == 'section' && element.classes.contains('footnotes')) {
      return buildFootnotesList(
        context: context,
        theme: theme,
        element: element,
        htmlBuilder: htmlBuilder,
      );
    }
    if (element.localName == 'ol' && element.classes.contains('footnotes-list')) {
      return buildFootnotesList(
        context: context,
        theme: theme,
        element: element,
        htmlBuilder: htmlBuilder,
      );
    }

    // 处理块级数学公式 (div.math)
    if (element.localName == 'div' && element.classes.contains('math')) {
      return buildMathBlock(
        context: context,
        theme: theme,
        element: element,
      );
    }

    // 处理行内数学公式 (span.math)
    if (element.localName == 'span' && element.classes.contains('math')) {
      return buildInlineMath(
        context: context,
        theme: theme,
        element: element,
      );
    }

    // 处理分割线
    if (element.localName == 'hr') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      );
    }

    // 带点击数的链接：点击数已通过 _injectClickCounts 注入为 span.click-count
    // 使用 CSS 样式渲染，回归文档流

    return null;
  }

  /// 构建内联 SVG widget
  ///
  /// 区分 Discourse UI 图标（.d-icon）和内容 SVG：
  /// - 没有 viewBox 且没有 width/height 的小图标 → SizedBox.shrink()
  /// - 有 viewBox 或有 width/height 的内容 SVG → 用 jovial_svg 渲染
  Widget _buildInlineSvg(dynamic element) {
    // 没有 viewBox 且没有尺寸属性的 SVG 视为 UI 图标，不渲染
    final viewBox = element.attributes['viewBox'] as String?;
    final widthAttr = element.attributes['width'] as String?;
    final heightAttr = element.attributes['height'] as String?;
    if (viewBox == null && widthAttr == null && heightAttr == null) {
      return const SizedBox.shrink();
    }

    try {
      final svgString = element.outerHtml as String;
      final si = ScalableImage.fromSvgString(svgString, warnF: (_) {});
      final viewport = si.viewport;

      // viewport 无效则 fallback
      if (viewport.width <= 0 || viewport.height <= 0) {
        return const SizedBox.shrink();
      }

      final aspectRatio = viewport.width / viewport.height;

      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width - 32;
          final displayWidth = availableWidth;
          final displayHeight = displayWidth / aspectRatio;

          return SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: ScalableImageWidget(si: si, fit: BoxFit.contain),
          );
        },
      );
    } catch (_) {
      // 解析失败 fallback
      return const SizedBox.shrink();
    }
  }

  /// 提取 spoiler 元素内的 lightbox 图片 URL，添加到已揭示集合
  void _extractSpoilerImageUrls(dynamic element) {
    final lightboxLinks = element.querySelectorAll('a.lightbox');
    for (final anchor in lightboxLinks) {
      final href = anchor.attributes['href'] as String?;
      if (href != null && href.isNotEmpty) {
        final url = UrlHelper.resolveUrlWithCdn(href);
        _revealedImageUrls.add(url);
      }
    }
  }

  /// 格式化点击数
  String _formatClickCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}

/// 在 isolate 中批量执行 Pangu 混排
List<String> _batchPanguInIsolate(List<String> htmlList) {
  final pangu = Pangu();
  return htmlList.map((html) => pangu.spacingText(html)).toList();
}
