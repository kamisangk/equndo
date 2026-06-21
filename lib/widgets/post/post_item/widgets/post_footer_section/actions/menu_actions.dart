part of '../post_footer_section.dart';

extension _PostFooterMenuActions on _PostFooterSectionState {
  Future<void> _sharePost() async {
    final url = EqunThreadUrl.thread(widget.topicId);
    await SharePlus.instance.share(ShareParams(text: url));
  }

  void _showFlagDialog(BuildContext context) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PostFlagSheet(
        postId: widget.post.id,
        postUsername: widget.post.username,
        service: _service,
        onSuccess: () => ToastService.showSuccess(S.current.post_flagSubmitted),
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, ThemeData theme) {
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.post_deleteReplyTitle),
        content: Text(context.l10n.post_deleteReplyConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deletePost();
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context, ThemeData theme) {
    final isGuest = ref.read(currentUserProvider).value == null;

    showAppBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onShowPostDetail != null)
                  ListTile(
                    leading: Icon(
                      widget.postDetailLabel != null
                          ? Icons.open_in_new
                          : Icons.article_outlined,
                      color: theme.colorScheme.onSurface,
                    ),
                    title: Text(
                      widget.postDetailLabel ?? context.l10n.post_detail,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onShowPostDetail!();
                    },
                  ),
                if (widget.onReply != null)
                  ListTile(
                    leading: Icon(
                      Icons.reply,
                      color: theme.colorScheme.onSurface,
                    ),
                    title: Text(context.l10n.common_reply),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onReply!();
                    },
                  ),
                if (widget.post.canEdit && widget.onEdit != null)
                  ListTile(
                    leading: Icon(
                      Icons.edit_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      context.l10n.common_edit,
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onEdit!();
                    },
                  ),
                ListTile(
                  leading: Icon(
                    Icons.share_outlined,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: Text(context.l10n.common_shareLink),
                  onTap: () {
                    Navigator.pop(ctx);
                    _sharePost();
                  },
                ),
                if (widget.onShareAsImage != null)
                  ListTile(
                    leading: Icon(
                      Icons.image_outlined,
                      color: theme.colorScheme.onSurface,
                    ),
                    title: Text(context.l10n.post_generateShareImage),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onShareAsImage!();
                    },
                  ),
                if (!isGuest &&
                    (widget.post.canAcceptAnswer ||
                        widget.post.canUnacceptAnswer))
                  ListTile(
                    leading: Icon(
                      _isAcceptedAnswer
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: _isAcceptedAnswer
                          ? Colors.green
                          : theme.colorScheme.onSurface,
                    ),
                    title: Text(
                      _isAcceptedAnswer
                          ? context.l10n.post_unacceptSolution
                          : context.l10n.post_acceptSolution,
                      style: TextStyle(
                        color: _isAcceptedAnswer
                            ? Colors.green
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    onTap: _isTogglingAnswer
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _toggleSolution();
                          },
                  ),
                if (!isGuest)
                  ListTile(
                    leading: Icon(
                      _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: _isBookmarked
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    title: Text(
                      _isBookmarked
                          ? context.l10n.bookmark_editBookmark
                          : context.l10n.common_addBookmark,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (_isBookmarked) {
                        _editBookmark();
                      } else {
                        _addBookmark();
                      }
                    },
                  ),
                if (!isGuest)
                  ListTile(
                    leading: Icon(
                      Icons.flag_outlined,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      context.l10n.common_report,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showFlagDialog(context);
                    },
                  ),
                if (!isGuest && widget.post.canRecover)
                  ListTile(
                    leading: Icon(
                      Icons.restore,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      context.l10n.common_restore,
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                    onTap: _isDeleting
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _recoverPost();
                          },
                  ),
                if (!isGuest && widget.post.canDelete && !widget.post.isDeleted)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      context.l10n.common_delete,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: _isDeleting
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _showDeleteConfirmDialog(context, theme);
                          },
                  ),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(
                    context.l10n.common_cancel,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
