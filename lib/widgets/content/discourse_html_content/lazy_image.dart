import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../lazy_load_scope.dart';
import '../../common/hero_image.dart';

/// 懒加载图片组件
///
/// 只有当图片进入视口时才开始加载，减少内存和网络占用
class LazyImage extends StatefulWidget {
  final ImageProvider imageProvider;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String heroTag;
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  /// 右键回调（桌面端）
  final GestureTapUpCallback? onSecondaryTapUp;

  /// 缓存 key（用于判断是否已加载，默认使用 heroTag）
  final String? cacheKey;

  /// 可见比例阈值，超过此值开始加载（0.0 - 1.0）
  final double visibilityThreshold;

  const LazyImage({
    super.key,
    required this.imageProvider,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    required this.heroTag,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.cacheKey,
    this.visibilityThreshold = 0.01,
  });

  @override
  State<LazyImage> createState() => _LazyImageState();
}

class _LazyImageState extends State<LazyImage> {
  bool _shouldLoad = false;
  bool _initialized = false;

  String get _cacheKey => widget.cacheKey ?? widget.heroTag;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      // 检查作用域缓存
      if (LazyLoadScope.isLoaded(context, _cacheKey)) {
        _shouldLoad = true;
      }
    }
  }

  void _triggerLoad() {
    if (!_shouldLoad) {
      LazyLoadScope.markLoaded(context, _cacheKey);
      setState(() => _shouldLoad = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 如果已加载过，直接显示图片
    if (_shouldLoad) {
      return _buildImageWidget(theme);
    }

    // 静态占位符（无动画，避免多个 AnimationController 开销）
    Widget placeholder = _buildStaticPlaceholder(theme);

    // 使用 VisibilityDetector 检测可见性
    return VisibilityDetector(
      key: Key('lazy-image-${widget.heroTag}'),
      onVisibilityChanged: (info) {
        if (!_shouldLoad && info.visibleFraction >= widget.visibilityThreshold) {
          _triggerLoad();
        }
      },
      child: placeholder,
    );
  }

  Widget _buildStaticPlaceholder(ThemeData theme) {
    Widget placeholder = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
        borderRadius: BorderRadius.circular(8),
      ),
    );

    if (widget.width != null && widget.height != null && widget.height! > 0) {
      return AspectRatio(
        aspectRatio: widget.width! / widget.height!,
        child: placeholder,
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height ?? 200,
      child: placeholder,
    );
  }

  Widget _buildImageWidget(ThemeData theme) {
    final imageChild = Image(
      image: widget.imageProvider,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;

        // 加载中显示进度指示器
        return Container(
          width: widget.width,
          height: widget.height ?? 200,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha:0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: widget.width,
          height: widget.height ?? 200,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha:0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.broken_image,
            color: theme.colorScheme.outline,
            size: 32,
          ),
        );
      },
    );

    // 使用 HeroImage 封装 Hero 动画及可见性控制
    Widget imageWidget = HeroImage(
      heroTag: widget.heroTag,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTapUp: widget.onSecondaryTapUp,
      child: imageChild,
    );

    if (widget.width != null && widget.height != null && widget.height! > 0) {
      return AspectRatio(
        aspectRatio: widget.width! / widget.height!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}
