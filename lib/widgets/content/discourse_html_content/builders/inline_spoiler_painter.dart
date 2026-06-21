import 'package:flutter/material.dart';
import 'spoiler_particles.dart';

/// Spoiler 区域
class SpoilerRect {
  final Rect rect;
  SpoilerRect({required this.rect});
}

/// Spoiler 组（一个 spoiler 可能跨多行）
class SpoilerGroup {
  final String id;
  final List<SpoilerRect> rects;
  final SpoilerParticleSystem particleSystem = SpoilerParticleSystem();
  bool isRevealed = false;

  SpoilerGroup({required this.id, required this.rects});

  /// 检查点是否在任意区域内
  bool containsPoint(Offset point) {
    for (final r in rects) {
      if (r.rect.contains(point)) return true;
    }
    return false;
  }
}

/// 内联 Spoiler 绘制器
class InlineSpoilerPainter extends CustomPainter {
  final List<SpoilerGroup> groups;
  final bool isDark;
  final Color backgroundColor;

  static const alphaLevels = [0.3, 0.6, 1.0];

  InlineSpoilerPainter({
    required this.groups,
    required this.isDark,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isDark ? Colors.white : Colors.grey.shade800;
    final paint = Paint()..style = PaintingStyle.fill;

    for (final group in groups) {
      for (final spoilerRect in group.rects) {
        final rect = spoilerRect.rect;
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

        canvas.save();
        canvas.clipRRect(rrect);

        paint.color = backgroundColor;
        canvas.drawRRect(rrect, paint);

        for (final p in group.particleSystem.particles) {
          if (p.boundingRect == rect) {
            paint.color = baseColor.withValues(alpha: alphaLevels[p.alphaType] * p.life);
            final radius = p.alphaType == 0 ? 0.7 : 0.6;
            canvas.drawCircle(Offset(p.x, p.y), radius, paint);
          }
        }

        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(InlineSpoilerPainter oldDelegate) => true;
}

/// 归一化同行的 rect 高度
List<SpoilerRect> normalizeRowHeights(List<SpoilerRect> rects) {
  if (rects.isEmpty) return rects;

  final List<List<SpoilerRect>> rows = [];
  for (final rect in rects) {
    bool addedToRow = false;
    for (final row in rows) {
      for (final existing in row) {
        if (rect.rect.top < existing.rect.bottom && rect.rect.bottom > existing.rect.top) {
          row.add(rect);
          addedToRow = true;
          break;
        }
      }
      if (addedToRow) break;
    }
    if (!addedToRow) {
      rows.add([rect]);
    }
  }

  final List<SpoilerRect> result = [];
  for (final row in rows) {
    double minTop = row.first.rect.top;
    double maxBottom = row.first.rect.bottom;
    for (final rect in row) {
      if (rect.rect.top < minTop) minTop = rect.rect.top;
      if (rect.rect.bottom > maxBottom) maxBottom = rect.rect.bottom;
    }
    for (final rect in row) {
      result.add(SpoilerRect(
        rect: Rect.fromLTRB(rect.rect.left, minTop, rect.rect.right, maxBottom),
      ));
    }
  }
  return result;
}
