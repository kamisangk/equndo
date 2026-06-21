import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/widgets/common/error_view.dart';
import 'package:fluxdo/widgets/common/loading_spinner.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_editor.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/models/shortcut_binding.dart';

import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/equn_discuz_providers.dart';
import 'package:fluxdo/services/toast_service.dart';
import 'package:fluxdo/services/app_error_handler.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_renderer.dart';
import 'package:fluxdo/providers/shortcut_provider.dart';
import 'package:fluxdo/widgets/topic/topic_editor_helpers.dart';
import '../l10n/s.dart';
import '../utils/dialog_utils.dart';

class CreateTopicPage extends ConsumerStatefulWidget {
  final int? initialCategoryId;
  final bool useEqunComposer;

  const CreateTopicPage({
    super.key,
    this.initialCategoryId,
    this.useEqunComposer = true,
  });

  @override
  ConsumerState<CreateTopicPage> createState() => _CreateTopicPageState();
}

class _CreateTopicPageState extends ConsumerState<CreateTopicPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();
  final _editorKey = GlobalKey<MarkdownEditorState>();
  late final ShortcutSurfaceBinding _shortcutSurfaceBinding =
      ShortcutSurfaceBinding(
        ref: ref,
        id: ShortcutSurfaceIds.createTopic,
        triggerAction: ShortcutAction.createTopic,
        kind: ShortcutSurfaceKind.route,
        repeatBehavior: ShortcutSurfaceRepeatBehavior.reveal,
        passthroughActions: ShortcutSurfaceActionSets.globalRoutePassthrough,
      );
  ModalRoute<dynamic>? _route;

  Category? _selectedCategory;
  bool _isSubmitting = false;
  bool _showPreview = false;
  String? _templateContent;
  bool _showEmojiPanel = false;

  final PageController _pageController = PageController();
  int _contentLength = 0;

  @override
  void initState() {
    super.initState();
    _contentController.addListener(_updateContentLength);

    // 从当前筛选条件自动填入分类和标签
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyCurrentFilter());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _route)) return;
    _route = route;
    _shortcutSurfaceBinding.registerDeferred(
      context,
      onClose: () => Navigator.of(context).maybePop(),
      onFocus: _revealSelf,
    );
  }

  void _revealSelf() {
    final route = _route;
    final navigator = route?.navigator;
    if (route == null || navigator == null || route.isCurrent) return;
    navigator.popUntil((candidate) => identical(candidate, route));
  }

  void _applyCurrentFilter() async {
    final targetCategoryId = widget.initialCategoryId;

    if (targetCategoryId != null && mounted) {
      // 监听 categories 加载完成
      ref.listenManual(categoriesProvider, (previous, next) {
        next.whenData((categories) {
          if (!mounted) return;
          final category = categories
              .where((c) => c.id == targetCategoryId)
              .firstOrNull;
          if (category != null &&
              category.canCreateTopic &&
              _selectedCategory == null) {
            _onCategorySelected(category);
          }
        });
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _shortcutSurfaceBinding.disposeDeferred();
    _pageController.dispose();
    _contentController.removeListener(_updateContentLength);
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _updateContentLength() {
    setState(() => _contentLength = _contentController.text.length);
  }

  void _onCategorySelected(Category category) {
    setState(() => _selectedCategory = category);

    final currentContent = _contentController.text.trim();
    if (currentContent.isEmpty ||
        (_templateContent != null &&
            currentContent == _templateContent!.trim())) {
      if (category.topicTemplate != null &&
          category.topicTemplate!.isNotEmpty) {
        _contentController.text = category.topicTemplate!;
        _templateContent = category.topicTemplate;
      } else {
        _contentController.clear();
        _templateContent = null;
      }
    }

  }

  void _togglePreview() {
    if (_showPreview) {
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      // 预览模式下验证错误不可见，切回编辑模式并提示
      if (_showPreview) {
        _togglePreview();
        ToastService.showInfo(S.current.common_checkInput);
      }
      return;
    }

    // 手动验证内容
    const minContentLength = 1;
    final contentText = _contentController.text.trim();
    if (contentText.isEmpty) {
      if (_showPreview) _togglePreview();
      ToastService.showInfo(S.current.createTopic_enterContent);
      return;
    }
    if (contentText.length < minContentLength) {
      if (_showPreview) _togglePreview();
      ToastService.showInfo(
        S.current.createTopic_minContentLength(minContentLength),
      );
      return;
    }

    if (_selectedCategory == null) {
      if (_showPreview) _togglePreview();
      ToastService.showInfo(S.current.createTopic_selectCategory);
      return;
    }

    if (_templateContent != null &&
        _contentController.text.trim() == _templateContent!.trim()) {
      final confirm = await showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.common_hint),
          content: Text(context.l10n.createTopic_templateNotModified),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.createTopic_continueEditing),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.createTopic_confirmPublish),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSubmitting = true);

    try {
      final topicId = await _createEqunTopic();

      if (!mounted) return;
      Navigator.of(context).pop(topicId);
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<int> _createEqunTopic() async {
    return ref
        .read(equnDiscuzServiceProvider)
        .createThread(
          fid: _selectedCategory!.id,
          subject: _titleController.text.trim(),
          message: _contentController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final theme = Theme.of(context);

    const minTitleLength = 1;

    return PopScope(
      canPop: !_showEmojiPanel,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        _editorKey.currentState?.closeEmojiPanel();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(context.l10n.createTopic_title),
          scrolledUnderElevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.l10n.common_publish),
              ),
            ),
          ],
        ),
        body: categoriesAsync.when(
          data: (categories) {
            return Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        allowImplicitScrolling: true,
                        onPageChanged: (index) {
                          setState(() {
                            _showPreview = index == 1;
                          });
                          if (_showPreview) {
                            FocusScope.of(context).unfocus();
                            _editorKey.currentState?.closeEmojiPanel();
                          }
                        },
                        children: [
                          // Page 0: 编辑模式
                          Column(
                            children: [
                              // 标题 + 元数据区域
                              Form(
                                key: _formKey,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    16,
                                    20,
                                    0,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 标题输入
                                      TextFormField(
                                        controller: _titleController,
                                        decoration: InputDecoration(
                                          hintText: context
                                              .l10n
                                              .createTopic_titleHint,
                                          hintStyle: TextStyle(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant
                                                .withValues(alpha: 0.5),
                                            fontWeight: FontWeight.normal,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.zero,
                                          isDense: true,
                                        ),
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.5,
                                            ),
                                        maxLines: null,
                                        maxLength: 200,
                                        buildCounter:
                                            (
                                              context, {
                                              required currentLength,
                                              required isFocused,
                                              maxLength,
                                            }) => null,
                                        validator: (value) {
                                          if (value == null ||
                                              value.trim().isEmpty) {
                                            return context
                                                .l10n
                                                .createTopic_enterTitle;
                                          }
                                          if (value.trim().length <
                                              minTitleLength) {
                                            return context.l10n
                                                .createTopic_minTitleLength(
                                                  minTitleLength,
                                                );
                                          }
                                          return null;
                                        },
                                        onTap: () {
                                          _editorKey.currentState
                                              ?.closeEmojiPanel();
                                        },
                                      ),

                                      const SizedBox(height: 16),

                                      // 元数据区域 (分类 + 标签)
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CategoryTrigger(
                                            category: _selectedCategory,
                                            categories: categories,
                                            onSelected: _onCategorySelected,
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 20),
                                      Divider(
                                        height: 1,
                                        color: theme.colorScheme.outlineVariant
                                            .withValues(alpha: 0.3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // 字符计数
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: 20,
                                  top: 8,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    context.l10n.createTopic_charCount(
                                      _contentLength,
                                    ),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),

                              // 内容编辑器
                              Expanded(
                                child: MarkdownEditor(
                                  key: _editorKey,
                                  controller: _contentController,
                                  focusNode: _contentFocusNode,
                                  hintText:
                                      context.l10n.createTopic_contentHint,
                                  expands: true,
                                  emojiPanelHeight: 350,
                                  onTogglePreview: _togglePreview,
                                  isPreview: _showPreview,
                                  onEmojiPanelChanged: (show) {
                                    setState(() => _showEmojiPanel = show);
                                  },
                                ),
                              ),
                            ],
                          ),

                          // Page 1: 预览模式
                          SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              24,
                              24,
                              MediaQuery.paddingOf(context).bottom + 80,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _titleController.text.isEmpty
                                      ? context.l10n.createTopic_noTitle
                                      : _titleController.text,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                      ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (_selectedCategory != null)
                                      CategoryTrigger(
                                        category: _selectedCategory,
                                        categories: categories,
                                        onSelected: _onCategorySelected,
                                      ),
                                  ],
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Divider(height: 1),
                                ),
                                if (_contentController.text.isEmpty)
                                  Text(
                                    context.l10n.createTopic_noContent,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                else
                                  MarkdownBody(data: _contentController.text),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 预览模式下的退出预览按钮
                if (_showPreview)
                  Positioned(
                    right: 16,
                    bottom: MediaQuery.paddingOf(context).bottom + 16,
                    child: FloatingActionButton.small(
                      onPressed: _togglePreview,
                      tooltip: context.l10n.common_exitPreview,
                      child: const Icon(Icons.edit_outlined),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: LoadingSpinner()),
          error: (err, stack) => ErrorView(
            error: err,
            stackTrace: stack,
            onRetry: () => ref.invalidate(categoriesProvider),
          ),
        ),
      ),
    );
  }
}
