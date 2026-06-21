import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 扫描边界标记 Widget
/// 用于阻止 SpoilerOverlay 和 InlineDecoratorOverlay 向下扫描
/// 适用于可水平滚动的容器（如表格），让内部的 overlay 自行处理
class ScanBoundary extends SingleChildRenderObjectWidget {
  const ScanBoundary({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderScanBoundary();
}

/// 扫描边界 RenderObject
class RenderScanBoundary extends RenderProxyBox {}
