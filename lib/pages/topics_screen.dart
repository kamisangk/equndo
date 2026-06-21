import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../l10n/s.dart';
import '../navigation/nav_action_bus.dart';
import '../providers/core_providers.dart';
import '../providers/preferences_provider.dart';
import '../providers/selected_topic_provider.dart';
import '../providers/shortcut_provider.dart';
import '../utils/platform_utils.dart';
import '../utils/blur_config.dart';
import '../utils/responsive.dart';
import '../widgets/layout/master_detail_layout.dart';
import 'equn_thread_detail_page.dart';
import 'create_topic_page.dart';
import 'topics_page.dart';
import '../providers/topic_list/tab_state_provider.dart';

/// 话题屏幕
/// 在手机上显示单栏列表，平板上显示 Master-Detail 双栏
class TopicsScreen extends ConsumerStatefulWidget {
  const TopicsScreen({super.key, this.isActive = true});

  /// 是否为当前活跃的 tab（IndexedStack 中非活跃时跳过导航）
  final bool isActive;

  @override
  ConsumerState<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends ConsumerState<TopicsScreen> {
  bool? _lastCanShowDetailPane;
  bool _isAutoSwitching = false;

  /// 当前活跃的 provider 实例 ID，布局切换时复用
  String? _activeInstanceId;
  int? _activeTopicId;

  /// topicId 变化时生成新 instanceId，相同 topicId 复用
  /// 如果提供了 existingInstanceId（如从全屏详情页传回），直接采用
  String _getOrCreateInstanceId(int topicId, {String? existingInstanceId}) {
    if (existingInstanceId != null) {
      _activeTopicId = topicId;
      _activeInstanceId = existingInstanceId;
      return existingInstanceId;
    }
    if (_activeTopicId != topicId) {
      _activeTopicId = topicId;
      _activeInstanceId = const Uuid().v4();
    }
    return _activeInstanceId!;
  }

  void _maybePushDetail(
    SelectedTopicState selectedTopic,
    bool canShowDetailPane,
  ) {
    if (_isAutoSwitching) return;

    // IndexedStack 中非活跃 tab 仍需更新状态，避免切回时误触发
    if (!widget.isActive) {
      _lastCanShowDetailPane = canShowDetailPane;
      return;
    }

    // 当前路由不在栈顶时（有其他页面覆盖），根据布局判断是否清除选中
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      // 单栏模式下选中状态没有意义（看不到），清除并释放 provider 缓存
      if (!canShowDetailPane && selectedTopic.hasSelection) {
        _activeTopicId = null;
        _activeInstanceId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(selectedTopicProvider.notifier).clear();
        });
      }
      // 双栏模式下保留选中状态（从详情面板 push 到其他页面，回来还要显示）
      _lastCanShowDetailPane = canShowDetailPane;
      return;
    }

    final previous = _lastCanShowDetailPane;
    _lastCanShowDetailPane = canShowDetailPane;

    // 从双栏切到单栏时自动 push；如果 previous 为空但当前为单栏且有选中，
    // 也执行 push，避免因状态丢失导致无法自动进入详情。
    if (!canShowDetailPane &&
        selectedTopic.hasSelection &&
        (previous == null || previous == true)) {
      final topicId = selectedTopic.topicId;
      if (topicId == null) return;

      _isAutoSwitching = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final navigator = Navigator.of(context);
        ref.read(selectedTopicProvider.notifier).clear();
        navigator
            .push(
              MaterialPageRoute(
                builder: (_) => EqunThreadDetailPage(
                  tid: topicId,
                  initialTitle: selectedTopic.initialTitle,
                ),
              ),
            )
            .whenComplete(() {
              if (mounted) {
                setState(() => _isAutoSwitching = false);
              }
            });
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTopic = ref.watch(selectedTopicProvider);
    final canShowDetailPane = MasterDetailLayout.canShowBothPanesFor(context);
    final user = ref.watch(currentUserProvider).value;

    // 监听底栏派发的快捷动作（仅活跃 tab 响应）
    ref.listen(navActionBusProvider, (_, event) {
      if (event == null) return;
      if (event.targetId != NavEntryIds.home) return;
      if (!widget.isActive) return;
      switch (event.action) {
        case NavAction.scrollToTop:
          ref.read(fabRefreshModeProvider.notifier).state = false;
          ref.read(scrollToTopProvider.notifier).trigger();
          break;
        case NavAction.refresh:
          ref.read(fabRefreshModeProvider.notifier).state = false;
          ref.read(scrollToTopProvider.notifier).trigger();
          ref.read(fabRefreshSignalProvider.notifier).trigger();
          ref.resetNavScrollProgress(NavEntryIds.home);
          break;
      }
    });

    _maybePushDetail(selectedTopic, canShowDetailPane);

    // 统一使用 MasterDetailLayout 处理所有情况
    // 手机/平板单栏：只显示 master
    // 平板双栏：显示 master + detail
    return MasterDetailLayout(
      master: _wrapPaneTap(ActivePane.master, const TopicsPage()),
      detail: selectedTopic.hasSelection && canShowDetailPane
          ? _wrapPaneTap(
              ActivePane.detail,
              TopicDetailPane(
                key: ValueKey(selectedTopic.topicId),
                topicId: selectedTopic.topicId!,
                parentActive: widget.isActive,
                instanceId: _getOrCreateInstanceId(
                  selectedTopic.topicId!,
                  existingInstanceId: selectedTopic.instanceId,
                ),
                initialTitle: selectedTopic.initialTitle,
                scrollToPostNumber: selectedTopic.scrollToPostNumber,
              ),
            )
          : null,
      masterFloatingActionButton: user != null
          ? _TopicsFab(onCreateTopic: _showEqunComposeNotReady)
          : null,
    );
  }

  /// 包裹面板：点击切换活跃面板 + Tab 切换时短暂高亮顶部指示条
  Widget _wrapPaneTap(ActivePane pane, Widget child) {
    if (!PlatformUtils.isDesktop) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        // 点击切换时不显示指示器（鼠标用户不需要）
        if (ref.read(activePaneProvider) != pane) {
          ref.read(activePaneProvider.notifier).state = pane;
        }
      },
      child: _PaneActiveIndicator(pane: pane, child: child),
    );
  }

  void _showEqunComposeNotReady() {
    final categoryId = ref.read(currentTabCategoryIdProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateTopicPage(
          initialCategoryId: categoryId,
          useEqunComposer: true,
        ),
      ),
    );
  }
}

/// 首页 FAB：向上滚动时切换为刷新按钮，正常模式下点击展开 Speed Dial 菜单
class _TopicsFab extends ConsumerStatefulWidget {
  const _TopicsFab({required this.onCreateTopic});

  final VoidCallback onCreateTopic;

  @override
  ConsumerState<_TopicsFab> createState() => _TopicsFabState();
}

class _TopicsFabState extends ConsumerState<_TopicsFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _expandAnimation;
  final LayerLink _layerLink = LayerLink();
  bool _isExpanded = false;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_isExpanded) {
      _close();
    } else {
      setState(() => _isExpanded = true);
      _controller.forward();
      _showOverlay();
      HapticFeedback.lightImpact();
    }
  }

  void _close({bool immediately = false}) {
    if (!_isExpanded) return;
    setState(() => _isExpanded = false);
    if (immediately) {
      _controller.stop();
      _controller.value = 0;
      _removeOverlay();
      return;
    }
    _controller.reverse().then((_) {
      _removeOverlay();
    });
  }

  void _showOverlay() {
    _removeOverlay();
    final theme = Theme.of(context);
    final dialogBlur = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(preferencesProvider).dialogBlur;

    // 桌面 acrylic 模式下 NavigationRail 背景透明，
    // BackdropFilter 对其模糊效果异常，需跳过该区域
    final showRail = Responsive.showNavigationRail(context);
    final hasAcrylic = Platform.isMacOS || Platform.isWindows;
    final blurLeftInset = (showRail && hasAcrylic) ? 72.0 : 0.0;
    final barrierColor = dialogBlur
        ? blurBarrierColor(Theme.of(context).brightness)
        : Colors.black26;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 全屏暗色遮罩 + 点击关闭
          GestureDetector(
            onTap: _close,
            behavior: HitTestBehavior.opaque,
            child: FadeTransition(
              opacity: _expandAnimation,
              child: ColoredBox(
                color: barrierColor,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // NavigationRail 补底：acrylic 模式下 Rail 背景透明，
          // 用 surface 色填充使遮罩可见
          if (dialogBlur && blurLeftInset > 0)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: blurLeftInset,
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _expandAnimation,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceDim,
                  ),
                ),
              ),
            ),
          // 模糊层：覆盖 body 区域（跳过透明的 NavigationRail）
          if (dialogBlur)
            Positioned.fill(
              left: blurLeftInset,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _expandAnimation,
                  builder: (context, child) {
                    final t = _expandAnimation.value;
                    if (t == 0) return child!;
                    return BackdropFilter(
                      filter: createBlurFilter(
                        (blurSigma * t).clamp(0.01, blurSigma),
                      ),
                      child: child,
                    );
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          // 主 FAB 副本（在模糊层之上，保持清晰）
          if (dialogBlur)
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.center,
              followerAnchor: Alignment.center,
              child: FloatingActionButton(
                heroTag: null,
                onPressed: _close,
                child: AnimatedRotation(
                  turns: 0.125,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.add),
                ),
              ),
            ),
          // 子按钮：定位到主 FAB 上方
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(0, -16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildMiniAction(
                  icon: Icons.edit_outlined,
                  label: context.l10n.topicsScreen_createTopic,
                  onTap: () {
                    _close(immediately: true);
                    widget.onCreateTopic();
                  },
                  theme: theme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  void _refreshTopics() {
    ref.read(fabRefreshModeProvider.notifier).state = false;
    ref.read(scrollToTopProvider.notifier).trigger();
    ref.read(fabRefreshSignalProvider.notifier).trigger();
  }

  @override
  Widget build(BuildContext context) {
    final showRefresh = ref.watch(fabRefreshModeProvider);

    // 刷新模式切换时自动收起
    if (showRefresh && _isExpanded) {
      _close();
    }

    // 刷新模式：简单的单按钮
    if (showRefresh) {
      return FloatingActionButton(
        heroTag: 'createTopic',
        onPressed: _refreshTopics,
        child: const Icon(Icons.refresh),
      );
    }

    // 主 FAB（作为锚点，子按钮在 Overlay 中定位到它上方）
    // 模糊开启时，展开后隐藏真实 FAB（overlay 中有 sharp 副本）
    final dialogBlur = ref.watch(
      preferencesProvider.select((p) => p.dialogBlur),
    );
    final hideFab = _isExpanded && dialogBlur;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Opacity(
        opacity: hideFab ? 0 : 1,
        child: FloatingActionButton(
          heroTag: 'createTopic',
          onPressed: _toggle,
          child: AnimatedRotation(
            turns: _isExpanded ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return FadeTransition(
      opacity: _expandAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.5),
          end: Offset.zero,
        ).animate(_expandAnimation),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FloatingActionButton.small(
              heroTag: 'fab_$label',
              onPressed: onTap,
              child: Icon(icon),
            ),
          ],
        ),
      ),
    );
  }
}

/// 面板活跃 HUD 指示器：Tab 切换时在面板中央短暂显示半透明浮层
class _PaneActiveIndicator extends ConsumerStatefulWidget {
  final ActivePane pane;
  final Widget child;

  const _PaneActiveIndicator({required this.pane, required this.child});

  @override
  ConsumerState<_PaneActiveIndicator> createState() =>
      _PaneActiveIndicatorState();
}

class _PaneActiveIndicatorState extends ConsumerState<_PaneActiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 仅监听键盘切换信号，点击切换不触发 HUD
    ref.listen(paneSwitchSignalProvider, (prev, next) {
      if (prev != next && ref.read(activePaneProvider) == widget.pane) {
        _anim.forward(from: 0).then((_) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) _anim.reverse();
          });
        });
      }
    });

    final theme = Theme.of(context);
    final label = widget.pane == ActivePane.master
        ? context.l10n.shortcuts_navigation
        : context.l10n.shortcuts_content;
    final icon = widget.pane == ActivePane.master
        ? Icons.list_rounded
        : Icons.article_rounded;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: FadeTransition(
                opacity: _anim,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.inverseSurface.withValues(
                      alpha: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: theme.colorScheme.onInverseSurface,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onInverseSurface,
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
    );
  }
}

/// 话题详情面板（用于双栏模式，不包含返回按钮）
class TopicDetailPane extends ConsumerWidget {
  const TopicDetailPane({
    super.key,
    required this.topicId,
    required this.parentActive,
    this.instanceId,
    this.initialTitle,
    this.scrollToPostNumber,
  });

  final int topicId;
  final bool parentActive;
  final String? instanceId;
  final String? initialTitle;
  final int? scrollToPostNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EqunThreadDetailPage(tid: topicId, initialTitle: initialTitle);
  }
}
