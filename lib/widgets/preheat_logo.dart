import 'package:flutter/material.dart';

import '../providers/app_icon_provider.dart';

/// 启动页 logo 动画组件。
///
/// 保留 [style] 参数以兼容现有调用；当前启动页统一展示 EqunDO 默认图标。
class PreheatLogo extends StatefulWidget {
  final AppIconStyle style;
  final double size;

  const PreheatLogo({super.key, required this.style, this.size = 108});

  @override
  State<PreheatLogo> createState() => _PreheatLogoState();
}

class _PreheatLogoState extends State<PreheatLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 2400),
    vsync: this,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final breathe = Curves.easeInOutSine.transform(_controller.value);
        final glowAlpha = 0.14 + 0.08 * breathe;
        final glowBlur = 32.0 + 16.0 * breathe;
        final scale = 0.98 + 0.02 * breathe;

        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: glowAlpha),
                blurRadius: glowBlur,
              ),
            ],
          ),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: SizedBox.square(
        dimension: widget.size,
        child: Image.asset(
          'assets/images/icon_default_preview.png',
          key: const ValueKey('preheat-logo'),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
