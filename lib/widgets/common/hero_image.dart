import 'package:flutter/material.dart';
import '../../utils/hero_visibility_controller.dart';

/// 封装 Hero 动画及可见性控制的图片 Widget
///
/// 提供：
/// - Hero 飞行动画
/// - 源端自动隐藏/显示
/// - pop 飞行结束后无闪烁恢复
/// - placeholderBuilder 正确行为
///
/// 使用者只需包裹 HeroImage 即可获得完整的 Hero 体验。
/// 调用方（如 ImageViewerPage）在 initState/onPageChanged/dispose 时
/// 通知 HeroVisibilityController 即可。
class HeroImage extends StatelessWidget {
  /// Hero 动画的唯一标识
  final String heroTag;

  /// 实际显示的图片内容
  final Widget child;

  /// 点击回调
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  /// 右键回调（桌面端）
  final GestureTapUpCallback? onSecondaryTapUp;

  const HeroImage({
    super.key,
    required this.heroTag,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
  });

  @override
  Widget build(BuildContext context) {
    // Opacity 在 Hero 外层控制可见性
    // Hero 飞行在 Overlay 中，不受外层 Opacity 影响
    return ListenableBuilder(
      listenable: HeroVisibilityController.instance,
      builder: (context, _) {
        final controller = HeroVisibilityController.instance;
        final hiddenTag = controller.hiddenHeroTag;
        final isPopping = controller.isPopping;

        // pop 期间不隐藏任何图片（让 child 可见），其他时候根据 hiddenTag 判断
        final shouldHide = !isPopping && hiddenTag == heroTag;

        return Opacity(
          opacity: shouldHide ? 0.0 : 1.0,
          child: Hero(
            tag: heroTag,
            // 飞行动画：返回纯图片，并在 pop 飞行结束时设置 isPopping
            flightShuttleBuilder: (flightContext, animation, direction, fromContext, toContext) {
              if (direction == HeroFlightDirection.pop) {
                void listener(AnimationStatus status) {
                  if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
                    animation.removeStatusListener(listener);
                    HeroVisibilityController.instance.startPopping();
                  }
                }
                animation.addStatusListener(listener);
              }
              return child;
            },
            // 飞行期间源端占位 - 直接读取最新状态
            placeholderBuilder: (context, heroSize, _) {
              final ctrl = HeroVisibilityController.instance;
              final currentIsPopping = ctrl.isPopping;
              final currentHiddenTag = ctrl.hiddenHeroTag;

              // pop 飞行中 或 当前正在查看的图片：空占位
              if (currentIsPopping || currentHiddenTag == heroTag) {
                return SizedBox(width: heroSize.width, height: heroSize.height);
              }
              // 其他图片：显示图片
              return GestureDetector(
                onTap: onTap,
                onLongPress: onLongPress,
                onSecondaryTapUp: onSecondaryTapUp,
                child: SizedBox(
                  width: heroSize.width,
                  height: heroSize.height,
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onTap: onTap,
              onLongPress: onLongPress,
              onSecondaryTapUp: onSecondaryTapUp,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
