import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'grain_gradient_shape.dart';

/// GrainGradient 的 CustomPainter
///
/// 负责设置 shader uniform 并绘制。
class GrainGradientPainter extends CustomPainter {
  GrainGradientPainter({
    required this.shader,
    required this.noiseTexture,
    required this.time,
    required this.pixelRatio,
    required this.colors,
    required this.backgroundColor,
    required this.softness,
    required this.intensity,
    required this.noise,
    required this.shape,
    required this.scale,
    required this.rotation,
    required this.offsetX,
    required this.offsetY,
  });

  final ui.FragmentShader shader;
  final ui.Image noiseTexture;
  final double time;
  final double pixelRatio;
  final List<Color> colors;
  final Color backgroundColor;
  final double softness;
  final double intensity;
  final double noise;
  final GrainGradientShape shape;
  final double scale;
  final double rotation;
  final double offsetX;
  final double offsetY;

  @override
  void paint(Canvas canvas, Size size) {
    var idx = 0;

    // u_resolution (vec2) — 使用逻辑像素，与 FlutterFragCoord() 一致
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

    // u_softness
    shader.setFloat(idx++, softness);

    // u_intensity
    shader.setFloat(idx++, intensity);

    // u_noise
    shader.setFloat(idx++, noise);

    // u_shape
    shader.setFloat(idx++, shape.value);

    // u_colorsCount
    shader.setFloat(idx++, colors.length.toDouble());

    // u_colorBack (vec4, premultiplied alpha)
    idx = _setColor(idx, backgroundColor);

    // u_color0 ~ u_color6 (7 × vec4)
    for (var i = 0; i < 7; i++) {
      if (i < colors.length) {
        idx = _setColor(idx, colors[i]);
      } else {
        // 填充透明色
        idx = _setColor(idx, const Color(0x00000000));
      }
    }

    // sampler 0: u_noiseTexture
    shader.setImageSampler(0, noiseTexture);

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
  bool shouldRepaint(GrainGradientPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.pixelRatio != pixelRatio ||
        oldDelegate.softness != softness ||
        oldDelegate.intensity != intensity ||
        oldDelegate.noise != noise ||
        oldDelegate.shape != shape ||
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
