import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// MeshGradient 的 CustomPainter
///
/// 负责设置 shader uniform 并绘制。
/// 不需要噪声纹理 sampler（使用纯程序化噪声）。
class MeshGradientPainter extends CustomPainter {
  MeshGradientPainter({
    required this.shader,
    required this.time,
    required this.pixelRatio,
    required this.colors,
    required this.backgroundColor,
    required this.distortion,
    required this.swirl,
    required this.scale,
    required this.rotation,
    required this.offsetX,
    required this.offsetY,
  });

  final ui.FragmentShader shader;
  final double time;
  final double pixelRatio;
  final List<Color> colors;
  final Color backgroundColor;
  final double distortion;
  final double swirl;
  final double scale;
  final double rotation;
  final double offsetX;
  final double offsetY;

  @override
  void paint(Canvas canvas, Size size) {
    var idx = 0;

    // u_resolution (vec2)
    shader.setFloat(idx++, size.width);
    shader.setFloat(idx++, size.height);

    // u_time
    shader.setFloat(idx++, time);

    // u_pixelRatio
    shader.setFloat(idx++, pixelRatio);

    // u_scale
    shader.setFloat(idx++, scale);

    // u_rotation
    shader.setFloat(idx++, rotation);

    // u_offsetX, u_offsetY
    shader.setFloat(idx++, offsetX);
    shader.setFloat(idx++, offsetY);

    // u_colorsCount
    shader.setFloat(idx++, colors.length.toDouble());

    // u_distortion
    shader.setFloat(idx++, distortion);

    // u_swirl
    shader.setFloat(idx++, swirl);

    // u_colorBack (vec4)
    idx = _setColor(idx, backgroundColor);

    // u_color0 ~ u_color6 (7 × vec4)
    for (var i = 0; i < 7; i++) {
      if (i < colors.length) {
        idx = _setColor(idx, colors[i]);
      } else {
        idx = _setColor(idx, const Color(0x00000000));
      }
    }

    final paint = Paint()..shader = shader;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  /// 设置颜色 uniform（RGBA 0-1 范围）
  int _setColor(int idx, Color color) {
    shader.setFloat(idx++, color.r);
    shader.setFloat(idx++, color.g);
    shader.setFloat(idx++, color.b);
    shader.setFloat(idx++, color.a);
    return idx;
  }

  @override
  bool shouldRepaint(MeshGradientPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.pixelRatio != pixelRatio ||
        oldDelegate.distortion != distortion ||
        oldDelegate.swirl != swirl ||
        oldDelegate.scale != scale ||
        oldDelegate.rotation != rotation ||
        oldDelegate.offsetX != offsetX ||
        oldDelegate.offsetY != offsetY ||
        oldDelegate.backgroundColor != backgroundColor ||
        !_colorsEqual(oldDelegate.colors, colors);
  }

  bool _colorsEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
