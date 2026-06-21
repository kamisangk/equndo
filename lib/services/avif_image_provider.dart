import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_avif/flutter_avif.dart' as fa;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../l10n/s.dart';
import 'discourse_cache_manager.dart';

/// 限制并发 AVIF 解码数(thumbnail batch 场景)。
///
/// 当前调到 8 —— 用户机器 8+ 核常见(M 系列、骁龙 8 Gen 2+),平台 native
/// ImageIO 内存友好,并发 8 同屏内存峰值可控。完整解码路径(长按预览 /
/// 大图)已经在 loadImage 内 bypass 这个 semaphore。
final _avifDecodeSemaphore = _Semaphore(8);
final _pendingThumbnailTasks = <String, Future<void>>{};
final _knownThumbnailKeys = <String>{};

/// MultiFrameAvifCodec 的 key 序列(Rust 端 decoder 注册表按 key 索引)。
int _avifCodecKeySeq = 0;

/// AVIF 图片 Provider
///
/// 通过 CacheManager 下载/缓存文件，使用 [NativeAvifPlatform] 解码:
/// - iOS 16.4+/macOS 13.4+/Android 31+ → 系统 ImageIO/ImageDecoder(优)
/// - 其他平台 / 解码失败 → 纯 Rust zenavif(rav1d + zenavif-parse)
///
/// 支持单帧和多帧（动画）AVIF。
///
/// 当 [singleFrame] 且 [targetSize] 不为 null 时，走缩略图快速路径：
/// 首次解码后将缩放结果以 PNG 写入磁盘缓存，后续直接读取 PNG，
/// 完全绕过 AV1 解码，性能与普通 PNG 一致。
class AvifImageProvider extends ImageProvider<AvifImageProvider> {
  final String url;
  final double scale;
  final BaseCacheManager? cacheManager;

  /// 只解码第一帧，不播放动画。用于缩略图网格等场景。
  final bool singleFrame;

  /// 缩略图目标像素尺寸（长边）。
  /// 仅在 [singleFrame] 为 true 时生效：首次解码后缩放并以 PNG 缓存，
  /// 后续直接读取缓存 PNG，不再触发 AV1 解码。
  final int? targetSize;

  const AvifImageProvider(
    this.url, {
    this.scale = 1.0,
    this.cacheManager,
    this.singleFrame = false,
    this.targetSize,
  });

  static bool isAvifUrl(String url) {
    try {
      return Uri.parse(url).path.toLowerCase().endsWith('.avif');
    } catch (_) {
      return url.toLowerCase().endsWith('.avif');
    }
  }

  static String _thumbnailCacheKey(String url, int targetSize) {
    return 'avif_thumb:$targetSize:$url';
  }

  /// 预热 AVIF 缩略图缓存。
  ///
  /// 适合在列表展示前后台执行，避免首次进入视口时现场解码 AVIF。
  static Future<void> precacheThumbnail(
    String url, {
    required int targetSize,
    BaseCacheManager? cacheManager,
  }) async {
    if (!isAvifUrl(url)) return;

    final manager = cacheManager ?? DiscourseCacheManager();
    final thumbKey = _thumbnailCacheKey(url, targetSize);
    if (_knownThumbnailKeys.contains(thumbKey)) return;

    final cachedBytes = await _readCachedThumbnailBytes(manager, thumbKey);
    if (cachedBytes != null) return;

    final pending = _pendingThumbnailTasks[thumbKey];
    if (pending != null) {
      await pending;
      return;
    }

    final task = _warmThumbnail(
      manager: manager,
      url: url,
      targetSize: targetSize,
      thumbKey: thumbKey,
    );
    _pendingThumbnailTasks[thumbKey] = task;
    try {
      await task;
    } finally {
      _pendingThumbnailTasks.remove(thumbKey);
    }
  }

  @override
  Future<AvifImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<AvifImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    AvifImageProvider key,
    ImageDecoderCallback decode,
  ) {
    // 缩略图快速路径：PNG 缓存 → 内置 codec，不走 AV1
    if (key.singleFrame && key.targetSize != null) {
      return OneFrameImageStreamCompleter(
        _loadThumbnail(key).catchError(_evictOnError(key)),
      );
    }
    // 完整动画路径:流式逐帧解码(不预解全帧),见 completer 注释
    return _AvifAnimatedImageStreamCompleter(
      codecFactory: () => _createCodec(key),
      scale: key.scale,
      singleFrame: key.singleFrame,
      onError: () {
        scheduleMicrotask(() {
          PaintingBinding.instance.imageCache.evict(key);
        });
      },
    );
  }

  /// 从 cache manager 拉 bytes 并初始化增量解码器。
  ///
  /// `MultiFrameAvifCodec` 静态(avif)/ 动画(avis)AVIF 通吃:
  /// `initMemoryDecoder` 只做容器解析,帧由 `getNextFrame` 增量解出。
  static Future<fa.AvifCodec> _createCodec(AvifImageProvider key) async {
    final manager = key.cacheManager ?? DiscourseCacheManager();
    final file = await manager.getSingleFile(key.url);
    final bytes = await file.readAsBytes();
    final codec = fa.MultiFrameAvifCodec(
      key: _avifCodecKeySeq++,
      avifBytes: bytes,
    );
    await codec.ready();
    return codec;
  }

  /// 只解码第一帧并返回 [ui.Image]。
  ///
  /// **不要用 `fa.decodeAvif`**:它把全部帧解完才返回 —— 50 帧动图 sticker
  /// = 50 次 AV1 解码 + 50 次主 isolate RGBA 拷贝 + 50 个 ui.Image,缩略图
  /// 场景只留第 1 帧,其余全是浪费(这曾是"AVIF 单张 50-150ms"的大头)。
  /// 这里用 MultiFrameAvifCodec 增量解 1 帧后立即 dispose Rust 端 decoder。
  static Future<ui.Image> decodeFirstFrame(Uint8List bytes) async {
    final codec = fa.MultiFrameAvifCodec(
      key: _avifCodecKeySeq++,
      avifBytes: bytes,
    );
    try {
      await codec.ready();
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// 加载失败时把错误 completer 从 ImageCache 踢出,下次 rebuild 自动重试,
  /// 避免一次网络抖动 / 解码失败导致同 key 永久裂图(NetworkImage 同款行为)。
  static Never Function(Object, StackTrace) _evictOnError(
    AvifImageProvider key,
  ) {
    return (Object e, StackTrace st) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      Error.throwWithStackTrace(e, st);
    };
  }

  // ==================== 缩略图路径 ====================

  Future<ImageInfo> _loadThumbnail(AvifImageProvider key) async {
    final manager = key.cacheManager ?? DiscourseCacheManager();
    final thumbKey = _thumbnailCacheKey(key.url, key.targetSize!);

    // 快速路径：PNG 缓存命中 → 用 Flutter 内置 codec 解码（毫秒级）
    final cachedBytes = await _readCachedThumbnailBytes(manager, thumbKey);
    if (cachedBytes != null) {
      return _decodeThumbnailBytes(cachedBytes, key.scale);
    }

    // 首次解码提前走预热逻辑，避免重复解码同一缩略图。
    await precacheThumbnail(
      key.url,
      targetSize: key.targetSize!,
      cacheManager: manager,
    );
    final warmedBytes = await _readCachedThumbnailBytes(manager, thumbKey);
    if (warmedBytes != null) {
      return _decodeThumbnailBytes(warmedBytes, key.scale);
    }

    // 缓存写入失败时兜底：仍然现场解码并显示，避免出现空白。
    final displayImage = await _decodeThumbnailImage(
      manager: manager,
      url: key.url,
      targetSize: key.targetSize!,
    );
    unawaited(_cacheThumbnail(manager, thumbKey, displayImage));

    return ImageInfo(image: displayImage, scale: key.scale);
  }

  static Future<Uint8List?> _readCachedThumbnailBytes(
    BaseCacheManager manager,
    String thumbKey,
  ) async {
    final cached = await manager.getFileFromCache(thumbKey);
    if (cached == null) return null;
    _knownThumbnailKeys.add(thumbKey);
    return cached.file.readAsBytes();
  }

  static Future<ImageInfo> _decodeThumbnailBytes(
    Uint8List bytes,
    double scale,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecFromBuffer(buffer);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return ImageInfo(image: frame.image, scale: scale);
  }

  static Future<void> _warmThumbnail({
    required BaseCacheManager manager,
    required String url,
    required int targetSize,
    required String thumbKey,
  }) async {
    ui.Image? displayImage;
    try {
      displayImage = await _decodeThumbnailImage(
        manager: manager,
        url: url,
        targetSize: targetSize,
      );
      await _cacheThumbnail(manager, thumbKey, displayImage);
      _knownThumbnailKeys.add(thumbKey);
    } finally {
      displayImage?.dispose();
    }
  }

  static Future<ui.Image> _decodeThumbnailImage({
    required BaseCacheManager manager,
    required String url,
    required int targetSize,
  }) async {
    await _avifDecodeSemaphore.acquire();
    ui.Image srcImage;
    try {
      final file = await manager.getSingleFile(url);
      final bytes = await file.readAsBytes();
      // 只解第一帧 —— 缩略图不需要其余帧
      srcImage = await AvifImageProvider.decodeFirstFrame(bytes);
    } finally {
      _avifDecodeSemaphore.release();
    }

    if (srcImage.width > targetSize || srcImage.height > targetSize) {
      final resized = await _resize(srcImage, targetSize);
      srcImage.dispose();
      return resized;
    }
    return srcImage;
  }

  static Future<void> _cacheThumbnail(
    BaseCacheManager manager,
    String key,
    ui.Image image,
  ) async {
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        await manager.putFile(
          key,
          byteData.buffer.asUint8List(),
          fileExtension: 'png',
        );
      }
    } catch (_) {
      // 缓存写入失败不影响显示
    }
  }

  static Future<ui.Image> _resize(ui.Image src, int maxDim) async {
    final double ratio = src.width / src.height;
    final int w, h;
    if (ratio >= 1) {
      w = maxDim;
      h = (maxDim / ratio).round().clamp(1, maxDim);
    } else {
      h = maxDim;
      w = (maxDim * ratio).round().clamp(1, maxDim);
    }
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final pic = recorder.endRecording();
    final result = await pic.toImage(w, h);
    pic.dispose();
    return result;
  }

  // ==================== 完整解码路径 ====================
  //
  // 完整动画(长按预览、大图查看)走 [_AvifAnimatedImageStreamCompleter]
  // 流式逐帧解码,不再用 `fa.decodeAvif` 全帧预解(N 帧 RGBA 全驻内存 +
  // 首帧延迟 = 全量解码时间)。这条路不走 [_avifDecodeSemaphore] ——
  // 否则 sticker grid 的 thumbnail 解码会把用户长按预览的请求挤在队列
  // 后面,长按预览感知慢;单张交互场景也不存在 batch 内存爆炸问题。

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AvifImageProvider &&
        other.url == url &&
        other.scale == scale &&
        other.singleFrame == singleFrame &&
        other.targetSize == targetSize;
  }

  @override
  int get hashCode => Object.hash(url, scale, singleFrame, targetSize);

  @override
  String toString() => 'AvifImageProvider("$url", scale: $scale)';
}

/// AVIF 流式动画 Completer。
///
/// 与旧实现("`fa.decodeAvif` 全帧预解,Timer 轮播内存中的帧列表")的区别:
///
/// - **首帧立即显示**:容器解析完解出第 1 帧就 setImage,不等全量解码。
///   50 帧 512px 的 sticker 首帧延迟从"50 次 AV1 解码"降到 1 次。
/// - **内存只驻留当前帧**:逐帧 `getNextFrame` 按需解码(Rust 端到尾自动
///   回绕循环),不再 N 帧 RGBA 全驻内存(50 帧 ≈ 50 MB → ~1 MB)。
/// - **无监听时彻底释放**:flutter_avif 自带的 AvifImageStreamCompleter
///   从不调 `codec.dispose()`,Rust 端 decoder 注册表会随预览次数泄漏。
///   这里在最后一个 listener 移除时 dispose 解码器,重新监听时通过
///   [codecFactory] 重建(bytes 来自磁盘缓存,重建是毫秒级)。
class _AvifAnimatedImageStreamCompleter extends ImageStreamCompleter {
  _AvifAnimatedImageStreamCompleter({
    required Future<fa.AvifCodec> Function() codecFactory,
    required this.scale,
    this.singleFrame = false,
    VoidCallback? onError,
  })  : _codecFactory = codecFactory,
        _onError = onError;

  final Future<fa.AvifCodec> Function() _codecFactory;
  final double scale;

  /// 只播第一帧(provider 的 singleFrame 且无 targetSize 的场景)。
  final bool singleFrame;

  /// 初始化 / 解帧失败时回调(provider 用它做 ImageCache evict)。
  final VoidCallback? _onError;

  fa.AvifCodec? _codec;
  bool _starting = false;
  Timer? _timer;

  /// 暂停代号:每次 [_pause] 自增,使在途的异步解码结果作废。
  int _generation = 0;

  @override
  void addListener(ImageStreamListener listener) {
    final hadListeners = hasListeners;
    super.addListener(listener);
    if (!hadListeners) {
      _start();
    }
  }

  @override
  void removeListener(ImageStreamListener listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _pause();
    }
  }

  Future<void> _start() async {
    if (_codec != null || _starting) return;
    _starting = true;
    final gen = _generation;
    try {
      final codec = await _codecFactory();
      if (gen != _generation || !hasListeners) {
        // 等待初始化期间监听已撤销(预览关闭)
        codec.dispose();
        return;
      }
      _codec = codec;
      await _decodeAndEmitNext();
    } catch (error, stack) {
      _onError?.call();
      reportError(
        context: ErrorDescription(S.current.common_decodeAvif),
        exception: error,
        stack: stack,
      );
    } finally {
      _starting = false;
    }
  }

  Future<void> _decodeAndEmitNext() async {
    final codec = _codec;
    if (codec == null || !hasListeners) return;
    final gen = _generation;

    final fa.AvifFrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } catch (error, stack) {
      if (gen != _generation) return; // 已暂停,decoder 已释放,静默退出
      _onError?.call();
      reportError(
        context: ErrorDescription(S.current.common_decodeAvif),
        exception: error,
        stack: stack,
      );
      return;
    }
    if (gen != _generation || !hasListeners) {
      frame.image.dispose();
      return;
    }

    // setImage 接管 image 所有权(替换时基类会 dispose 旧帧)
    setImage(ImageInfo(image: frame.image, scale: scale));

    if (singleFrame || codec.frameCount <= 1) {
      // 静态图 / 单帧:不会再要帧,立即释放 Rust 端 decoder
      codec.dispose();
      _codec = null;
      return;
    }
    final delay = frame.duration.inMilliseconds > 0
        ? frame.duration
        : const Duration(milliseconds: 100);
    _timer?.cancel();
    _timer = Timer(delay, _decodeAndEmitNext);
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    _codec?.dispose();
    _codec = null;
  }
}

/// 简单的异步信号量，用于限制并发操作数
class _Semaphore {
  _Semaphore(this.maxCount);

  final int maxCount;
  int _current = 0;
  final _queue = <Completer<void>>[];

  Future<void> acquire() {
    if (_current < maxCount) {
      _current++;
      return SynchronousFuture(null);
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _current--;
    }
  }
}
