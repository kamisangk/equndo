import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ============================================================
// 以下常量和私有类复制自 Flutter popup_menu.dart，
// 因为内部类 (_PopupMenuRoute 等) 不可访问，必须复制才能自定义 barrier 行为。
// ============================================================

const Duration _kMenuDuration = Duration(milliseconds: 300);
const double _kMenuCloseIntervalEnd = 2.0 / 3.0;
const double _kMenuMaxWidth = 5.0 * _kMenuWidthStep;
const double _kMenuMinWidth = 2.0 * _kMenuWidthStep;
const double _kMenuWidthStep = 56.0;
const double _kMenuScreenPadding = 8.0;

// ------ _MenuItem / _RenderMenuItem ------

class _MenuItem extends SingleChildRenderObjectWidget {
  const _MenuItem({required this.onLayout, required super.child});

  final ValueChanged<Size> onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMenuItem(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMenuItem renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _RenderMenuItem extends RenderShiftedBox {
  _RenderMenuItem(this.onLayout, [RenderBox? child]) : super(child);

  ValueChanged<Size> onLayout;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child?.getDryLayout(constraints) ?? Size.zero;

  @override
  void performLayout() {
    if (child == null) {
      size = Size.zero;
    } else {
      child!.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(child!.size);
      final BoxParentData childParentData =
          child!.parentData! as BoxParentData;
      childParentData.offset = Offset.zero;
    }
    onLayout(size);
  }
}

// ------ _PopupMenu widget ------

class _PopupMenu<T> extends StatefulWidget {
  const _PopupMenu({
    super.key,
    required this.itemKeys,
    required this.route,
    required this.semanticLabel,
    this.constraints,
    required this.clipBehavior,
  });

  final List<GlobalKey> itemKeys;
  final _SwipeDismissiblePopupRoute<T> route;
  final String? semanticLabel;
  final BoxConstraints? constraints;
  final Clip clipBehavior;

  @override
  State<_PopupMenu<T>> createState() => _PopupMenuState<T>();
}

class _PopupMenuState<T> extends State<_PopupMenu<T>> {
  List<CurvedAnimation> _opacities = const <CurvedAnimation>[];

  @override
  void initState() {
    super.initState();
    _setOpacities();
  }

  @override
  void didUpdateWidget(covariant _PopupMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route.items.length != widget.route.items.length ||
        oldWidget.route.animation != widget.route.animation) {
      _setOpacities();
    }
  }

  void _setOpacities() {
    for (final CurvedAnimation opacity in _opacities) {
      opacity.dispose();
    }
    final List<CurvedAnimation> newOpacities = <CurvedAnimation>[];
    final double unit = 1.0 / (widget.route.items.length + 1.5);
    for (int i = 0; i < widget.route.items.length; i += 1) {
      final double start = (i + 1) * unit;
      final double end = clampDouble(start + 1.5 * unit, 0.0, 1.0);
      final CurvedAnimation opacity = CurvedAnimation(
        parent: widget.route.animation!,
        curve: Interval(start, end),
      );
      newOpacities.add(opacity);
    }
    _opacities = newOpacities;
  }

  @override
  void dispose() {
    for (final CurvedAnimation opacity in _opacities) {
      opacity.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double unit = 1.0 / (widget.route.items.length + 1.5);
    final List<Widget> children = <Widget>[];
    final ThemeData theme = Theme.of(context);
    final PopupMenuThemeData popupMenuTheme = PopupMenuTheme.of(context);

    for (int i = 0; i < widget.route.items.length; i += 1) {
      final CurvedAnimation opacity = _opacities[i];
      Widget item = widget.route.items[i];
      if (widget.route.initialValue != null &&
          widget.route.items[i].represents(widget.route.initialValue)) {
        item = ColoredBox(color: theme.highlightColor, child: item);
      }
      children.add(
        _MenuItem(
          onLayout: (Size size) {
            widget.route.itemSizes[i] = size;
          },
          child: FadeTransition(
            key: widget.itemKeys[i],
            opacity: opacity,
            child: item,
          ),
        ),
      );
    }

    final CurveTween opacity =
        CurveTween(curve: const Interval(0.0, 1.0 / 3.0));
    final CurveTween width = CurveTween(curve: Interval(0.0, unit));
    final CurveTween height =
        CurveTween(curve: Interval(0.0, unit * widget.route.items.length));

    final Widget child = ConstrainedBox(
      constraints: widget.constraints ??
          const BoxConstraints(
            minWidth: _kMenuMinWidth,
            maxWidth: _kMenuMaxWidth,
          ),
      child: IntrinsicWidth(
        stepWidth: _kMenuWidthStep,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: widget.semanticLabel,
          child: SingleChildScrollView(
            padding: widget.route.menuPadding ??
                popupMenuTheme.menuPadding ??
                const EdgeInsetsDirectional.symmetric(vertical: 8.0),
            child: ListBody(children: children),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: widget.route.animation!,
      builder: (BuildContext context, Widget? child) {
        return FadeTransition(
          opacity: opacity.animate(widget.route.animation!),
          child: Material(
            shape: widget.route.shape ?? popupMenuTheme.shape,
            color: widget.route.color ?? popupMenuTheme.color,
            clipBehavior: widget.clipBehavior,
            type: MaterialType.card,
            elevation:
                widget.route.elevation ?? popupMenuTheme.elevation ?? 8.0,
            shadowColor: widget.route.shadowColor ?? popupMenuTheme.shadowColor,
            surfaceTintColor: widget.route.surfaceTintColor ??
                popupMenuTheme.surfaceTintColor,
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              widthFactor: width.evaluate(widget.route.animation!),
              heightFactor: height.evaluate(widget.route.animation!),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

// ------ _PopupMenuRouteLayout ------

class _PopupMenuRouteLayout extends SingleChildLayoutDelegate {
  _PopupMenuRouteLayout(
    this.position,
    this.itemSizes,
    this.selectedItemIndex,
    this.textDirection,
    this.padding,
    this.avoidBounds,
  );

  final RelativeRect position;
  List<Size?> itemSizes;
  final int? selectedItemIndex;
  final TextDirection textDirection;
  EdgeInsets padding;
  final Set<Rect> avoidBounds;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest)
        .deflate(const EdgeInsets.all(_kMenuScreenPadding) + padding);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double y = position.top;
    double x;
    if (position.left > position.right) {
      x = size.width - position.right - childSize.width;
    } else if (position.left < position.right) {
      x = position.left;
    } else {
      x = switch (textDirection) {
        TextDirection.rtl => size.width - position.right - childSize.width,
        TextDirection.ltr => position.left,
      };
    }
    final Offset wantedPosition = Offset(x, y);
    final Offset originCenter = position.toRect(Offset.zero & size).center;
    final Iterable<Rect> subScreens =
        DisplayFeatureSubScreen.subScreensInBounds(
      Offset.zero & size,
      avoidBounds,
    );
    final Rect subScreen = _closestScreen(subScreens, originCenter);
    return _fitInsideScreen(subScreen, childSize, wantedPosition);
  }

  Rect _closestScreen(Iterable<Rect> screens, Offset point) {
    Rect closest = screens.first;
    for (final Rect screen in screens) {
      if ((screen.center - point).distance <
          (closest.center - point).distance) {
        closest = screen;
      }
    }
    return closest;
  }

  Offset _fitInsideScreen(Rect screen, Size childSize, Offset wantedPosition) {
    double x = wantedPosition.dx;
    double y = wantedPosition.dy;
    if (x < screen.left + _kMenuScreenPadding + padding.left) {
      x = screen.left + _kMenuScreenPadding + padding.left;
    } else if (x + childSize.width >
        screen.right - _kMenuScreenPadding - padding.right) {
      x = screen.right -
          childSize.width -
          _kMenuScreenPadding -
          padding.right;
    }
    if (y < screen.top + _kMenuScreenPadding + padding.top) {
      y = _kMenuScreenPadding + padding.top;
    } else if (y + childSize.height >
        screen.bottom - _kMenuScreenPadding - padding.bottom) {
      y = screen.bottom -
          childSize.height -
          _kMenuScreenPadding -
          padding.bottom;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopupMenuRouteLayout oldDelegate) {
    assert(itemSizes.length == oldDelegate.itemSizes.length);
    return position != oldDelegate.position ||
        selectedItemIndex != oldDelegate.selectedItemIndex ||
        textDirection != oldDelegate.textDirection ||
        !listEquals(itemSizes, oldDelegate.itemSizes) ||
        padding != oldDelegate.padding ||
        !setEquals(avoidBounds, oldDelegate.avoidBounds);
  }
}

// ============================================================
// 自定义 Route：barrier 支持滑动关闭
// ============================================================

class _SwipeDismissiblePopupRoute<T> extends PopupRoute<T> {
  _SwipeDismissiblePopupRoute({
    required this.position,
    required this.items,
    required this.itemKeys,
    this.initialValue,
    this.elevation,
    this.surfaceTintColor,
    this.shadowColor,
    required this.barrierLabel,
    this.semanticLabel,
    this.shape,
    this.menuPadding,
    this.color,
    required this.capturedThemes,
    this.constraints,
    required this.clipBehavior,
    super.settings,
    this.popUpAnimationStyle,
  }) : itemSizes = List<Size?>.filled(items.length, null),
       super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final List<GlobalKey> itemKeys;
  final List<Size?> itemSizes;
  final T? initialValue;
  final double? elevation;
  final Color? surfaceTintColor;
  final Color? shadowColor;
  final String? semanticLabel;
  final ShapeBorder? shape;
  final EdgeInsetsGeometry? menuPadding;
  final Color? color;
  final CapturedThemes capturedThemes;
  final BoxConstraints? constraints;
  final Clip clipBehavior;
  final AnimationStyle? popUpAnimationStyle;

  CurvedAnimation? _animation;

  @override
  Animation<double> createAnimation() {
    if (popUpAnimationStyle != AnimationStyle.noAnimation) {
      return _animation ??= CurvedAnimation(
        parent: super.createAnimation(),
        curve: popUpAnimationStyle?.curve ?? Curves.linear,
        reverseCurve: popUpAnimationStyle?.reverseCurve ??
            const Interval(0.0, _kMenuCloseIntervalEnd),
      );
    }
    return super.createAnimation();
  }

  @override
  Duration get transitionDuration =>
      popUpAnimationStyle?.duration ?? _kMenuDuration;

  // 关键：禁用框架自带的 barrier，改由 buildPage 中自行处理
  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  final String barrierLabel;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    int? selectedItemIndex;
    if (initialValue != null) {
      for (int index = 0;
          selectedItemIndex == null && index < items.length;
          index += 1) {
        if (items[index].represents(initialValue)) {
          selectedItemIndex = index;
        }
      }
    }

    final Widget menu = _PopupMenu<T>(
      route: this,
      itemKeys: itemKeys,
      semanticLabel: semanticLabel,
      constraints: constraints,
      clipBehavior: clipBehavior,
    );

    final MediaQueryData mediaQuery = MediaQuery.of(context);

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: Builder(
        builder: (context) {
          return Stack(
            children: [
              // 底层：自定义 barrier（可响应 tap 和垂直滑动）
              _SwipeBarrier(
                onDismiss: () => Navigator.of(context).pop(),
              ),
              // 上层：菜单内容（优先接收手势事件）
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return CustomSingleChildLayout(
                    delegate: _PopupMenuRouteLayout(
                      position,
                      itemSizes,
                      selectedItemIndex,
                      Directionality.of(context),
                      mediaQuery.padding,
                      DisplayFeatureSubScreen.avoidBounds(mediaQuery).toSet(),
                    ),
                    child: capturedThemes.wrap(menu),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _animation?.dispose();
    super.dispose();
  }
}

/// 自定义 barrier：支持点击和垂直滑动关闭。
///
/// 在 [Stack] 中处于菜单内容的 **下层**，所以当手指在菜单上时，
/// 菜单内容会优先接收事件，此 barrier 不会响应。
class _SwipeBarrier extends StatefulWidget {
  const _SwipeBarrier({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  State<_SwipeBarrier> createState() => _SwipeBarrierState();
}

class _SwipeBarrierState extends State<_SwipeBarrier> {
  double _totalDragDistance = 0;
  bool _dismissed = false;
  static const double _dismissThreshold = 20.0;

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss,
        onVerticalDragStart: (_) {
          _totalDragDistance = 0;
        },
        onVerticalDragUpdate: (details) {
          _totalDragDistance += details.delta.dy.abs();
          if (_totalDragDistance >= _dismissThreshold) {
            _dismiss();
          }
        },
      ),
    );
  }
}

// ============================================================
// 公开 API
// ============================================================

/// 显示支持滑动空白区域关闭的弹出菜单。
///
/// 功能与 [showMenu] 一致，但弹出菜单外的空白区域（barrier）
/// 除了支持点击关闭外，还支持垂直滑动关闭。
Future<T?> showSwipeDismissibleMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? elevation,
  Color? shadowColor,
  Color? surfaceTintColor,
  String? semanticLabel,
  ShapeBorder? shape,
  EdgeInsetsGeometry? menuPadding,
  Color? color,
  bool useRootNavigator = false,
  BoxConstraints? constraints,
  Clip clipBehavior = Clip.none,
  RouteSettings? routeSettings,
  AnimationStyle? popUpAnimationStyle,
  bool? requestFocus,
}) {
  assert(items.isNotEmpty);

  switch (Theme.of(context).platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      break;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      semanticLabel ??= MaterialLocalizations.of(context).popupMenuLabel;
  }

  final List<GlobalKey> menuItemKeys = List<GlobalKey>.generate(
    items.length,
    (int index) => GlobalKey(),
  );
  final NavigatorState navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  );
  return navigator.push(
    _SwipeDismissiblePopupRoute<T>(
      position: position,
      items: items,
      itemKeys: menuItemKeys,
      initialValue: initialValue,
      elevation: elevation,
      shadowColor: shadowColor,
      surfaceTintColor: surfaceTintColor,
      semanticLabel: semanticLabel,
      barrierLabel: MaterialLocalizations.of(context).menuDismissLabel,
      shape: shape,
      menuPadding: menuPadding,
      color: color,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      constraints: constraints,
      clipBehavior: clipBehavior,
      settings: routeSettings,
      popUpAnimationStyle: popUpAnimationStyle,
    ),
  );
}

/// 支持滑动空白区域关闭的 PopupMenuButton。
///
/// 在原生 [PopupMenuButton] 基础上，额外支持在 barrier（菜单外的空白区域）
/// 上进行垂直滑动来关闭菜单，改善移动端体验。
class SwipeDismissiblePopupMenuButton<T> extends StatefulWidget {
  const SwipeDismissiblePopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.initialValue,
    this.onOpened,
    this.onSelected,
    this.onCanceled,
    this.tooltip,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.padding = const EdgeInsets.all(8.0),
    this.menuPadding,
    this.child,
    this.borderRadius,
    this.splashRadius,
    this.icon,
    this.iconSize,
    this.offset = Offset.zero,
    this.enabled = true,
    this.shape,
    this.color,
    this.iconColor,
    this.enableFeedback,
    this.constraints,
    this.position,
    this.clipBehavior = Clip.none,
    this.useRootNavigator = false,
    this.popUpAnimationStyle,
    this.routeSettings,
    this.style,
    this.requestFocus,
  }) : assert(
         !(child != null && icon != null),
         'You can only pass [child] or [icon], not both.',
       );

  final PopupMenuItemBuilder<T> itemBuilder;
  final T? initialValue;
  final VoidCallback? onOpened;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? menuPadding;
  final Widget? child;
  final BorderRadius? borderRadius;
  final double? splashRadius;
  final Widget? icon;
  final double? iconSize;
  final Offset offset;
  final bool enabled;
  final ShapeBorder? shape;
  final Color? color;
  final Color? iconColor;
  final bool? enableFeedback;
  final BoxConstraints? constraints;
  final PopupMenuPosition? position;
  final Clip clipBehavior;
  final bool useRootNavigator;
  final AnimationStyle? popUpAnimationStyle;
  final RouteSettings? routeSettings;
  final ButtonStyle? style;
  final bool? requestFocus;

  @override
  State<SwipeDismissiblePopupMenuButton<T>> createState() =>
      _SwipeDismissiblePopupMenuButtonState<T>();
}

class _SwipeDismissiblePopupMenuButtonState<T>
    extends State<SwipeDismissiblePopupMenuButton<T>> {
  void showButtonMenu() {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay = Navigator.of(
      context,
      rootNavigator: widget.useRootNavigator,
    ).overlay!.context.findRenderObject()! as RenderBox;

    final PopupMenuThemeData popupMenuTheme = PopupMenuTheme.of(context);
    final PopupMenuPosition popupMenuPosition =
        widget.position ?? popupMenuTheme.position ?? PopupMenuPosition.over;

    late Offset offset;
    switch (popupMenuPosition) {
      case PopupMenuPosition.over:
        offset = widget.offset;
      case PopupMenuPosition.under:
        offset = Offset(0.0, button.size.height) + widget.offset;
        if (widget.child == null) {
          offset -= Offset(0.0, widget.padding.vertical / 2);
        }
    }

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(offset, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero) + offset,
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final List<PopupMenuEntry<T>> items = widget.itemBuilder(context);
    if (items.isEmpty) return;

    widget.onOpened?.call();

    showSwipeDismissibleMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: widget.initialValue,
      elevation: widget.elevation,
      shadowColor: widget.shadowColor,
      surfaceTintColor: widget.surfaceTintColor,
      shape: widget.shape,
      menuPadding: widget.menuPadding,
      color: widget.color,
      constraints: widget.constraints,
      clipBehavior: widget.clipBehavior,
      useRootNavigator: widget.useRootNavigator,
      popUpAnimationStyle: widget.popUpAnimationStyle,
      routeSettings: widget.routeSettings,
      requestFocus: widget.requestFocus,
    ).then<void>((T? newValue) {
      if (!mounted) return;
      if (newValue == null) {
        widget.onCanceled?.call();
        return;
      }
      widget.onSelected?.call(newValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    final IconThemeData iconTheme = IconTheme.of(context);
    final PopupMenuThemeData popupMenuTheme = PopupMenuTheme.of(context);
    final bool enableFeedback =
        widget.enableFeedback ?? popupMenuTheme.enableFeedback ?? true;

    if (widget.child != null) {
      return Tooltip(
        message: widget.tooltip ??
            MaterialLocalizations.of(context).showMenuTooltip,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: widget.enabled ? showButtonMenu : null,
          canRequestFocus: widget.enabled,
          radius: widget.splashRadius,
          enableFeedback: enableFeedback,
          child: widget.child,
        ),
      );
    }

    return IconButton(
      icon: widget.icon ?? Icon(Icons.adaptive.more),
      padding: widget.padding,
      splashRadius: widget.splashRadius,
      iconSize: widget.iconSize ?? popupMenuTheme.iconSize ?? iconTheme.size,
      color: widget.iconColor ?? popupMenuTheme.iconColor ?? iconTheme.color,
      tooltip: widget.tooltip ??
          MaterialLocalizations.of(context).showMenuTooltip,
      onPressed: widget.enabled ? showButtonMenu : null,
      enableFeedback: enableFeedback,
      style: widget.style,
    );
  }
}
