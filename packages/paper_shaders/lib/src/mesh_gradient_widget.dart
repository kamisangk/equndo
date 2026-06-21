import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'mesh_gradient_painter.dart';

/// GPU shader 驱动的 MeshGradient 动画背景
///
/// 多个颜色点各自按独立轨迹运动，通过距离倒数加权混合产生平滑流动的渐变。
/// 支持有机扭曲（distortion）和旋涡（swirl）效果。
class MeshGradient extends StatefulWidget {
  const MeshGradient({
    super.key,
    required this.colors,
    this.backgroundColor = const Color(0xFF000000),
    this.distortion = 0.8,
    this.swirl = 0.1,
    this.speed = 1.0,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.child,
  }) : assert(colors.length >= 1 && colors.length <= 7);

  /// 渐变颜色列表（1-7 个），每个颜色点按独立轨迹运动
  final List<Color> colors;

  /// 背景颜色
  final Color backgroundColor;

  /// 有机扭曲强度 (0-1)
  final double distortion;

  /// 旋涡强度 (0-1)
  final double swirl;

  /// 动画速度倍数
  final double speed;

  /// 整体缩放
  final double scale;

  /// 旋转角度（度数）
  final double rotation;

  /// 水平偏移
  final double offsetX;

  /// 垂直偏移
  final double offsetY;

  /// 子组件（可叠加在渐变上方）
  final Widget? child;

  @override
  State<MeshGradient> createState() => _MeshGradientState();
}

class _MeshGradientState extends State<MeshGradient>
    with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  late Ticker _ticker;
  double _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'packages/paper_shaders/shaders/mesh_gradient.frag',
      );

      if (!mounted) return;

      setState(() {
        _program = program;
        _shader = _program!.fragmentShader();
      });
    } catch (e) {
      debugPrint('[MeshGradient] shader 加载失败: $e');
    }
  }

  void _onTick(Duration elapsed) {
    setState(() {
      _elapsed = elapsed.inMicroseconds / 1e6 * widget.speed;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;

    Widget content;
    if (shader == null) {
      content = ColoredBox(color: widget.backgroundColor);
    } else {
      content = CustomPaint(
        painter: MeshGradientPainter(
          shader: shader,
          time: _elapsed,
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
          colors: widget.colors,
          backgroundColor: widget.backgroundColor,
          distortion: widget.distortion,
          swirl: widget.swirl,
          scale: widget.scale,
          rotation: widget.rotation,
          offsetX: widget.offsetX,
          offsetY: widget.offsetY,
        ),
        size: Size.infinite,
      );
    }

    if (widget.child != null) {
      return RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            widget.child!,
          ],
        ),
      );
    }

    return RepaintBoundary(child: content);
  }
}
