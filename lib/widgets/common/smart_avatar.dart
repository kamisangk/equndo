import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jovial_svg/jovial_svg.dart';
import '../../services/discourse_cache_manager.dart';
import '../../utils/svg_utils.dart';

/// 智能头像组件
///
/// 使用 CachedNetworkImage 加载图片，自动支持 GIF 动画。
/// 静态头像会先检测内容是否为 SVG，避免伪装成 PNG 的 SVG 进入位图解码器。
class SmartAvatar extends StatefulWidget {
  final String? imageUrl;
  final double radius;
  final String? fallbackText;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final BoxBorder? border;

  const SmartAvatar({
    super.key,
    this.imageUrl,
    required this.radius,
    this.fallbackText,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
  });

  @override
  State<SmartAvatar> createState() => _SmartAvatarState();
}

class _SmartAvatarState extends State<SmartAvatar> {
  static final DiscourseCacheManager _cacheManager = DiscourseCacheManager();

  Future<String?>? _svgProbeFuture;

  @override
  void initState() {
    super.initState();
    _svgProbeFuture = _createSvgProbeFuture(widget.imageUrl);
  }

  @override
  void didUpdateWidget(SmartAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _svgProbeFuture = _createSvgProbeFuture(widget.imageUrl);
    }
  }

  Future<String?>? _createSvgProbeFuture(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty || isNativeAnimatedUrl(imageUrl)) {
      return null;
    }
    return _loadSvgContentIfPresent(imageUrl);
  }

  Future<String?> _loadSvgContentIfPresent(String imageUrl) async {
    try {
      final file = await _cacheManager.getSingleFile(imageUrl);
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || !SvgUtils.isSvgBytes(bytes)) return null;
      return SvgUtils.sanitize(SvgUtils.decodeSvgBytes(bytes));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 默认透明背景，只有在需要 fallback 时才用主题色
    final bgColor = widget.backgroundColor ?? Colors.transparent;
    final fgColor =
        widget.foregroundColor ?? theme.colorScheme.onPrimaryContainer;

    // 计算边框宽度，边框包含在 radius 内部
    double borderWidth = 0;
    if (widget.border is Border) {
      borderWidth = (widget.border as Border).top.width;
    }
    final innerRadius = widget.radius - borderWidth;
    final innerSize = innerRadius * 2;

    Widget child;
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      child = _buildFallback(fgColor, innerRadius);
    } else if (isNativeAnimatedUrl(widget.imageUrl!)) {
      // 动图(GIF/APNG/动画 WebP)走 native_animated_image Rust pipeline,
      // 绕开 Flutter Skia multi_frame_codec 的 #85831 bug
      child = Image(
        image: discourseImageProvider(widget.imageUrl!),
        width: innerSize,
        height: innerSize,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (context, displayChild, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return displayChild;
          return _buildLoading(fgColor, innerRadius);
        },
        errorBuilder: (context, error, stack) {
          // 动图链路出错(网络 / Rust 解码失败),退化到字母 fallback
          return _buildFallback(fgColor, innerRadius);
        },
      );
    } else {
      child = FutureBuilder<String?>(
        future: _svgProbeFuture,
        builder: (context, snapshot) {
          final svgContent = snapshot.data;
          if (svgContent != null) {
            return _buildSvg(svgContent, innerSize) ??
                _buildFallback(fgColor, innerRadius);
          }

          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoading(fgColor, innerRadius);
          }

          // 静态图使用 CachedNetworkImage，解码失败时再次嗅探 SVG 兜底。
          return CachedNetworkImage(
            imageUrl: widget.imageUrl!,
            cacheManager: _cacheManager,
            width: innerSize,
            height: innerSize,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            fadeOutDuration: const Duration(milliseconds: 150),
            placeholder: (context, url) => _buildLoading(fgColor, innerRadius),
            errorWidget: (context, url, error) => _SvgFallbackBuilder(
              imageUrl: widget.imageUrl!,
              cacheManager: _cacheManager,
              size: innerSize,
              fallback: _buildFallback(fgColor, innerRadius),
            ),
          );
        },
      );
    }

    // 使用 BoxDecoration + shape: circle 确保 Hero 动画时保持圆形
    // ClipOval 在 Hero 飞行时不会被正确应用
    Widget avatar = Container(
      width: innerRadius * 2,
      height: innerRadius * 2,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    // 如果有边框，在外层添加，总尺寸保持 radius * 2
    if (widget.border != null) {
      avatar = Container(
        width: widget.radius * 2,
        height: widget.radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: widget.border,
        ),
        alignment: Alignment.center,
        child: avatar,
      );
    }

    return avatar;
  }

  Widget? _buildSvg(String svgContent, double size) {
    try {
      final si = ScalableImage.fromSvgString(svgContent, warnF: (_) {});
      return SizedBox(
        width: size,
        height: size,
        child: ScalableImageWidget(si: si, fit: BoxFit.cover),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildLoading(Color fgColor, double radius) {
    return Center(
      child: SizedBox(
        width: radius * 0.6,
        height: radius * 0.6,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: fgColor.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildFallback(Color fgColor, double radius) {
    if (widget.fallbackText != null && widget.fallbackText!.isNotEmpty) {
      return Center(
        child: Text(
          widget.fallbackText![0].toUpperCase(),
          style: TextStyle(
            color: fgColor,
            fontWeight: FontWeight.w600,
            fontSize: radius * 0.8,
          ),
        ),
      );
    }
    return Center(
      child: Icon(Icons.person, size: radius, color: fgColor),
    );
  }
}

/// SVG 检测和渲染组件
///
/// 当 CachedNetworkImage 解码失败时，检测缓存文件是否为 SVG
class _SvgFallbackBuilder extends StatefulWidget {
  final String imageUrl;
  final DiscourseCacheManager cacheManager;
  final double size;
  final Widget fallback;

  const _SvgFallbackBuilder({
    required this.imageUrl,
    required this.cacheManager,
    required this.size,
    required this.fallback,
  });

  @override
  State<_SvgFallbackBuilder> createState() => _SvgFallbackBuilderState();
}

class _SvgFallbackBuilderState extends State<_SvgFallbackBuilder> {
  String? _svgContent;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkForSvg();
  }

  Future<void> _checkForSvg() async {
    try {
      final file = await widget.cacheManager.getSingleFile(widget.imageUrl);
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty || !mounted) return;

      if (SvgUtils.isSvgBytes(bytes)) {
        final svgString = SvgUtils.sanitize(SvgUtils.decodeSvgBytes(bytes));
        if (mounted) {
          setState(() {
            _svgContent = svgString;
            _checked = true;
          });
        }
      } else {
        if (mounted) {
          setState(() => _checked = true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_svgContent != null) {
      try {
        final si = ScalableImage.fromSvgString(_svgContent!, warnF: (_) {});
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: ScalableImageWidget(si: si, fit: BoxFit.cover),
        );
      } catch (_) {
        return widget.fallback;
      }
    }

    if (!_checked) {
      // 检测中，显示空白避免闪烁
      return const SizedBox.shrink();
    }

    return widget.fallback;
  }
}
