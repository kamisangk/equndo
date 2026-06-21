import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'spoiler_particles.dart';

/// 块级 Spoiler 隐藏内容组件
class SpoilerContent extends StatefulWidget {
  final String innerHtml;
  final Widget Function(String html, TextStyle? textStyle) htmlBuilder;
  final TextStyle? textStyle;
  /// 外部传入的揭示状态
  final bool isRevealed;
  /// 揭示回调
  final VoidCallback? onReveal;

  const SpoilerContent({
    super.key,
    required this.innerHtml,
    required this.htmlBuilder,
    this.textStyle,
    this.isRevealed = false,
    this.onReveal,
  });

  @override
  State<SpoilerContent> createState() => _SpoilerContentState();
}

class _SpoilerContentState extends State<SpoilerContent>
    with SingleTickerProviderStateMixin {
  final SpoilerParticleSystem _particleSystem = SpoilerParticleSystem();
  Ticker? _ticker;
  Size? _size;
  Duration _lastTime = Duration.zero;
  // 本地揭示状态（点击后立即更新，不等待父组件重建）
  bool _isRevealed = false;

  @override
  void initState() {
    super.initState();
    _isRevealed = widget.isRevealed;
    if (!_isRevealed) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  @override
  void didUpdateWidget(SpoilerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同步外部状态
    if (widget.isRevealed && !_isRevealed) {
      _isRevealed = true;
      _ticker?.stop();
    } else if (!widget.isRevealed && _isRevealed) {
      // 从已揭示变为未揭示（重新渲染）
      _isRevealed = false;
      _particleSystem.clear();
      _size = null;
      _ticker ??= createTicker(_onTick);
      _ticker!.start();
    }
  }

  void _initParticles(Size size) {
    _size = size;
    _particleSystem.initForSize(size);
  }

  void _onTick(Duration elapsed) {
    if (!mounted || _isRevealed || _size == null) return;

    final dtMs = (elapsed - _lastTime).inMilliseconds.toDouble();
    _lastTime = elapsed;
    if (dtMs <= 0 || dtMs > 100) return;

    _particleSystem.update(dtMs);
    setState(() {});
  }

  void _reveal() {
    if (_isRevealed) return;
    _isRevealed = true;
    _ticker?.stop();
    widget.onReveal?.call();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = widget.htmlBuilder(widget.innerHtml, widget.textStyle);

    if (_isRevealed) {
      return content;
    }

    final isDark = theme.brightness == Brightness.dark;
    // 使用页面背景色，完全遮挡内部内容（包括 code 背景）
    final backgroundColor = theme.scaffoldBackgroundColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _reveal,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // 底层：隐藏内容（撑开尺寸）
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: content,
            ),
            // 粒子层（带不透明背景）
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  if (_size != size) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_isRevealed) {
                        _initParticles(size);
                      }
                    });
                  }

                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: SpoilerParticlePainter(
                        particles: _particleSystem.particles,
                        isDark: isDark,
                        backgroundColor: backgroundColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 构建块级 Spoiler 隐藏内容
Widget buildSpoiler({
  required BuildContext context,
  required ThemeData theme,
  required dynamic element,
  required Widget Function(String html, TextStyle? textStyle) htmlBuilder,
  TextStyle? textStyle,
  bool isRevealed = false,
  VoidCallback? onReveal,
}) {
  final innerHtml = element.innerHtml as String;

  return SpoilerContent(
    innerHtml: innerHtml,
    htmlBuilder: htmlBuilder,
    textStyle: textStyle,
    isRevealed: isRevealed,
    onReveal: onReveal,
  );
}
