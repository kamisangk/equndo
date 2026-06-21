part of '../topic_detail_page.dart';

// ignore_for_file: invalid_use_of_protected_member

/// 过滤模式相关方法
extension _FilterActions on _TopicDetailPageState {
  bool _detailHasTargetPost(TopicDetail detail, {int? postNumber, int? postId}) {
    if (postId != null) {
      if (detail.postStream.stream.contains(postId)) return true;
      if (detail.postStream.posts.any((p) => p.id == postId)) return true;
    }
    if (postNumber != null) {
      if (detail.postStream.posts.any((p) => p.postNumber == postNumber)) return true;
    }
    return false;
  }

  Future<void> _reloadWithFilterFallback({required int postNumber, int? postId}) async {
    final params = _params;
    final notifier = ref.read(topicDetailProvider(params).notifier);
    final wasSummaryMode = notifier.isSummaryMode;
    final wasAuthorOnlyMode = notifier.isAuthorOnlyMode;
    final wasTopLevelMode = notifier.isTopLevelMode;

    setState(() => _isSwitchingMode = true);
    _controller.resetVisibility();

    try {
      await notifier.reloadWithPostNumber(postNumber);
      if (!mounted) return;

      final detail = ref.read(topicDetailProvider(params)).value;
      final hasTarget = detail != null && _detailHasTargetPost(detail, postNumber: postNumber, postId: postId);
      final shouldFallback = detail != null && _shouldFallbackFilter(detail, wasSummaryMode, wasAuthorOnlyMode, wasTopLevelMode);
      if (!hasTarget || shouldFallback) {
        _controller.resetVisibility();
        _controller.prepareJumpToPost(postNumber);
        await notifier.cancelFilterAndReloadWithPostNumber(postNumber);
      }
    } finally {
      if (mounted) {
        setState(() => _isSwitchingMode = false);
        _scheduleCheckTitleVisibility();
      }
    }
  }

  bool _shouldFallbackFilter(TopicDetail detail, bool wasSummaryMode, bool wasAuthorOnlyMode, bool wasTopLevelMode) {
    if (wasSummaryMode) {
      if (!detail.hasSummary) return true;
      if (detail.postsCount > 0 && detail.postStream.stream.length >= detail.postsCount) {
        return true;
      }
    }

    if (wasAuthorOnlyMode) {
      final author = detail.createdBy?.username;
      if (author == null || author.isEmpty) return true;
      final hasOtherUsers = detail.postStream.posts.any((p) => p.username != author);
      if (hasOtherUsers) return true;
    }

    // 只看顶层模式下跳转到楼中楼帖子时需要取消过滤
    if (wasTopLevelMode) return true;

    return false;
  }

  Future<void> _handleShowTopReplies() async {
    final params = _params;
    final notifier = ref.read(topicDetailProvider(params).notifier);

    setState(() => _isSwitchingMode = true);

    _controller.prepareJumpToPost(1);
    _controller.skipNextJumpHighlight = true;
    _controller.resetVisibility();

    await notifier.showTopReplies();

    if (mounted) {
      setState(() => _isSwitchingMode = false);
      _scheduleCheckTitleVisibility();
    }
  }

  Future<void> _handleCancelFilter() async {
    // 嵌套模式：直接退出，不需要重新加载
    if (_isNestedView) {
      setState(() => _isNestedView = false);
      _scheduleCheckTitleVisibility();
      return;
    }

    final params = _params;
    final notifier = ref.read(topicDetailProvider(params).notifier);

    setState(() => _isSwitchingMode = true);

    _controller.prepareJumpToPost(1);
    _controller.skipNextJumpHighlight = true;
    _controller.resetVisibility();

    await notifier.cancelFilter();

    if (mounted) {
      setState(() => _isSwitchingMode = false);
      _scheduleCheckTitleVisibility();
    }
  }

  Future<void> _handleShowTopLevelReplies() async {
    final params = _params;
    final notifier = ref.read(topicDetailProvider(params).notifier);

    setState(() => _isSwitchingMode = true);

    _controller.prepareJumpToPost(1);
    _controller.skipNextJumpHighlight = true;
    _controller.resetVisibility();

    try {
      await notifier.showTopLevelReplies();
    } finally {
      if (mounted) {
        setState(() => _isSwitchingMode = false);
        _scheduleCheckTitleVisibility();
      }
    }
  }

  Future<void> _handleShowAuthorOnly() async {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;
    final notifier = ref.read(topicDetailProvider(params).notifier);

    final authorUsername = detail?.createdBy?.username;
    if (authorUsername == null || authorUsername.isEmpty) return;

    setState(() => _isSwitchingMode = true);

    _controller.prepareJumpToPost(1);
    _controller.skipNextJumpHighlight = true;
    _controller.resetVisibility();

    await notifier.showAuthorOnly(authorUsername);

    if (mounted) {
      setState(() => _isSwitchingMode = false);
      _scheduleCheckTitleVisibility();
    }
  }

  /// 从菜单打开筛选面板
  void _showFilterSheet() {
    final params = _params;
    final notifier = ref.read(topicDetailProvider(params).notifier);
    final detail = ref.read(topicDetailProvider(params)).value;
    final hasActiveFilter =
        notifier.isSummaryMode || notifier.isAuthorOnlyMode || notifier.isTopLevelMode || _isNestedView;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (detail?.hasSummary ?? false)
                ListTile(
                  leading: Icon(
                    notifier.isSummaryMode ? Icons.local_fire_department : Icons.local_fire_department_outlined,
                  ),
                  title: Text(context.l10n.topicDetail_hotOnly),
                  trailing: notifier.isSummaryMode
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (notifier.isSummaryMode) {
                      _handleCancelFilter();
                    } else {
                      _handleShowTopReplies();
                    }
                  },
                ),
              ListTile(
                leading: Icon(
                  notifier.isAuthorOnlyMode ? Icons.person : Icons.person_outline,
                ),
                title: Text(context.l10n.topicDetail_authorOnly),
                trailing: notifier.isAuthorOnlyMode
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (notifier.isAuthorOnlyMode) {
                    _handleCancelFilter();
                  } else {
                    _handleShowAuthorOnly();
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  notifier.isTopLevelMode ? Icons.account_tree : Icons.account_tree_outlined,
                ),
                title: Text(context.l10n.topicDetail_topLevelOnly),
                trailing: notifier.isTopLevelMode
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (notifier.isTopLevelMode) {
                    _handleCancelFilter();
                  } else {
                    _handleShowTopLevelReplies();
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  _isNestedView ? Icons.forum : Icons.forum_outlined,
                ),
                title: Text(context.l10n.nested_title),
                trailing: _isNestedView
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleNestedView();
                },
              ),
              if (hasActiveFilter) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.filter_list_off, color: theme.colorScheme.error),
                  title: Text(
                    context.l10n.common_cancel,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleCancelFilter();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
