import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/draft.dart';
import '../../models/topic.dart';
import '../../providers/equn_discuz_providers.dart';
import '../../providers/shortcut_provider.dart';
import '../../services/app_error_handler.dart';
import '../../services/emoji_handler.dart';
import '../../utils/dialog_utils.dart';
import '../common/smart_avatar.dart';
import '../markdown_editor/markdown_editor.dart';

/// 显示回复底部弹框。
///
/// Equn Discuz 适配只支持回复主题和回复指定楼层。其余参数保留用于旧调用点编译兼容。
Future<Post?> showReplySheet({
  required BuildContext context,
  int? topicId,
  int? categoryId,
  Post? replyToPost,
  String? targetUsername,
  String? draftKey,
  Future<Draft?>? preloadedDraftFuture,
  String? initialContent,
  String? initialTitle,
  String? topicTitle,
  bool isPrivateMessageTopic = false,
  bool useEqunComposer = true,
  ShortcutSurfaceConfig? shortcutSurface,
}) async {
  final result = await showAppBottomSheet<Post?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    shortcutSurface: shortcutSurface,
    builder: (context) => ReplySheet(
      topicId: topicId,
      replyToPost: replyToPost,
      initialContent: initialContent,
    ),
  );
  return result;
}

/// Equn 当前不支持在客户端编辑已有帖子。
Future<Post?> showEditSheet({
  required BuildContext context,
  required int topicId,
  required Post post,
  int? categoryId,
  ShortcutSurfaceConfig? shortcutSurface,
}) async {
  return null;
}

class ReplySheet extends ConsumerStatefulWidget {
  final int? topicId;
  final Post? replyToPost;
  final String? initialContent;

  const ReplySheet({
    super.key,
    this.topicId,
    this.replyToPost,
    this.initialContent,
  });

  @override
  ConsumerState<ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends ConsumerState<ReplySheet> {
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();
  final _editorKey = GlobalKey<MarkdownEditorState>();

  static const double _emojiPanelHeight = 280.0;

  bool _isSubmitting = false;
  bool _showEmojiPanel = false;

  @override
  void initState() {
    super.initState();
    EmojiHandler().init();

    final initialContent = widget.initialContent;
    if (initialContent != null && initialContent.isNotEmpty) {
      _contentController.text = initialContent;
      _contentController.selection = TextSelection.fromPosition(
        TextPosition(offset: _contentController.text.length),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _contentFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _showError(String message) {
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.common_hint),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.common_confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final topicId = widget.topicId;
    if (topicId == null || topicId <= 0) {
      _showError('无法确定主题');
      return;
    }

    final content = _contentController.text.trim();
    if (content.isEmpty) {
      _showError(S.current.post_contentRequired);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await ref
          .read(equnDiscuzServiceProvider)
          .createReply(
            tid: topicId,
            message: content,
            replyToPid: widget.replyToPost?.id,
          );
      if (!mounted) return;
      Navigator.of(context).pop(_postFromSubmitResult(result, content));
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Post _postFromSubmitResult(dynamic result, String content) {
    final now = DateTime.now();
    return Post(
      id: result.pid ?? now.millisecondsSinceEpoch,
      username: '',
      avatarTemplate: '',
      cooked: content,
      postNumber: 0,
      postType: 1,
      updatedAt: now,
      createdAt: now,
      likeCount: 0,
      replyCount: 0,
      replyToPostNumber: widget.replyToPost?.postNumber ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: FractionallySizedBox(
        heightFactor: 0.95,
        alignment: Alignment.bottomCenter,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: PopScope(
            canPop: !_showEmojiPanel,
            onPopInvokedWithResult: (bool didPop, dynamic result) async {
              if (didPop) return;
              if (_showEmojiPanel) {
                _editorKey.currentState?.closeEmojiPanel();
                setState(() => _showEmojiPanel = false);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  _ReplySheetHeader(
                    replyToPost: widget.replyToPost,
                    isSubmitting: _isSubmitting,
                    onSubmit: _submit,
                  ),
                  Expanded(
                    child: MarkdownEditor(
                      key: _editorKey,
                      controller: _contentController,
                      focusNode: _contentFocusNode,
                      hintText: context.l10n.editor_hintText,
                      expands: true,
                      emojiPanelHeight: _emojiPanelHeight,
                      onEmojiPanelChanged: (show) {
                        setState(() => _showEmojiPanel = show);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplySheetHeader extends StatelessWidget {
  const _ReplySheetHeader({
    required this.replyToPost,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final Post? replyToPost;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (replyToPost != null) ...[
                SmartAvatar(
                  imageUrl: replyToPost!.getAvatarUrl().isNotEmpty
                      ? replyToPost!.getAvatarUrl()
                      : null,
                  radius: 14,
                  fallbackText: replyToPost!.username,
                  backgroundColor: theme.colorScheme.primaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.post_replyToUser(replyToPost!.username),
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else ...[
                Expanded(
                  child: Text(
                    context.l10n.post_replyToTopic,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
              FilledButton(
                onPressed: isSubmitting ? null : onSubmit,
                child: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.l10n.common_send),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ],
    );
  }
}
