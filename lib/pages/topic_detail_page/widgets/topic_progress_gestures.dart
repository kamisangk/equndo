import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/preferences_provider.dart';
import 'progress_gesture_action_meta.dart';

/// 滑动触发阈值（手指相对起点的距离 ≥ 此值即视为可触发）
const double _kSwipeTriggerDistance = 56.0;

/// 滑动方向判定的死区（小于此值不判断方向）
const double _kSwipeDeadZone = 6.0;

/// 进度悬浮条手势包装：在 [TopicProgress] 上识别左/右/上滑与长按
///
/// - 按压进度环：手指落下即在悬浮条边缘累积一圈描边，按住越久环越满，
///   可视化反馈"按压时间"。pan 胜出或松开会让环回缩。
/// - 左/右/上滑：实时显示预览药丸，距离 ≥ [_kSwipeTriggerDistance] 后可触发
/// - 长按 200ms：弹出半圆向上展开菜单，拖到目标松开触发；拖到死区取消
/// - tap 由内层 InkWell 处理，本组件只处理 swipe + long press
/// - 总开关关闭时本组件退化为透传
class TopicProgressGestures extends ConsumerStatefulWidget {
  const TopicProgressGestures({
    super.key,
    required this.child,
    required this.onAction,
  });

  final Widget child;
  final ValueChanged<ProgressGestureAction> onAction;

  @override
  ConsumerState<TopicProgressGestures> createState() =>
      _TopicProgressGesturesState();
}

enum _SwipeDirection { left, right, up }

class _TopicProgressGesturesState extends ConsumerState<TopicProgressGestures>
    with TickerProviderStateMixin {
  // 长按菜单状态
  OverlayEntry? _menuEntry;
  Offset? _menuCenter;
  Rect? _pressArea; // 悬浮条本体的全局矩形，菜单弹出后在此位置画替代显示
  int? _highlightedIndex;
  List<ProgressGestureAction> _menuItems = const [];

  /// 缩短的长按触发阈值，让长按更早胜出，避免 swipe 与菜单视觉冲突
  static const Duration _longPressTimeout = Duration(milliseconds: 200);

  /// 按压进度环动画时长。比长按阈值略长，让用户在 200ms 触发时仍能看到
  /// 环还在累积，强化"按住越久越满"的感受
  static const Duration _pressProgressDuration = Duration(milliseconds: 520);

  late final AnimationController _pressController = AnimationController(
    vsync: this,
    duration: _pressProgressDuration,
  );

  // 滑动预览状态
  OverlayEntry? _swipeEntry;
  Offset? _swipeOrigin; // 悬浮条本体中心（用于定位预览药丸）
  Offset? _swipeStart; // 手指按下的全局坐标
  Offset _swipeCurrent = Offset.zero;
  _SwipeDirection? _swipeDirection;
  ProgressGestureAction? _swipeAction;
  bool _swipeTriggerable = false;

  @override
  void dispose() {
    _disposeMenuOverlay();
    _disposeSwipeOverlay();
    _pressController.dispose();
    super.dispose();
  }

  // ===== 按压进度环 =====

  void _handlePointerDown(PointerDownEvent event) {
    _pressController.forward(from: 0);
  }

  void _handlePointerUp(PointerUpEvent event) {
    _retractPressRing();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _retractPressRing();
  }

  /// 让进度环回缩到 0（带 120ms 平滑过渡，避免突然消失）
  void _retractPressRing() {
    if (_pressController.value == 0 && !_pressController.isAnimating) return;
    _pressController.animateTo(
      0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeIn,
    );
  }

  // ===== 长按菜单 =====

  void _disposeMenuOverlay() {
    _menuEntry?.remove();
    _menuEntry = null;
    _menuCenter = null;
    _pressArea = null;
    _highlightedIndex = null;
    _menuItems = const [];
  }

  double _radiusForCount(int count) {
    if (count <= 4) return 92;
    if (count <= 6) return 108;
    return 128;
  }

  void _handleLongPressStart(
    LongPressStartDetails details,
    AppPreferences prefs,
  ) {
    if (!prefs.progressGesturesEnabled) return;
    if (!prefs.progressGestureLongPressEnabled) return;
    final items = prefs.progressGestureMenuActions;
    if (items.isEmpty) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final widgetTopLeft = box.localToGlobal(Offset.zero);
    final widgetTopCenter = widgetTopLeft + Offset(box.size.width / 2, 0);

    _menuCenter = widgetTopCenter;
    _pressArea = Rect.fromLTWH(
      widgetTopLeft.dx,
      widgetTopLeft.dy,
      box.size.width,
      box.size.height,
    );
    _menuItems = items;
    _highlightedIndex = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    _menuEntry = OverlayEntry(builder: (_) => _buildMenuOverlay());
    overlay.insert(_menuEntry!);
    HapticFeedback.mediumImpact();

    // 长按触发，让进度环继续走到 1（视觉上"环走完=菜单完全展开"）
    _pressController.forward();
    _updateHighlight(details.globalPosition);
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_menuEntry == null) return;
    _updateHighlight(details.globalPosition);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    final idx = _highlightedIndex;
    final items = List<ProgressGestureAction>.from(_menuItems);
    _disposeMenuOverlay();
    if (idx != null && idx >= 0 && idx < items.length) {
      HapticFeedback.mediumImpact();
      widget.onAction(items[idx]);
    }
  }

  void _handleLongPressCancel() {
    _disposeMenuOverlay();
  }

  void _updateHighlight(Offset pointer) {
    final center = _menuCenter;
    if (center == null) return;
    final dx = pointer.dx - center.dx;
    final dy = pointer.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    int? newIndex;
    // 死区：紧贴中心（距离极小）或落入下半圆。其余范围根据角度找最近项，
    // 不限制最大距离 —— 手指拖到屏幕远处也能命中对应方向的项
    if (distance < 18 || dy >= 0) {
      newIndex = null;
    } else {
      final angle = math.atan2(dy, dx); // dy < 0 → angle ∈ (-π, 0)
      final n = _menuItems.length;
      if (n == 1) {
        newIndex = 0;
      } else {
        final step = math.pi / (n - 1);
        final normalized = (angle + math.pi) / step;
        newIndex = normalized.round().clamp(0, n - 1);
      }
    }
    final changed = newIndex != _highlightedIndex;
    _highlightedIndex = newIndex;
    if (changed && newIndex != null) {
      HapticFeedback.selectionClick();
    }
    _menuEntry?.markNeedsBuild();
  }

  Widget _buildMenuOverlay() {
    return _RadialMenuOverlay(
      center: _menuCenter ?? Offset.zero,
      pressArea: _pressArea,
      items: _menuItems,
      highlightedIndex: _highlightedIndex,
      radius: _radiusForCount(_menuItems.length),
    );
  }

  // ===== 滑动预览 =====

  void _disposeSwipeOverlay() {
    _swipeEntry?.remove();
    _swipeEntry = null;
    _swipeOrigin = null;
    _swipeStart = null;
    _swipeCurrent = Offset.zero;
    _swipeDirection = null;
    _swipeAction = null;
    _swipeTriggerable = false;
  }

  void _handlePanStart(DragStartDetails details, AppPreferences prefs) {
    if (!prefs.progressGesturesEnabled) return;

    // pan 胜出，按压进度环立刻回缩（不再有"按住"的语义）
    _retractPressRing();

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    _swipeStart = details.globalPosition;
    _swipeCurrent = details.globalPosition;
    _swipeOrigin = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    _swipeDirection = null;
    _swipeAction = null;
    _swipeTriggerable = false;

    final overlay = Overlay.of(context, rootOverlay: true);
    _swipeEntry = OverlayEntry(builder: (_) => _buildSwipeOverlay());
    overlay.insert(_swipeEntry!);
  }

  void _handlePanUpdate(DragUpdateDetails details, AppPreferences prefs) {
    final start = _swipeStart;
    if (start == null) return;
    _swipeCurrent = details.globalPosition;

    final dx = _swipeCurrent.dx - start.dx;
    final dy = _swipeCurrent.dy - start.dy;
    final absDx = dx.abs();
    final absDy = dy.abs();
    final maxDelta = math.max(absDx, absDy);

    _SwipeDirection? direction;
    if (maxDelta >= _kSwipeDeadZone) {
      if (absDx > absDy) {
        direction = dx < 0 ? _SwipeDirection.left : _SwipeDirection.right;
      } else if (dy < 0) {
        direction = _SwipeDirection.up;
      }
    }

    ProgressGestureAction? action;
    switch (direction) {
      case _SwipeDirection.left:
        action = prefs.progressGestureSwipeLeft;
      case _SwipeDirection.right:
        action = prefs.progressGestureSwipeRight;
      case _SwipeDirection.up:
        action = prefs.progressGestureSwipeUp;
      case null:
        action = null;
    }
    // 绑定为「无」时等同于未绑定：不显示 pill、不可触发
    if (action == ProgressGestureAction.none) {
      action = null;
    }

    final triggerable = action != null && maxDelta >= _kSwipeTriggerDistance;

    final directionChanged = direction != _swipeDirection;
    final triggerChanged = triggerable != _swipeTriggerable;
    if (triggerChanged && triggerable) {
      HapticFeedback.lightImpact();
    } else if (directionChanged && direction != null) {
      HapticFeedback.selectionClick();
    }

    _swipeDirection = direction;
    _swipeAction = action;
    _swipeTriggerable = triggerable;
    _swipeEntry?.markNeedsBuild();
  }

  void _handlePanEnd(DragEndDetails details) {
    final triggered = _swipeTriggerable;
    final action = _swipeAction;
    _disposeSwipeOverlay();
    if (triggered && action != null) {
      HapticFeedback.mediumImpact();
      widget.onAction(action);
    }
  }

  void _handlePanCancel() {
    _disposeSwipeOverlay();
  }

  Widget _buildSwipeOverlay() {
    return _SwipePreviewOverlay(
      origin: _swipeOrigin ?? Offset.zero,
      direction: _swipeDirection,
      action: _swipeAction,
      triggerable: _swipeTriggerable,
      delta: (_swipeStart == null)
          ? Offset.zero
          : _swipeCurrent - _swipeStart!,
      triggerDistance: _kSwipeTriggerDistance,
    );
  }

  // ===== 入口 =====

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(preferencesProvider);
    if (!prefs.progressGesturesEnabled) {
      return widget.child;
    }
    final ringColor = Theme.of(context).colorScheme.primary;
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: RawGestureDetector(
        behavior: HitTestBehavior.deferToChild,
        gestures: <Type, GestureRecognizerFactory>{
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: _longPressTimeout),
                (instance) {
                  instance.onLongPressStart =
                      (d) => _handleLongPressStart(d, prefs);
                  instance.onLongPressMoveUpdate = _handleLongPressMoveUpdate;
                  instance.onLongPressEnd = _handleLongPressEnd;
                  instance.onLongPressCancel = _handleLongPressCancel;
                },
              ),
          PanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                () => PanGestureRecognizer(),
                (instance) {
                  instance.onStart = (d) => _handlePanStart(d, prefs);
                  instance.onUpdate = (d) => _handlePanUpdate(d, prefs);
                  instance.onEnd = _handlePanEnd;
                  instance.onCancel = _handlePanCancel;
                },
              ),
        },
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _pressController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _StadiumProgressPainter(
                          progress: _pressController.value,
                          color: ringColor,
                          strokeWidth: 2.5,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================== 进度环 painter ==============================

/// 在 stadium 形状（圆角胶囊）边缘画一圈描边，从顶部中点向左右两侧对称扩散。
/// progress = 0 时不画任何东西；progress = 1 时画完整一圈。
class _StadiumProgressPainter extends CustomPainter {
  const _StadiumProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final radius = rect.height / 2;
    final cx = rect.center.dx;

    // 右半路径：顶部中点 → 右上 → 右弧 → 右下 → 底部中点
    final rightPath = Path()
      ..moveTo(cx, rect.top)
      ..lineTo(rect.right - radius, rect.top)
      ..arcToPoint(
        Offset(rect.right - radius, rect.bottom),
        radius: Radius.circular(radius),
        clockwise: true,
      )
      ..lineTo(cx, rect.bottom);

    // 左半路径：顶部中点 → 左上 → 左弧 → 左下 → 底部中点（逆时针）
    final leftPath = Path()
      ..moveTo(cx, rect.top)
      ..lineTo(rect.left + radius, rect.top)
      ..arcToPoint(
        Offset(rect.left + radius, rect.bottom),
        radius: Radius.circular(radius),
        clockwise: false,
      )
      ..lineTo(cx, rect.bottom);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final p = progress.clamp(0.0, 1.0);
    for (final path in [rightPath, leftPath]) {
      for (final metric in path.computeMetrics()) {
        final sub = metric.extractPath(0, metric.length * p);
        canvas.drawPath(sub, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StadiumProgressPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

// ============================== 半圆菜单 Overlay ==============================

class _RadialMenuOverlay extends StatefulWidget {
  const _RadialMenuOverlay({
    required this.center,
    required this.pressArea,
    required this.items,
    required this.highlightedIndex,
    required this.radius,
  });

  final Offset center;
  final Rect? pressArea; // 悬浮条本体的全局矩形，作为替代显示的锚点
  final List<ProgressGestureAction> items;
  final int? highlightedIndex;
  final double radius;

  @override
  State<_RadialMenuOverlay> createState() => _RadialMenuOverlayState();
}

class _RadialMenuOverlayState extends State<_RadialMenuOverlay>
    with SingleTickerProviderStateMixin {
  // 菜单整体入场 fade 动画时长
  static const Duration _fadeInDuration = Duration(milliseconds: 180);

  // 顶部 tooltip 底部到半圆顶部之间的间隙（顶部项放大时直径 ~58dp）
  static const double _tooltipGap = 64.0;

  // 背景模糊与暗化稳态强度
  static const double _maxBlur = 8.0;
  static const double _maxDim = 0.22;

  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: _fadeInDuration,
  )..forward();

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final highlightedIndex = widget.highlightedIndex;
    final highlightedAction = (highlightedIndex != null &&
            highlightedIndex >= 0 &&
            highlightedIndex < items.length)
        ? items[highlightedIndex]
        : null;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _fadeController,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_fadeController.value);
          return Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: _maxBlur * t,
                    sigmaY: _maxBlur * t,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: _maxDim * t),
                  ),
                ),
              ),
              for (int i = 0; i < items.length; i++)
                _buildItem(context, i, items[i], t),
              if (widget.pressArea != null)
                _buildPressAreaIndicator(context, widget.pressArea!, t),
              if (highlightedAction != null)
                _buildHeaderTooltip(context, highlightedAction, t),
            ],
          );
        },
      ),
    );
  }

  Offset _itemPosition(int index) {
    final n = widget.items.length;
    final double angle;
    if (n == 1) {
      angle = -math.pi / 2;
    } else {
      final step = math.pi / (n - 1);
      angle = -math.pi + index * step;
    }
    return Offset(
      widget.center.dx + widget.radius * math.cos(angle),
      widget.center.dy + widget.radius * math.sin(angle),
    );
  }

  Widget _buildItem(
    BuildContext context,
    int index,
    ProgressGestureAction action,
    double opacity,
  ) {
    final theme = Theme.of(context);
    final meta = progressGestureActionMeta(context, action);
    final isHighlighted = widget.highlightedIndex == index;
    const size = 48.0;
    final scale = isHighlighted ? 1.2 : 1.0;
    final pos = _itemPosition(index);

    return AnimatedPositioned(
      key: ValueKey('progress_gesture_item_$index'),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      left: pos.dx - size * scale / 2,
      top: pos.dy - size * scale / 2,
      width: size * scale,
      height: size * scale,
      child: Opacity(
        opacity: opacity,
        child: Material(
          color: isHighlighted
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          shape: const CircleBorder(),
          elevation: isHighlighted ? 6 : 2,
          shadowColor: isHighlighted
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : Colors.black26,
          child: Icon(
            meta.icon,
            size: 24 * scale,
            color: isHighlighted
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderTooltip(
    BuildContext context,
    ProgressGestureAction action,
    double opacity,
  ) {
    final theme = Theme.of(context);
    final meta = progressGestureActionMeta(context, action);
    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    const margin = 16.0;

    // 基于悬浮条本身（center.dx）居中，双栏布局下也正确
    final clampedX = widget.center.dx.clamp(margin, screenWidth - margin);
    final bottomY = (widget.center.dy - widget.radius - _tooltipGap).clamp(
      mq.padding.top + 56.0,
      mq.size.height,
    );

    return Positioned(
      left: clampedX,
      top: bottomY,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -1.0),
        child: Opacity(
          opacity: opacity,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: screenWidth - margin * 2),
            child: Material(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(24),
              elevation: 6,
              shadowColor: theme.colorScheme.primary.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      meta.icon,
                      size: 18,
                      color: theme.colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        meta.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 在悬浮条原位置画一个 primary 实心 pill 作为替代显示，
  /// 让用户在模糊背景下仍能看到"我刚才按的入口"。
  Widget _buildPressAreaIndicator(
    BuildContext context,
    Rect rect,
    double opacity,
  ) {
    final theme = Theme.of(context);
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Material(
            color: theme.colorScheme.primary,
            shape: const StadiumBorder(),
            elevation: 6,
            shadowColor: theme.colorScheme.primary.withValues(alpha: 0.4),
            child: Center(
              child: Icon(
                Icons.touch_app_rounded,
                size: 20,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================== 滑动预览 Overlay ==============================

class _SwipePreviewOverlay extends StatelessWidget {
  const _SwipePreviewOverlay({
    required this.origin,
    required this.direction,
    required this.action,
    required this.triggerable,
    required this.delta,
    required this.triggerDistance,
  });

  /// 悬浮条本体的全局坐标（中心点）
  final Offset origin;
  final _SwipeDirection? direction;
  final ProgressGestureAction? action;
  final bool triggerable;
  final Offset delta;
  final double triggerDistance;

  static const double _pillBaseOffset = 56;
  static const double _pillFollowFactor = 0.55;
  static const double _pillFollowMax = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (action == null || direction == null) {
      return const IgnorePointer(child: SizedBox.shrink());
    }
    final meta = progressGestureActionMeta(context, action!);
    final progress = (math.max(delta.dx.abs(), delta.dy.abs()) / triggerDistance)
        .clamp(0.0, 1.0);

    Offset pillOffset;
    switch (direction!) {
      case _SwipeDirection.left:
        final dx = (delta.dx * _pillFollowFactor).clamp(-_pillFollowMax, 0.0);
        pillOffset = Offset(dx, -_pillBaseOffset);
      case _SwipeDirection.right:
        final dx = (delta.dx * _pillFollowFactor).clamp(0.0, _pillFollowMax);
        pillOffset = Offset(dx, -_pillBaseOffset);
      case _SwipeDirection.up:
        final dy =
            (delta.dy * _pillFollowFactor).clamp(-_pillFollowMax, 0.0) -
                _pillBaseOffset;
        pillOffset = Offset(0, dy);
    }

    final pillCenter = origin + pillOffset;
    final bgColor = triggerable
        ? theme.colorScheme.primary
        : Color.lerp(
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.primary,
            progress * 0.4,
          )!;
    final fgColor = triggerable
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final shadow = triggerable
        ? theme.colorScheme.primary.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.12);

    final screenSize = MediaQuery.of(context).size;
    final clampedX = pillCenter.dx.clamp(60.0, screenSize.width - 60.0);
    final clampedY = pillCenter.dy.clamp(40.0, screenSize.height - 40.0);

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: clampedX,
            top: clampedY,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutBack,
                scale: triggerable ? 1.04 : 1.0,
                child: Material(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(20),
                  elevation: triggerable ? 6 : 3,
                  shadowColor: shadow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(meta.icon, size: 18, color: fgColor),
                        const SizedBox(width: 6),
                        Text(
                          meta.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: fgColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
