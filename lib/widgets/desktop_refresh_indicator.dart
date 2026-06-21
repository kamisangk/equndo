import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../providers/shortcut_provider.dart';
import '../utils/platform_utils.dart';

/// 带桌面端快捷键刷新支持的 RefreshIndicator
///
/// 用法：直接替换 `RefreshIndicator`，桌面端按刷新快捷键时
/// 会自动触发下拉刷新动画（与手动下拉效果一致）。
///
/// [refreshNotifier] 指定监听哪个信号：
/// - `desktopRefreshNotifier`（默认）：Navigator push 的独立页面
/// - `masterRefreshNotifier`：双栏主面板（话题列表等）
/// - `detailRefreshNotifier`：双栏详情面板
class DesktopRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final ValueListenable<int>? refreshNotifier;
  final GlobalKey<RefreshIndicatorState>? refreshIndicatorKey;

  /// 额外的可见性条件（如 isCurrentTab、isActive），
  /// 不满足时不响应信号
  final bool Function()? shouldRefresh;

  /// 透传给 RefreshIndicator
  final bool Function(ScrollNotification)? notificationPredicate;

  const DesktopRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.refreshNotifier,
    this.refreshIndicatorKey,
    this.shouldRefresh,
    this.notificationPredicate,
  });

  @override
  State<DesktopRefreshIndicator> createState() =>
      _DesktopRefreshIndicatorState();
}

class _DesktopRefreshIndicatorState extends State<DesktopRefreshIndicator> {
  late final GlobalKey<RefreshIndicatorState> _key;
  ValueListenable<int>? _notifier;

  @override
  void initState() {
    super.initState();
    _key = widget.refreshIndicatorKey ?? GlobalKey<RefreshIndicatorState>();
    if (PlatformUtils.isDesktop) {
      _notifier = widget.refreshNotifier ?? desktopRefreshNotifier;
      _notifier!.addListener(_onSignal);
    }
  }

  @override
  void dispose() {
    _notifier?.removeListener(_onSignal);
    super.dispose();
  }

  void _onSignal() {
    if (!mounted) return;
    if (widget.shouldRefresh != null && !widget.shouldRefresh!()) return;
    _key.currentState?.show();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      key: _key,
      onRefresh: widget.onRefresh,
      notificationPredicate:
          widget.notificationPredicate ?? defaultScrollNotificationPredicate,
      child: widget.child,
    );
  }
}
