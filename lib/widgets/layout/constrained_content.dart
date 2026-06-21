import 'package:flutter/widgets.dart';
import '../../utils/responsive.dart';

/// 内容宽度约束组件
/// 在大屏幕上限制内容最大宽度，使阅读更舒适
class ConstrainedContent extends StatelessWidget {
  const ConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.maxContentWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    Widget content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    );

    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    return Align(
      alignment: alignment,
      child: content,
    );
  }
}

/// Sliver 版本的内容宽度约束
class SliverConstrainedContent extends StatelessWidget {
  const SliverConstrainedContent({
    super.key,
    required this.sliver,
    this.maxWidth = Breakpoints.maxContentWidth,
    this.padding,
  });

  final Widget sliver;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.crossAxisExtent;
        final horizontalPadding = screenWidth > maxWidth
            ? (screenWidth - maxWidth) / 2
            : 0.0;

        final effectivePadding = padding ?? EdgeInsets.zero;
        final combinedPadding = EdgeInsetsDirectional.only(
          start: horizontalPadding + effectivePadding.horizontal / 2,
          end: horizontalPadding + effectivePadding.horizontal / 2,
          top: (effectivePadding as EdgeInsets?)?.top ?? 0,
          bottom: (effectivePadding as EdgeInsets?)?.bottom ?? 0,
        );

        return SliverPadding(
          padding: combinedPadding,
          sliver: sliver,
        );
      },
    );
  }
}
