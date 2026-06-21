import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import '../../../pages/image_viewer_page.dart';
import '../../../services/discourse/discourse_service.dart';
import '../../../utils/url_helper.dart';

/// 画廊信息类
/// 同时保存缩略图 URL（用于匹配）和原图 URL（用于显示）
class GalleryInfo {
  /// 原图 URL 列表（用于画廊显示）
  final List<String> originalUrls;

  /// 每张图片的文件名列表（来自 lightbox title，可能为 null）
  final List<String?> filenames;

  /// 缩略图 URL 到索引的映射（用于快速查找）
  final Map<String, int> _thumbnailToIndex;

  /// spoiler 内的图片 URL 集合（揭示前不在画廊中显示）
  final Set<String> _spoilerImageUrls;

  /// 全局 LRU 缓存，避免对同一 HTML 重复执行 DOM 解析
  static final Map<(int, int), GalleryInfo> _cache = {};
  static const int _maxCacheSize = 100;

  GalleryInfo._({
    required this.originalUrls,
    required Map<String, int> thumbnailToIndex,
    List<String?>? filenames,
    Set<String>? spoilerImageUrls,
  })  : _thumbnailToIndex = thumbnailToIndex,
        filenames = filenames ?? List.filled(originalUrls.length, null),
        _spoilerImageUrls = spoilerImageUrls ?? {};

  /// 获取指定索引的文件名
  String? getFilename(int index) {
    if (index >= 0 && index < filenames.length) return filenames[index];
    return null;
  }

  /// 获取可见图片的索引列表（排除未揭示 spoiler 中的图片）
  /// [revealedImageUrls] 为已揭示的 spoiler 图片 URL 集合
  List<int> getVisibleIndices(Set<String> revealedImageUrls) {
    if (_spoilerImageUrls.isEmpty) {
      return List.generate(originalUrls.length, (i) => i);
    }
    return [
      for (int i = 0; i < originalUrls.length; i++)
        if (!_spoilerImageUrls.contains(originalUrls[i]) ||
            revealedImageUrls.contains(originalUrls[i]))
          i,
    ];
  }

  /// 从 HTML 提取画廊信息
  /// 收集所有 a.lightbox 内的图片（标记 spoiler 内的，揭示后才加入可见画廊）
  /// 结果会被全局 LRU 缓存，相同 HTML 不会重复解析 DOM
  static GalleryInfo fromHtml(String html) {
    final cacheKey = (html.hashCode, html.length);

    // 检查缓存
    final cached = _cache[cacheKey];
    if (cached != null) {
      // LRU: 移到末尾
      _cache.remove(cacheKey);
      _cache[cacheKey] = cached;
      return cached;
    }

    final List<String> originalUrls = [];
    final List<String?> filenames = [];
    final Map<String, int> thumbnailToIndex = {};
    final Set<String> spoilerImageUrls = {};

    final doc = html_parser.parseFragment(html);

    // 查找所有 a.lightbox 元素
    final lightboxLinks = doc.querySelectorAll('a.lightbox');

    for (final anchor in lightboxLinks) {
      // 检查是否在 spoiler 内
      bool inSpoiler = false;
      var parent = anchor.parent;
      while (parent != null) {
        if (parent.classes.contains('spoiler') ||
            parent.classes.contains('spoiled')) {
          inSpoiler = true;
          break;
        }
        parent = parent.parent;
      }

      // 原图 URL：从 a.lightbox 的 href 获取
      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) continue;

      var originalUrl = UrlHelper.resolveUrlWithCdn(href);

      // 文件名：从 a.lightbox 的 title 获取
      final filename = anchor.attributes['title'];

      // 缩略图 URL：从内部 img 的 src 获取
      final img = anchor.querySelector('img');
      var thumbnailUrl = img?.attributes['src'];
      if (thumbnailUrl != null) {
        thumbnailUrl = UrlHelper.resolveUrlWithCdn(thumbnailUrl);
      }

      final index = originalUrls.length;
      originalUrls.add(originalUrl);
      filenames.add(filename);

      // 标记 spoiler 内的图片
      if (inSpoiler) {
        spoilerImageUrls.add(originalUrl);
      }

      // 用缩略图和原图 URL 都作为索引 key
      if (thumbnailUrl != null) {
        thumbnailToIndex[thumbnailUrl] = index;
        // 缩略图转原图后的 URL 也加入（处理 optimized → original 的情况）
        final thumbOriginal =
            DiscourseImageUtils.getOriginalUrl(thumbnailUrl);
        if (thumbOriginal != thumbnailUrl) {
          thumbnailToIndex[thumbOriginal] = index;
        }
      }
      thumbnailToIndex[originalUrl] = index;
    }

    final result = GalleryInfo._(
      originalUrls: originalUrls,
      thumbnailToIndex: thumbnailToIndex,
      filenames: filenames,
      spoilerImageUrls: spoilerImageUrls,
    );

    // 存入全局 LRU 缓存
    while (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = result;

    return result;
  }

  /// 从外部传入的图片列表构建 GalleryInfo
  /// [spoilerImageUrls] 可选，标记哪些图片在 spoiler 内
  static GalleryInfo fromImages(List<String> images, {Set<String>? spoilerImageUrls}) {
    final Map<String, int> thumbnailToIndex = {};

    for (var i = 0; i < images.length; i++) {
      final url = images[i];
      thumbnailToIndex[url] = i;
      // 同时添加原图 URL 作为 key
      final originalUrl = DiscourseImageUtils.getOriginalUrl(url);
      if (originalUrl != url) {
        thumbnailToIndex[originalUrl] = i;
      }
    }

    return GalleryInfo._(
      originalUrls: images,
      thumbnailToIndex: thumbnailToIndex,
      spoilerImageUrls: spoilerImageUrls,
    );
  }

  /// 根据任意格式的图片 URL 查找索引
  /// 会尝试多种 URL 变体匹配
  int? findIndex(String imageUrl) {
    // 1. 直接查找
    if (_thumbnailToIndex.containsKey(imageUrl)) {
      return _thumbnailToIndex[imageUrl];
    }
    
    // 2. 尝试 resolveUrl 后查找（处理相对路径）
    final resolvedUrl = UrlHelper.resolveUrlWithCdn(imageUrl);
    if (_thumbnailToIndex.containsKey(resolvedUrl)) {
      return _thumbnailToIndex[resolvedUrl];
    }
    
    // 3. 尝试转换为原图 URL 后查找
    final originalUrl = DiscourseImageUtils.getOriginalUrl(imageUrl);
    if (_thumbnailToIndex.containsKey(originalUrl)) {
      return _thumbnailToIndex[originalUrl];
    }
    
    // 4. resolvedUrl 转换为原图后查找
    final resolvedOriginalUrl = DiscourseImageUtils.getOriginalUrl(resolvedUrl);
    if (_thumbnailToIndex.containsKey(resolvedOriginalUrl)) {
      return _thumbnailToIndex[resolvedOriginalUrl];
    }
    
    return null;
  }

  /// spoiler 内的图片 URL 集合（公开供传递）
  Set<String> get spoilerImageUrls => _spoilerImageUrls;

  /// 获取原图 URL 列表（用于传递给画廊查看器）
  List<String> get images => originalUrls;
  
  /// 生成画廊 Hero tags
  List<String> get heroTags => DiscourseImageUtils.generateGalleryHeroTags(originalUrls);
  
  /// 获取指定索引的原图 URL
  String? getOriginalUrl(int index) {
    if (index >= 0 && index < originalUrls.length) {
      return originalUrls[index];
    }
    return null;
  }
}

/// Discourse 图片工具类
/// 集中处理图片 URL 转换、原图查找、查看器打开等通用逻辑
class DiscourseImageUtils {
  DiscourseImageUtils._();

  /// upload:// 短链接解析缓存（全局共享，仅缓存成功结果）
  /// 失败不缓存：临时性失败（速率限制、网络抖动）可在下次 build 时重试，
  /// 否则一次失败会被永久缓存为 null，即使后续 lookup-urls 成功也一直显示裂图
  static final Map<String, String> _uploadUrlCache = {};

  /// 进行中的解析请求（同一短链共享同一个 Future，避免并发解析互相覆盖结果）
  static final Map<String, Future<String?>> _inflightResolves = {};

  /// 检查是否是 upload:// 短链接
  static bool isUploadUrl(String url) => url.startsWith('upload://');

  /// 从缓存中获取已解析的 URL
  /// 返回 null 表示未缓存，需要异步解析
  static String? getCachedUploadUrl(String shortUrl) {
    if (!isUploadUrl(shortUrl)) return shortUrl;
    return _uploadUrlCache[shortUrl];
  }

  /// 异步解析 upload:// 短链接并缓存结果
  static Future<String?> resolveUploadUrl(String shortUrl) {
    if (!isUploadUrl(shortUrl)) return Future.value(shortUrl);

    final cached = _uploadUrlCache[shortUrl];
    if (cached != null) return Future.value(cached);

    return _inflightResolves[shortUrl] ??= _doResolveUploadUrl(shortUrl);
  }

  static Future<String?> _doResolveUploadUrl(String shortUrl) async {
    try {
      final resolved = await DiscourseService().resolveShortUrl(shortUrl);
      if (resolved != null) {
        _uploadUrlCache[shortUrl] = resolved;
      }
      return resolved;
    } catch (e) {
      debugPrint('[DiscourseImageUtils] Failed to resolve upload url: $shortUrl, error: $e');
      return null;
    } finally {
      _inflightResolves.remove(shortUrl);
    }
  }

  /// 将优化图 URL 转换为原图 URL
  ///
  /// Discourse 优化图路径: .../uploads/default/optimized/4X/7/5/c/75c...dc_2_690x270.png
  /// 原图路径:            .../uploads/default/original/4X/7/5/c/75c...dc.png
  static String getOriginalUrl(String optimizedUrl) {
    if (!optimizedUrl.contains('/optimized/')) {
      return optimizedUrl;
    }

    try {
      // 1. 替换路径段
      var original = optimizedUrl.replaceFirst('/optimized/', '/original/');

      // 2. 移除分辨率后缀 (e.g. _2_690x270)
      final regex = RegExp(r'_\d+_\d+x\d+(?=\.[a-zA-Z0-9]+$)');
      if (regex.hasMatch(original)) {
        original = original.replaceAll(regex, '');
      }

      return original;
    } catch (e) {
      debugPrint('Error converting to original url: $e');
      return optimizedUrl;
    }
  }

  /// 从 DOM 元素中查找原图 URL
  /// 向上遍历 DOM 树，查找 lightbox 链接
  static String? findOriginalImageUrl(dynamic img) {
    dynamic current = img;

    // 向上遍历最多 5 层
    for (int i = 0; i < 5 && current != null; i++) {
      // 检查当前元素是否是 a 标签
      if (current.localName == 'a') {
        final href = current.attributes['href'] as String?;
        if (href != null && href.isNotEmpty) {
          // 检查是否是 lightbox 链接（通常指向原图）
          final classes = (current.classes as Iterable<String>?)?.toList() ?? [];
          if (classes.contains('lightbox') || href.contains('/original/')) {
            return href;
          }
          // 如果 href 指向图片文件，也返回
          if (isImageUrl(href)) {
            return href;
          }
        }
      }

      // 检查是否在 lightbox-wrapper 内
      if (current.localName == 'div' || current.localName == 'span') {
        final classes = (current.classes as Iterable<String>?)?.toList() ?? [];
        if (classes.contains('lightbox-wrapper')) {
          // 在 lightbox-wrapper 内查找 a.lightbox
          final anchors = current.getElementsByTagName('a');
          for (final a in anchors) {
            final aClasses = (a.classes as Iterable<String>?)?.toList() ?? [];
            if (aClasses.contains('lightbox')) {
              final href = a.attributes['href'] as String?;
              if (href != null && href.isNotEmpty) {
                return href;
              }
            }
          }
        }
      }

      current = current.parent;
    }

    return null;
  }

  /// 检查 URL 是否指向图片
  static bool isImageUrl(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.endsWith('.jpg') ||
        lowerUrl.endsWith('.jpeg') ||
        lowerUrl.endsWith('.png') ||
        lowerUrl.endsWith('.gif') ||
        lowerUrl.endsWith('.webp') ||
        lowerUrl.endsWith('.avif') ||
        lowerUrl.contains('/uploads/') ||
        lowerUrl.contains('/original/');
  }


  /// 打开图片查看器（过滤不可见的 spoiler 图片）
  /// 根据 [revealedImageUrls] 过滤画廊，只显示非 spoiler 图片和已揭示的 spoiler 图片
  static void openViewerFiltered({
    required BuildContext context,
    required GalleryInfo galleryInfo,
    required Set<String> revealedImageUrls,
    required String imageUrl,
    required String heroTag,
    required int fullGalleryIndex,
    String? thumbnailUrl,
  }) {
    final allImages = galleryInfo.images;
    final allHeroTags = galleryInfo.heroTags;
    final visibleIndices = galleryInfo.getVisibleIndices(revealedImageUrls);
    final visibleIndex = visibleIndices.indexOf(fullGalleryIndex);

    openViewer(
      context: context,
      imageUrl: getOriginalUrl(imageUrl),
      heroTag: heroTag,
      galleryImages: visibleIndices.map((i) => getOriginalUrl(allImages[i])).toList(),
      heroTags: visibleIndices.map((i) => allHeroTags[i]).toList(),
      initialIndex: visibleIndex >= 0 ? visibleIndex : 0,
      thumbnailUrl: thumbnailUrl ?? imageUrl,
      thumbnailUrls: visibleIndices.map((i) => allImages[i]).toList(),
      filenames: visibleIndices.map((i) => galleryInfo.filenames[i]).toList(),
    );
  }

  /// 打开图片查看器
  static void openViewer({
    required BuildContext context,
    required String imageUrl,
    required String heroTag,
    String? thumbnailUrl,
    List<String>? galleryImages,
    List<String>? thumbnailUrls,
    List<String>? heroTags,
    int initialIndex = 0,
    bool enableShare = true,
    List<String?>? filenames,
  }) {
    ImageViewerPage.open(
      context,
      imageUrl,
      heroTag: heroTag,
      galleryImages: galleryImages,
      heroTags: heroTags,
      initialIndex: initialIndex,
      enableShare: enableShare,
      thumbnailUrl: thumbnailUrl,
      thumbnailUrls: thumbnailUrls,
      filenames: filenames,
    );
  }

  /// 生成画廊 Hero Tag
  static String generateGalleryHeroTag(List<String> galleryImages, int index) {
    final galleryHash = Object.hashAll(galleryImages);
    return "gallery_${galleryHash}_$index";
  }

  /// 生成画廊所有 Hero Tags
  static List<String> generateGalleryHeroTags(List<String> galleryImages) {
    final galleryHash = Object.hashAll(galleryImages);
    return List.generate(
      galleryImages.length,
      (i) => "gallery_${galleryHash}_$i",
    );
  }
}

