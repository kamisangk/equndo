import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/topic.dart';
import '../../l10n/s.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import '../../utils/export_utils.dart';

/// 用户在 sheet 上选的"目标"。
enum _ExportTarget { md, html }

/// 导出选项 Sheet
class ExportSheet extends ConsumerStatefulWidget {
  /// 话题详情
  final TopicDetail detail;

  const ExportSheet({super.key, required this.detail});

  /// 显示导出 Sheet
  static Future<void> show(BuildContext context, TopicDetail detail) {
    return showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ExportSheet(detail: detail),
    );
  }

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  ExportScope _scope = ExportScope.firstPostOnly;
  _ExportTarget _target = _ExportTarget.md;
  bool _isExporting = false;
  int _progress = 0;
  int _total = 0;

  int get _totalPostsCount => widget.detail.postStream.stream.length;

  bool get _willBeLimited =>
      _target == _ExportTarget.md &&
      _scope == ExportScope.allPosts &&
      _totalPostsCount > ExportUtils.maxMarkdownPosts;

  Future<void> _export() async {
    if (_isExporting) return;
    setState(() {
      _isExporting = true;
      _progress = 0;
      _total = 0;
    });

    try {
      switch (_target) {
        case _ExportTarget.md:
        case _ExportTarget.html:
          await _exportLocal();
          break;
      }
    } catch (e) {
      if (mounted) {
        ToastService.showError(S.current.export_failed('$e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _exportLocal() async {
    final format = _target == _ExportTarget.md
        ? ExportFormat.markdown
        : ExportFormat.html;
    await ExportUtils.exportTopic(
      detail: widget.detail,
      scope: _scope,
      format: format,
      onProgress: (current, total) {
        if (mounted) {
          setState(() {
            _progress = current;
            _total = total;
          });
        }
      },
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部拖动条
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.l10n.export_title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 导出范围选择
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.l10n.export_range,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ExportScope>(
                segments: [
                  ButtonSegment(
                    value: ExportScope.firstPostOnly,
                    label: Text(context.l10n.export_firstPostOnly),
                    icon: const Icon(Icons.article_outlined),
                  ),
                  ButtonSegment(
                    value: ExportScope.allPosts,
                    label: Text(context.l10n.common_all),
                    icon: const Icon(Icons.forum_outlined),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (selected) {
                  setState(() => _scope = selected.first);
                },
              ),
            ),

            const SizedBox(height: 20),

            // 导出格式选择
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.l10n.export_format,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<_ExportTarget>(
                segments: const [
                  ButtonSegment(
                    value: _ExportTarget.md,
                    label: Text('MD'),
                    icon: Icon(Icons.code),
                  ),
                  ButtonSegment(
                    value: _ExportTarget.html,
                    label: Text('HTML'),
                    icon: Icon(Icons.html),
                  ),
                ],
                selected: {_target},
                onSelectionChanged: (selected) {
                  setState(() => _target = selected.first);
                },
              ),
            ),

            // Markdown 限制提示
            if (_willBeLimited) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.l10n.export_markdownLimit(
                          ExportUtils.maxMarkdownPosts,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // 导出按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: _isExporting ? null : _export,
                icon: _isExporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(_buttonLabel(context)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            SizedBox(height: 16 + bottomPadding),
          ],
        ),
      ),
    );
  }

  String _buttonLabel(BuildContext context) {
    if (!_isExporting) return context.l10n.common_export;
    if (_total > 0) {
      return context.l10n.export_exporting(_progress, _total);
    }
    return context.l10n.export_exportingNoProgress;
  }
}
