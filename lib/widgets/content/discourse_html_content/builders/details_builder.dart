import 'package:flutter/material.dart';
import '../../../../l10n/s.dart';
import '../chunked/html_chunk.dart';
import '../chunked/html_chunker.dart';

/// 构建 Discourse details 折叠块
///
/// 处理 `<details><summary>标题</summary>内容</details>` 结构
Widget buildDetails({
  required BuildContext context,
  required ThemeData theme,
  required dynamic element,
  required Widget Function(String html, TextStyle? textStyle) htmlBuilder,
}) {
  // 提取 summary 文本
  final summaryElements = element.getElementsByTagName('summary');
  String summaryText = S.current.common_details; // 默认标题
  if (summaryElements.isNotEmpty) {
    // 取 summary 的纯文本
    summaryText = summaryElements.first.text.trim();
    if (summaryText.isEmpty) {
      summaryText = S.current.common_details;
    }
  }

  // 提取 details 内容（除 summary 外的部分）
  String contentHtml = element.innerHtml as String;
  // 移除 summary 标签及其内容
  contentHtml = contentHtml.replaceFirst(
    RegExp(r'<summary[^>]*>.*?</summary>', caseSensitive: false, dotAll: true),
    '',
  );
  contentHtml = contentHtml.trim();

  // 检查是否有 open 属性（默认展开）
  final isOpenByDefault = element.attributes.containsKey('open');

  return _DetailsWidget(
    theme: theme,
    summaryText: summaryText,
    contentHtml: contentHtml,
    htmlBuilder: htmlBuilder,
    initiallyExpanded: isOpenByDefault,
  );
}

/// 内容长度超过此阈值时启用渐进式分块渲染
const _progressiveChunkThreshold = 3000;

/// 可折叠的 Details Widget
class _DetailsWidget extends StatefulWidget {
  final ThemeData theme;
  final String summaryText;
  final String contentHtml;
  final Widget Function(String html, TextStyle? textStyle) htmlBuilder;
  final bool initiallyExpanded;

  const _DetailsWidget({
    required this.theme,
    required this.summaryText,
    required this.contentHtml,
    required this.htmlBuilder,
    required this.initiallyExpanded,
  });

  @override
  State<_DetailsWidget> createState() => _DetailsWidgetState();
}

class _DetailsWidgetState extends State<_DetailsWidget>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  /// 是否应该构建内容 Widget 树（展开中或动画进行中为 true）
  late bool _shouldBuildContent;
  late AnimationController _controller;
  late Animation<double> _iconTurns;
  late Animation<double> _heightFactor;

  /// 渐进式渲染：内容分块列表（短内容为 null，不分块）
  List<HtmlChunk>? _chunks;
  /// 渐进式渲染：当前已渲染的块数
  int _renderedChunkCount = 0;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _shouldBuildContent = _isExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _controller.addStatusListener(_handleAnimationStatus);
    _iconTurns = Tween<double>(begin: 0.0, end: 0.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _heightFactor = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    if (_isExpanded) {
      _controller.value = 1.0;
      _prepareChunks();
      _renderedChunkCount = _chunks?.length ?? 0;
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  /// 预解析分块（同步，内容已经不会太长因为是 details 内部）
  void _prepareChunks() {
    if (widget.contentHtml.length > _progressiveChunkThreshold) {
      final chunks = HtmlChunker.chunk(widget.contentHtml);
      if (chunks.length > 1) {
        _chunks = chunks;
        return;
      }
    }
    _chunks = null;
  }

  void _handleAnimationStatus(AnimationStatus status) {
    // 收起动画结束后，移除内容 Widget 树释放资源
    if (status == AnimationStatus.dismissed) {
      setState(() {
        _shouldBuildContent = false;
        _renderedChunkCount = 0;
      });
    }
  }

  /// 逐帧渲染下一批 chunk
  void _renderNextChunk() {
    if (!mounted || !_isExpanded || _chunks == null) return;
    if (_renderedChunkCount >= _chunks!.length) return;

    setState(() {
      _renderedChunkCount++;
    });

    // 还有剩余 chunk，继续排队下一帧
    if (_renderedChunkCount < _chunks!.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _renderNextChunk());
    }
  }

  void _handleTap() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _shouldBuildContent = true;
        _prepareChunks();
        _controller.forward();

        if (_chunks != null) {
          // 长内容：渐进式渲染，第一帧先渲染一个 chunk
          _renderedChunkCount = 1;
          WidgetsBinding.instance.addPostFrameCallback((_) => _renderNextChunk());
        } else {
          // 短内容：延迟一帧直接渲染全部
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isExpanded) {
              setState(() => _renderedChunkCount = 1);
            }
          });
        }
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = theme.brightness == Brightness.dark;

    // 使用柔和的边框颜色
    final borderColor = isDark
        ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
        : theme.colorScheme.outline.withValues(alpha: 0.3);

    // 标题背景色
    final headerBgColor = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surfaceContainerLow;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // 可点击的标题栏
          Material(
            color: headerBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            child: InkWell(
              onTap: _handleTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    RotationTransition(
                      turns: _iconTurns,
                      child: Icon(
                        Icons.arrow_right_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.summaryText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 可折叠的内容：折叠状态下不构建 HTML 内容，避免无谓的解析开销
          if (_shouldBuildContent)
            ClipRect(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Align(
                    alignment: Alignment.topLeft,
                    heightFactor: _heightFactor.value,
                    child: child,
                  );
                },
                child: _buildContent(theme, borderColor),
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, Color borderColor) {
    if (widget.contentHtml.isEmpty) return const SizedBox.shrink();

    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      height: 1.5,
      color: theme.colorScheme.onSurface,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _chunks != null
            ? _buildProgressiveChunks(textStyle)
            : _renderedChunkCount > 0
                ? widget.htmlBuilder(widget.contentHtml, textStyle)
                : const SizedBox(height: 24),
      ),
    );
  }

  /// 渐进式渲染已就绪的 chunk
  Widget _buildProgressiveChunks(TextStyle? textStyle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _renderedChunkCount && i < _chunks!.length; i++)
          RepaintBoundary(
            child: widget.htmlBuilder(_chunks![i].html, textStyle),
          ),
      ],
    );
  }
}
