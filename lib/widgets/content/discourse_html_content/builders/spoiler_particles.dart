import 'dart:math';
import 'package:flutter/material.dart';

/// 粒子数据
class SpoilerParticle {
  double x, y, vx, vy;
  double life, maxLife;
  int alphaType; // 0=0.3, 1=0.6, 2=1.0
  Rect? boundingRect; // 所属区域（用于多行 spoiler）

  SpoilerParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.maxLife,
    required this.alphaType,
    this.boundingRect,
  });
}

/// Spoiler 粒子系统（管理粒子生成、更新和绘制）
class SpoilerParticleSystem {
  final List<SpoilerParticle> particles = [];
  final Random _random = Random();
  int _maxParticles = 200;
  List<Rect> _rects = [];

  /// 根据区域初始化粒子
  void initForRects(List<Rect> rects) {
    _rects = rects;
    if (rects.isEmpty) return;

    // 计算总面积
    double totalArea = 0;
    for (final rect in rects) {
      totalArea += rect.width * rect.height;
    }

    // 粒子密度：每 4 平方像素一个粒子，范围 200-2000
    _maxParticles = (totalArea / 4).clamp(200, 2000).toInt();

    // 初始填充粒子
    particles.clear();
    for (int i = 0; i < _maxParticles; i++) {
      _spawnParticle();
    }
  }

  /// 更新区域位置，复用已有粒子（避免布局变化时粒子闪烁重建）
  void updateRects(List<Rect> newRects) {
    if (newRects.isEmpty) {
      clear();
      return;
    }

    final oldRects = _rects;
    _rects = newRects;

    // 计算新的最大粒子数
    double totalArea = 0;
    for (final rect in newRects) {
      totalArea += rect.width * rect.height;
    }
    _maxParticles = (totalArea / 4).clamp(200, 2000).toInt();

    // 建立旧区域索引到新区域的映射（按顺序一一对应）
    // 并将已有粒子的 boundingRect 迁移到新区域
    for (final p in particles) {
      final oldIdx = oldRects.indexOf(p.boundingRect!);
      if (oldIdx >= 0 && oldIdx < newRects.length) {
        // 计算粒子在旧区域中的相对位置，映射到新区域
        final oldRect = oldRects[oldIdx];
        final newRect = newRects[oldIdx];
        final relX = (p.x - oldRect.left) / oldRect.width;
        final relY = (p.y - oldRect.top) / oldRect.height;
        p.x = newRect.left + relX * newRect.width;
        p.y = newRect.top + relY * newRect.height;
        p.boundingRect = newRect;
      } else {
        // 旧区域不存在于新布局中，标记粒子为已死亡
        p.life = 0;
      }
    }

    // 移除已死亡的粒子
    particles.removeWhere((p) => p.life <= 0);

    // 补充或裁减粒子数
    while (particles.length < _maxParticles) {
      _spawnParticle();
    }
    if (particles.length > _maxParticles) {
      particles.removeRange(_maxParticles, particles.length);
    }
  }

  /// 根据尺寸初始化粒子（用于块级 spoiler）
  void initForSize(Size size) {
    initForRects([Rect.fromLTWH(0, 0, size.width, size.height)]);
  }

  /// 生成一个新粒子
  void _spawnParticle() {
    if (_rects.isEmpty) return;

    // 按面积权重随机选择一个区域
    double totalArea = 0;
    for (final rect in _rects) {
      totalArea += rect.width * rect.height;
    }

    double r = _random.nextDouble() * totalArea;
    Rect? selectedRect;
    for (final rect in _rects) {
      r -= rect.width * rect.height;
      if (r <= 0) {
        selectedRect = rect;
        break;
      }
    }
    selectedRect ??= _rects.last;

    final angle = _random.nextDouble() * 2 * pi;
    final velocity = 4 + _random.nextDouble() * 6;

    particles.add(SpoilerParticle(
      x: selectedRect.left + _random.nextDouble() * selectedRect.width,
      y: selectedRect.top + _random.nextDouble() * selectedRect.height,
      vx: cos(angle) * velocity,
      vy: sin(angle) * velocity,
      life: 1.0,
      maxLife: 1.0 + _random.nextDouble() * 2.0,
      alphaType: _random.nextInt(3),
      boundingRect: selectedRect,
    ));
  }

  /// 更新粒子状态
  void update(double dtMs) {
    if (_rects.isEmpty) return;

    final dtFactor = dtMs / 500.0;
    final toRemove = <SpoilerParticle>[];

    for (final p in particles) {
      p.x += p.vx * dtFactor;
      p.y += p.vy * dtFactor;
      p.life -= (dtMs / 1000.0) / p.maxLife;

      // 检查是否死亡或出界（使用所属区域的边界）
      final bound = p.boundingRect ?? _rects.first;
      if (p.life <= 0 ||
          p.x < bound.left - 5 ||
          p.x > bound.right + 5 ||
          p.y < bound.top - 5 ||
          p.y > bound.bottom + 5) {
        toRemove.add(p);
      }
    }

    for (final p in toRemove) {
      particles.remove(p);
    }

    // 补充新粒子
    while (particles.length < _maxParticles) {
      _spawnParticle();
    }
  }

  /// 清空粒子
  void clear() {
    particles.clear();
    _rects = [];
  }
}

/// Spoiler 粒子绘制器
class SpoilerParticlePainter extends CustomPainter {
  final List<SpoilerParticle> particles;
  final bool isDark;
  final Color? backgroundColor;
  final List<Rect>? clipRects; // 裁剪区域（用于多行 spoiler）
  final double borderRadius;

  static const alphaLevels = [0.3, 0.6, 1.0];

  SpoilerParticlePainter({
    required this.particles,
    required this.isDark,
    this.backgroundColor,
    this.clipRects,
    this.borderRadius = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isDark ? Colors.white : Colors.grey.shade800;
    final paint = Paint()..style = PaintingStyle.fill;

    if (clipRects != null && clipRects!.isNotEmpty) {
      // 多区域模式：每个区域单独绘制
      for (final rect in clipRects!) {
        final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

        canvas.save();
        canvas.clipRRect(rrect);

        // 绘制背景
        if (backgroundColor != null) {
          paint.color = backgroundColor!;
          canvas.drawRRect(rrect, paint);
        }

        // 绘制属于这个区域的粒子
        for (final p in particles) {
          if (p.boundingRect == rect) {
            paint.color = baseColor.withValues(alpha: alphaLevels[p.alphaType] * p.life);
            final radius = p.alphaType == 0 ? 0.7 : 0.6;
            canvas.drawCircle(Offset(p.x, p.y), radius, paint);
          }
        }

        canvas.restore();
      }
    } else {
      // 单区域模式（块级 spoiler）
      final rect = Rect.fromLTWH(0, 0, size.width, size.height);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

      // 绘制背景
      if (backgroundColor != null) {
        paint.color = backgroundColor!;
        canvas.drawRRect(rrect, paint);
      }

      // 绘制所有粒子
      for (final p in particles) {
        paint.color = baseColor.withValues(alpha: alphaLevels[p.alphaType] * p.life);
        final radius = p.alphaType == 0 ? 0.7 : 0.6;
        canvas.drawCircle(Offset(p.x, p.y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SpoilerParticlePainter oldDelegate) => true;
}
