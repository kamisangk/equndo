import 'package:flutter/material.dart';

/// 模拟印章残缺边框的绘制器
class PostStampPainter extends CustomPainter {
  final Color color;
  PostStampPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final path = Path();
    const double radius = 8;

    // 绘制残缺的矩形边框
    // 顶部边（部分）
    path.moveTo(size.width * 0.1, 0);
    path.lineTo(size.width - radius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, radius);

    // 右侧边（部分）
    path.lineTo(size.width, size.height * 0.7);

    // 底部边（从右向左，部分）
    path.moveTo(size.width * 0.8, size.height);
    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);

    // 左侧边（部分）
    path.lineTo(0, size.height * 0.3);
    path.moveTo(0, size.height * 0.15);
    path.lineTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
