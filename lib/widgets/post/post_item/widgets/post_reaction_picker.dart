import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../models/topic.dart';
import '../../../../services/discourse_cache_manager.dart';
import '../../../../services/emoji_handler.dart';
import '../../../../utils/platform_utils.dart';

/// 获取 emoji 图片 URL（未加载完成时返回空字符串，由 errorBuilder 处理）
String _getEmojiUrl(String emojiName) {
  return EmojiHandler().getEmojiUrl(emojiName);
}

/// 回应选择器弹窗
class PostReactionPicker {
  /// 显示回应选择器
  static void show({
    required BuildContext context,
    required ThemeData theme,
    required GlobalKey likeButtonKey,
    required List<String> reactions,
    required PostReaction? currentUserReaction,
    required void Function(String reactionId) onReactionSelected,
  }) {
    final box = likeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final buttonPos = box.localToGlobal(Offset.zero);
    final buttonSize = box.size;
    final screenWidth = MediaQuery.of(context).size.width;

    // 配置参数
    const double itemSize = 40.0;
    const double iconSize = 26.0;
    const double spacing = 1.0;
    const double padding = 4.0;
    const int crossAxisCount = 5;

    // 计算尺寸
    final int count = reactions.length;
    final int cols = count < crossAxisCount ? count : crossAxisCount;
    final int rows = (count / crossAxisCount).ceil();

    final double pickerWidth = (itemSize * cols) + (spacing * (cols - 1)) + (padding * 2) + 4.0;
    final double pickerHeight = (itemSize * rows) + (spacing * (rows - 1)) + (padding * 2);

    // 计算左边位置：居中于按钮，但限制在屏幕内
    double left = (buttonPos.dx + buttonSize.width / 2) - (pickerWidth / 2);
    if (left < 16) left = 16;
    if (left + pickerWidth > screenWidth - 16) left = screenWidth - pickerWidth - 16;

    // 计算顶部位置：默认在按钮上方
    bool isAbove = true;
    double top = buttonPos.dy - pickerHeight - 12;
    if (top < 80) {
      top = buttonPos.dy + buttonSize.height + 12;
      isAbove = false;
    }

    // 计算动画原点 Alignment
    final buttonCenterX = buttonPos.dx + buttonSize.width / 2;
    final relativeX = (buttonCenterX - left) / pickerWidth;
    final alignmentX = relativeX * 2 - 1;
    final alignmentY = isAbove ? 1.0 : -1.0;

    final transformAlignment = Alignment(alignmentX, alignmentY);

    // 触发按钮区域（含上下 12px 间隙，使按钮与气泡之间的空隙也是安全区域）
    final buttonRect = Rect.fromLTWH(
      buttonPos.dx, buttonPos.dy - 12, buttonSize.width, buttonSize.height + 24,
    );

    // 防止多个 pop 入口（barrier 点击 / hover 离开 / 选择表情）重复 pop
    bool dismissed = false;
    late final BuildContext dialogContext;

    void safePop() {
      if (dismissed) return;
      dismissed = true;
      Navigator.pop(dialogContext);
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: PlatformUtils.isDesktop
          ? const Duration(milliseconds: 150)
          : const Duration(milliseconds: 450),
      pageBuilder: (ctx, _, _) {
        dialogContext = ctx;
        // 桌面端：鼠标离开气泡+按钮区域后自动关闭
        if (PlatformUtils.isDesktop) {
          return _DesktopReactionPickerHost(
            pickerRect: Rect.fromLTWH(left, top, pickerWidth, pickerHeight),
            buttonRect: buttonRect,
            onDismiss: safePop,
          );
        }
        return const SizedBox();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        // 桌面端：干脆的缩放动画；移动端：弹性回弹
        final double curvedValue;
        final double opacity;
        if (PlatformUtils.isDesktop) {
          curvedValue = Curves.easeOutCubic.transform(animation.value);
          opacity = animation.value;
        } else {
          curvedValue = Curves.elasticOut.transform(animation.value);
          opacity = (animation.value / 0.15).clamp(0.0, 1.0);
        }

        return Stack(
          children: [
            // 全屏透明点击层
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: safePop,
                child: child, // 桌面端 host 在此，处理鼠标追踪
              ),
            ),
            // 气泡主体
            Positioned(
              left: left,
              top: top,
              child: Transform.scale(
                scale: curvedValue,
                alignment: transformAlignment,
                child: Opacity(
                  opacity: opacity,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: pickerWidth,
                      height: pickerHeight,
                      padding: const EdgeInsets.all(padding),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 16,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                      ),
                      child: Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        alignment: WrapAlignment.center,
                        children: reactions.map((r) {
                          final isCurrent = currentUserReaction?.id == r;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              safePop();
                              onReactionSelected(r);
                            },
                            child: Container(
                              width: itemSize,
                              height: itemSize,
                              decoration: BoxDecoration(
                                color: isCurrent ? theme.colorScheme.primaryContainer : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Image(
                                  image: emojiImageProvider(_getEmojiUrl(r)),
                                  width: iconSize,
                                  height: iconSize,
                                  errorBuilder: (_, _, _) => const Icon(Icons.emoji_emotions_outlined, size: 24),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 桌面端：追踪鼠标位置，离开气泡和触发按钮区域后自动关闭
class _DesktopReactionPickerHost extends StatefulWidget {
  final Rect pickerRect;
  final Rect buttonRect;
  final VoidCallback onDismiss;

  const _DesktopReactionPickerHost({
    required this.pickerRect,
    required this.buttonRect,
    required this.onDismiss,
  });

  @override
  State<_DesktopReactionPickerHost> createState() => _DesktopReactionPickerHostState();
}

class _DesktopReactionPickerHostState extends State<_DesktopReactionPickerHost> {
  Timer? _dismissTimer;

  /// 安全区域：气泡 + 触发按钮（含间隙）
  bool _isInSafeZone(Offset globalPos) {
    // 气泡区域加 8px 容差
    final expandedPickerRect = widget.pickerRect.inflate(8);
    if (expandedPickerRect.contains(globalPos)) return true;
    // 触发按钮区域
    if (widget.buttonRect.contains(globalPos)) return true;
    return false;
  }

  void _onPointerMove(PointerEvent event) {
    if (_isInSafeZone(event.position)) {
      _dismissTimer?.cancel();
      _dismissTimer = null;
    } else {
      _dismissTimer ??= Timer(const Duration(milliseconds: 300), widget.onDismiss);
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: _onPointerMove,
      onPointerMove: _onPointerMove,
      child: const SizedBox.expand(),
    );
  }
}
