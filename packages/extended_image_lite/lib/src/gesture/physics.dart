import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// 惯性滑动物理配置
class InertiaPhysicsConfig {
  const InertiaPhysicsConfig({
    this.friction = 0.02,
    this.minVelocity = 50.0,
  });

  /// 摩擦系数 - 值越小滑动越远
  /// 0.01 = 滑动很远（冰面感）
  /// 0.02 = 适中（默认）
  /// 0.05 = 较快停止
  final double friction;

  /// 最小启动速度 - 低于此速度不触发惯性
  final double minVelocity;

  static const smooth = InertiaPhysicsConfig(friction: 0.015);
  static const standard = InertiaPhysicsConfig(friction: 0.02);
  static const quick = InertiaPhysicsConfig(friction: 0.035);
}

/// 2D 惯性滑动模拟器
class Inertia2DSimulation extends Simulation {
  Inertia2DSimulation({
    required this.startPosition,
    required Offset velocity,
    required double friction,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    super.tolerance,
  }) : _xSim = FrictionSimulation(friction, startPosition.dx, velocity.dx),
       _ySim = FrictionSimulation(friction, startPosition.dy, velocity.dy);

  final Offset startPosition;
  final FrictionSimulation _xSim;
  final FrictionSimulation _ySim;

  // 边界
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  /// 获取指定时间点的位置（带边界限制）
  Offset positionAt(double time) {
    double x = _xSim.x(time);
    double y = _ySim.x(time);

    // 边界限制
    x = x.clamp(minX, maxX);
    y = y.clamp(minY, maxY);

    return Offset(x, y);
  }

  /// 获取指定时间点的速度
  Offset velocityAt(double time) {
    return Offset(_xSim.dx(time), _ySim.dx(time));
  }

  /// 预测最终停止位置（考虑边界）
  Offset get finalPosition {
    double x = _xSim.finalX.clamp(minX, maxX);
    double y = _ySim.finalX.clamp(minY, maxY);
    return Offset(x, y);
  }

  /// 检查是否已到达边界
  bool isAtBoundary(double time) {
    final pos = positionAt(time);
    return pos.dx <= minX || pos.dx >= maxX ||
           pos.dy <= minY || pos.dy >= maxY;
  }

  @override
  double x(double time) => positionAt(time).distance;

  @override
  double dx(double time) => velocityAt(time).distance;

  @override
  bool isDone(double time) {
    final vel = velocityAt(time);
    final atBoundary = isAtBoundary(time);
    // 速度足够小或已到边界
    return (vel.distance < tolerance.velocity) || atBoundary;
  }
}

/// 计算惯性滑动的边界
class ScrollBounds {
  const ScrollBounds({
    required this.viewportSize,
    required this.contentSize,
  });

  final Size viewportSize;
  final Size contentSize;

  /// 获取 X 方向的偏移边界
  /// 返回 (minOffset, maxOffset)
  (double, double) get xBounds {
    if (contentSize.width <= viewportSize.width) {
      // 内容比视口小，居中，不允许滑动
      return (0.0, 0.0);
    }
    // 内容比视口大，可以左右滑动
    final maxOffset = (contentSize.width - viewportSize.width) / 2;
    return (-maxOffset, maxOffset);
  }

  /// 获取 Y 方向的偏移边界
  (double, double) get yBounds {
    if (contentSize.height <= viewportSize.height) {
      return (0.0, 0.0);
    }
    final maxOffset = (contentSize.height - viewportSize.height) / 2;
    return (-maxOffset, maxOffset);
  }
}

