import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/widgets/common/error_view.dart';
import 'package:fluxdo/widgets/common/loading_spinner.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_editor.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/models/topic.dart';

import 'package:dio/dio.dart';
import 'package:fluxdo/providers/discourse_providers.dart';
import 'package:fluxdo/services/app_error_handler.dart';
import 'package:fluxdo/services/toast_service.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_renderer.dart';
import 'package:fluxdo/widgets/topic/topic_editor_helpers.dart';
import '../l10n/s.dart';

/// 编辑话题结果
class EditTopicResult {
  final String? title;
  final int? categoryId;
  final List<String>? tags;
  final Post? updatedFirstPost;

  const EditTopicResult({
    this.title,
    this.categoryId,
    this.tags,
    this.updatedFirstPost,
  });
}

class EditTopicPage extends ConsumerStatefulWidget {
  final TopicDetail topicDetail;
  /// 首贴，可选。如果为 null 会尝试通过 firstPostId 加载
  final Post? firstPost;
  /// 首贴 ID，用于在 firstPost 为 null 时加载首贴
  final int? firstPostId;

  const EditTopicPage({
    super.key,
    required this.topicDetail,
    this.firstPost,
    this.firstPostId,
  });

  @override
  ConsumerState<EditTopicPage> createState() => _EditTopicPageState();
}

class _EditTopicPageState extends ConsumerState<EditTopicPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();
  final _editorKey = GlobalKey<MarkdownEditorState>();

  Category? _selectedCategory;
  List<String> _selectedTags = [];
  bool _isSubmitting = false;
  bool _showPreview = false;
  bool _showEmojiPanel = false;
  bool _isLoadingContent = true;

  final PageController _pageController = PageController();
  int _contentLength = 0;

  // 首贴（可能从 widget 传入，也可能异步加载）
  Post? _firstPost;

  // 原始值，用于检测变化
  String? _originalTitle;
  int? _originalCategoryId;
  List<String>? _originalTags;
  String? _originalContent;

  /// 是否为私信编辑
  bool get _isPrivateMessage => widget.topicDetail.isPrivateMessage;

  /// 是否可以编辑话题元数据（标题、分类、标签）
  bool get _canEditMetadata => widget.topicDetail.canEdit;

  /// 是否可以编辑首贴内容（需要有首贴且有编辑权限）
  bool get _canEditContent => _firstPost?.canEdit ?? false;

  @override
  void initState() {
    super.initState();

    // 预填充数据
    _titleController.text = widget.topicDetail.title;
    _originalTitle = widget.topicDetail.title;
    _originalCategoryId = widget.topicDetail.categoryId;
    _originalTags = widget.topicDetail.tags?.map((tag) => tag.name).toList() ?? [];
    _selectedTags = List.from(_originalTags!);

    // 初始化首贴
    _firstPost = widget.firstPost;

    // 加载首贴和内容
    _loadFirstPostAndContent();

    // 非私信时加载分类数据
    if (!_isPrivateMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSelectedCategory());
    }
  }

  void _loadSelectedCategory() {
    ref.listenManual(categoriesProvider, (previous, next) {
      next.whenData((categories) {
        if (!mounted) return;
        final category = categories.where((c) => c.id == widget.topicDetail.categoryId).firstOrNull;
        if (category != null && _selectedCategory == null) {
          setState(() => _selectedCategory = category);
        }
      });
    }, fireImmediately: true);
  }

  Future<void> _loadFirstPostAndContent() async {
    final service = ref.read(discourseServiceProvider);

    try {
      // 如果没有首贴但有首贴 ID，先加载首贴
      if (_firstPost == null && widget.firstPostId != null) {
        final postStream = await service.getPosts(widget.topicDetail.id, [widget.firstPostId!]);
        if (mounted && postStream.posts.isNotEmpty) {
          setState(() => _firstPost = postStream.posts.first);
        }
      }

      // 加载首贴原始内容（无论是否可编辑都加载，用于显示）
      if (_firstPost != null) {
        final raw = await service.getPostRaw(_firstPost!.id);
        if (mounted && raw != null) {
          _contentController.text = raw;
          _originalContent = raw;
          _contentLength = raw.length;

          // 可编辑时添加字符计数监听器
          if (_canEditContent) {
            _contentController.addListener(_updateContentLength);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ToastService.showError(S.current.editTopic_loadContentFailed(e.toString().replaceAll('Exception: ', '')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingContent = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
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
  }

  void _togglePreview() {
    if (_showPreview) {
      _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
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
    if (_canEditContent) {
      final minContentLength = _isPrivateMessage
          ? (ref.read(minPmPostLengthProvider).value ?? 10)
          : (ref.read(minFirstPostLengthProvider).value ?? 20);
      final contentText = _contentController.text.trim();
      if (contentText.isEmpty) {
        if (_showPreview) _togglePreview();
        ToastService.showInfo(S.current.createTopic_enterContent);
        return;
      }
      if (contentText.length < minContentLength) {
        if (_showPreview) _togglePreview();
        ToastService.showInfo(S.current.createTopic_minContentLength(minContentLength));
        return;
      }
    }

    // 只有在有权限编辑元数据且不是私信时才验证分类
    if (_canEditMetadata && !_isPrivateMessage && _selectedCategory == null) {
      if (_showPreview) _togglePreview();
      ToastService.showInfo(S.current.createTopic_selectCategory);
      return;
    }

    // 只有在有权限编辑元数据时才验证标签数量
    if (_canEditMetadata &&
        !_isPrivateMessage &&
        _selectedCategory != null &&
        _selectedCategory!.minimumRequiredTags > 0 &&
        _selectedTags.length < _selectedCategory!.minimumRequiredTags) {
      if (_showPreview) _togglePreview();
      ToastService.showInfo(S.current.createTopic_minTags(_selectedCategory!.minimumRequiredTags));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final service = ref.read(discourseServiceProvider);
      final newTitle = _titleController.text.trim();
      final newContent = _contentController.text;

      // 检测话题元数据变化（仅当有权限编辑元数据时）
      final titleChanged = _canEditMetadata && newTitle != _originalTitle;
      // 私信不支持分类和标签
      final categoryChanged = _canEditMetadata &&
          !_isPrivateMessage &&
          _selectedCategory != null &&
          _selectedCategory!.id != _originalCategoryId;
      final tagsChanged = _canEditMetadata &&
          !_isPrivateMessage &&
          !_listEquals(_selectedTags, _originalTags ?? []);
      // 检测内容变化（仅当有权限编辑内容时）
      final contentChanged = _canEditContent && newContent != _originalContent;

      // 更新话题元数据（如果有变化且有权限）
      if (titleChanged || categoryChanged || tagsChanged) {
        await service.updateTopic(
          topicId: widget.topicDetail.id,
          title: titleChanged ? newTitle : null,
          categoryId: categoryChanged ? _selectedCategory!.id : null,
          tags: tagsChanged ? _selectedTags : null,
        );
      }

      // 更新首贴内容（如果有变化且有权限）
      Post? updatedPost;
      if (contentChanged && _firstPost != null) {
        updatedPost = await service.updatePost(
          postId: _firstPost!.id,
          raw: newContent,
        );
      }

      if (!mounted) return;

      // 返回编辑结果
      Navigator.of(context).pop(EditTopicResult(
        title: titleChanged ? newTitle : null,
        categoryId: categoryChanged ? _selectedCategory!.id : null,
        tags: tagsChanged ? _selectedTags : null,
        updatedFirstPost: updatedPost,
      ));
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sortedA = List<String>.from(a)..sort();
    final sortedB = List<String>.from(b)..sort();
    for (int i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final tagsAsync = ref.watch(tagsProvider);
    final canTagTopics = ref.watch(canTagTopicsProvider).value ?? false;
    final theme = Theme.of(context);

    // 获取站点配置的最小长度
    final minTitleLength = _isPrivateMessage
        ? (ref.watch(minPmTitleLengthProvider).value ?? 2)
        : (ref.watch(minTopicTitleLengthProvider).value ?? 15);

    return PopScope(
      canPop: !_showEmojiPanel,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        _editorKey.currentState?.closeEmojiPanel();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(_isPrivateMessage ? context.l10n.editTopic_editPm : context.l10n.editTopic_editTopic),
          scrolledUnderElevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton(
                onPressed: (_isSubmitting || _isLoadingContent) ? null : _submit,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(context.l10n.common_save),
              ),
            ),
          ],
        ),
        body: _isPrivateMessage
            ? _buildBody(theme, [], canTagTopics, tagsAsync, minTitleLength)
            : categoriesAsync.when(
                data: (categories) => _buildBody(theme, categories, canTagTopics, tagsAsync, minTitleLength),
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

  Widget _buildBody(ThemeData theme, List<Category> categories, bool canTagTopics, AsyncValue<List<String>> tagsAsync, int minTitleLength) {
    if (_isLoadingContent) {
      return const Center(child: LoadingSpinner());
    }

    // 构建元数据编辑区域（标题、分类、标签）
    Widget buildMetadataSection() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题输入
          TextFormField(
            controller: _titleController,
            enabled: _canEditMetadata,
            decoration: InputDecoration(
              hintText: context.l10n.createTopic_titleHint,
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontWeight: FontWeight.normal,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: _canEditMetadata ? null : theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: null,
            maxLength: 200,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
            validator: _canEditMetadata ? (value) {
              if (value == null || value.trim().isEmpty) return context.l10n.createTopic_enterTitle;
              if (value.trim().length < minTitleLength) return context.l10n.createTopic_minTitleLength(minTitleLength);
              return null;
            } : null,
            onTap: () {
              _editorKey.currentState?.closeEmojiPanel();
            },
          ),

          const SizedBox(height: 16),

          // 元数据区域 (分类 + 标签) - 私信不显示
          if (!_isPrivateMessage)
            IgnorePointer(
              ignoring: !_canEditMetadata,
              child: Opacity(
                opacity: _canEditMetadata ? 1.0 : 0.6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CategoryTrigger(
                      category: _selectedCategory,
                      categories: categories,
                      onSelected: _onCategorySelected,
                    ),
                    if (canTagTopics) ...[
                      const SizedBox(height: 12),
                      tagsAsync.when(
                        data: (tags) => TagsArea(
                          selectedCategory: _selectedCategory,
                          selectedTags: _selectedTags,
                          allTags: tags,
                          onTagsChanged: (newTags) => setState(() => _selectedTags = newTags),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (e, s) => const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),
          Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ],
      );
    }

    // 如果没有内容编辑权限，不需要 PageView，直接显示表单 + 渲染后的内容
    if (!_canEditContent) {
      return Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          children: [
            buildMetadataSection(),
            const SizedBox(height: 20),
            // 直接显示渲染后的内容
            MarkdownBody(data: _contentController.text),
          ],
        ),
      );
    }

    // 有内容编辑权限时，使用 PageView 支持编辑/预览切换
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
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              buildMetadataSection(),
                            ],
                          ),
                        ),
                      ),

                      // 字符计数
                      Padding(
                        padding: const EdgeInsets.only(right: 20, top: 8),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            context.l10n.createTopic_charCount(_contentLength),
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
                          hintText: context.l10n.createTopic_contentHint,
                          expands: true,
                          emojiPanelHeight: 350,
                          onTogglePreview: _togglePreview,
                          isPreview: _showPreview,
                          onEmojiPanelChanged: (show) {
                            setState(() => _showEmojiPanel = show);
                          },
                          mentionDataSource: (term) => ref.read(discourseServiceProvider).searchUsers(
                            term: term,
                            categoryId: _selectedCategory?.id,
                            includeGroups: !_isPrivateMessage,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Page 1: 预览模式
                  SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.paddingOf(context).bottom + 80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _titleController.text.isEmpty ? context.l10n.createTopic_noTitle : _titleController.text,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (!_isPrivateMessage)
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
                              PreviewTagsList(tags: _selectedTags),
                            ],
                          ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1),
                        ),
                        if (_contentController.text.isEmpty)
                          Text(
                            context.l10n.createTopic_noContent,
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
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
  }
}
