import 'package:flutter/material.dart';

/// 内联代码背景绘制器
class InlineCodePainter extends CustomPainter {
  final List<List<Rect>> groups;
  final bool isDark;
  final int _groupsHash;

  InlineCodePainter({
    required this.groups,
    required this.isDark,
  }) : _groupsHash = Object.hashAll(groups.map((g) => Object.hashAll(g)));

  @override
  void paint(Canvas canvas, Size size) {
    final bgColor = isDark ? const Color(0xFF3a3a3a) : const Color(0xFFe8e8e8);
    const radius = 3.0;
    const hPadding = 3.5;
    const vPadding = 1.5;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = bgColor;

    for (final group in groups) {
      final rows = <List<Rect>>[];
      for (final rect in group) {
        bool added = false;
        for (final row in rows) {
          if (rect.top < row.first.bottom && rect.bottom > row.first.top) {
            row.add(rect);
            added = true;
            break;
          }
        }
        if (!added) {
          rows.add([rect]);
        }
      }

      final rowCount = rows.length;
      for (int i = 0; i < rowCount; i++) {
        final row = rows[i];
        row.sort((a, b) => a.left.compareTo(b.left));

        final isFirst = i == 0;
        final isLast = i == rowCount - 1;

        final merged = Rect.fromLTRB(
          row.first.left - hPadding,
          row.map((r) => r.top).reduce((a, b) => a < b ? a : b) - vPadding,
          row.last.right + hPadding,
          row.map((r) => r.bottom).reduce((a, b) => a > b ? a : b) + vPadding,
        );

        final Radius leftRadius = isFirst ? const Radius.circular(radius) : Radius.zero;
        final Radius rightRadius = isLast ? const Radius.circular(radius) : Radius.zero;

        final rrect = RRect.fromRectAndCorners(
          merged,
          topLeft: leftRadius,
          bottomLeft: leftRadius,
          topRight: rightRadius,
          bottomRight: rightRadius,
        );
        canvas.drawRRect(rrect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(InlineCodePainter oldDelegate) {
    return isDark != oldDelegate.isDark || _groupsHash != oldDelegate._groupsHash;
  }
}