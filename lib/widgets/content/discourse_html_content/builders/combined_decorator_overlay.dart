import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'scan_boundary.dart';
import 'inline_decorator_common.dart';
import 'inline_code_painter.dart';
import 'inline_spoiler_painter.dart';

// 导出公共 API
export 'inline_decorator_common.dart';

/// 合并的内联装饰覆盖层
/// 一次扫描同时处理内联代码背景和 spoiler 粒子效果
class CombinedDecoratorOverlay extends StatefulWidget {
  final Widget child;
  final Set<String> revealedSpoilers;
  final void Function(String id)? onReveal;

  const CombinedDecoratorOverlay({
    super.key,
    required this.child,
    required this.revealedSpoilers,
    this.onReveal,
  });

  @override
  State<CombinedDecoratorOverlay> createState() => _CombinedDecoratorOverlayState();
}

class _CombinedDecoratorOverlayState extends State<CombinedDecoratorOverlay>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;

  // 内联代码组（每组是一个 code 元素的多行矩形）
  List<List<Rect>> _codeGroups = [];

  // Spoiler 组（每组可能包含多行）
  List<SpoilerGroup> _spoilerGroups = [];

  bool _hasScanned = false;
  bool _needsRescan = false;
  int _scanDelayCounter = 0;

  // 上次扫描时 RenderObject 的尺寸，用于检测布局变化（如 details 展开/收起）
  Size? _lastRenderSize;

  @override
  void initState() {
    super.initState();
    _scheduleScan();
  }

  void _scheduleScan() {
    _ticker ??= createTicker(_onTick);
    if (!_ticker!.isActive) {
      _ticker!.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dtMs = (elapsed - _lastElapsed).inMilliseconds.toDouble();
    _lastElapsed = elapsed;

    // 扫描阶段
    if (!_hasScanned || _needsRescan) {
      _scanDelayCounter++;
      // 等待 2 帧确保 RenderTree 完成布局
      if (_scanDelayCounter >= 2) {
        _scan();
        _hasScanned = true;
        _needsRescan = false;
        _scanDelayCounter = 0;

        // 扫描完成后，如果没有活跃的 spoiler，停止 Ticker
        if (!_hasActiveSpoilers()) {
          _ticker?.stop();
        }
        // 扫描完成后始终 setState，确保 UI 立即更新
        setState(() {});
      }
      return;
    }

    // 动画阶段：更新 spoiler 粒子
    if (!_hasActiveSpoilers()) {
      _ticker?.stop();
      return;
    }

    // 检测 RenderObject 尺寸变化（如 details 展开/收起导致整体高度变化）
    // 尺寸变化说明上一帧布局已完成，可以立即 rescan，避免延迟帧导致闪烁
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize) {
      final currentSize = ro.size;
      if (_lastRenderSize != null && currentSize != _lastRenderSize) {
        _scan();
        setState(() {});
        return;
      }
    }

    if (dtMs > 0 && dtMs < 100) {
      for (final group in _spoilerGroups) {
        if (!group.isRevealed) {
          group.particleSystem.update(dtMs);
        }
      }
      setState(() {});
    }
  }

  bool _hasActiveSpoilers() {
    for (final group in _spoilerGroups) {
      if (!group.isRevealed) return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(CombinedDecoratorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {
      _needsRescan = true;
      _scanDelayCounter = 0;
      _scheduleScan();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  /// 一次扫描同时收集 code 和 spoiler 的位置
  void _scan() {
    final renderObject = context.findRenderObject();
    if (renderObject == null) return;

    // 保存当前 RenderObject 尺寸
    if (renderObject is RenderBox && renderObject.hasSize) {
      _lastRenderSize = renderObject.size;
    }

    final newCodeGroups = <List<Rect>>[];
    final spoilerTempRects = <_TempRect>[];
    int paragraphIndex = 0;

    void visitRenderObject(
      RenderObject ro,
      Offset parentOffset,
    ) {
      if (ro is RenderScanBoundary) return;

      if (ro is RenderParagraph) {
        _extractFromParagraph(ro, parentOffset, paragraphIndex, newCodeGroups, spoilerTempRects);
        paragraphIndex++;
      }

      ro.visitChildren((child) {
        Offset childOffset = parentOffset;
        if (child is RenderBox && ro is RenderBox) {
          final parentData = child.parentData;
          if (parentData is BoxParentData) {
            childOffset = parentOffset + parentData.offset;
          }
        }
        visitRenderObject(child, childOffset);
      });
    }

    visitRenderObject(renderObject, Offset.zero);

    // 处理 code groups
    _codeGroups = newCodeGroups;

    // 处理 spoiler groups，复用已有粒子系统避免闪烁
    final oldGroupMap = <String, SpoilerGroup>{};
    for (final group in _spoilerGroups) {
      oldGroupMap[group.id] = group;
    }

    final newSpoilerGroups = _buildSpoilerGroups(spoilerTempRects);
    final resultGroups = <SpoilerGroup>[];
    for (final group in newSpoilerGroups) {
      final newRects = group.rects.map((r) => r.rect).toList();
      final oldGroup = oldGroupMap[group.id];
      if (oldGroup != null && !oldGroup.isRevealed) {
        // 复用旧 group，更新其区域位置，保留粒子系统
        oldGroup.rects
          ..clear()
          ..addAll(group.rects);
        oldGroup.particleSystem.updateRects(newRects);
        if (widget.revealedSpoilers.contains(group.id)) {
          oldGroup.isRevealed = true;
        }
        resultGroups.add(oldGroup);
      } else {
        if (widget.revealedSpoilers.contains(group.id)) {
          group.isRevealed = true;
        } else {
          group.particleSystem.initForRects(newRects);
        }
        resultGroups.add(group);
      }
    }
    _spoilerGroups = resultGroups;
  }

  void _extractFromParagraph(
    RenderParagraph paragraph,
    Offset offset,
    int paragraphIndex,
    List<List<Rect>> codeGroups,
    List<_TempRect> spoilerRects,
  ) {
    final text = paragraph.text;
    _visitInlineSpan(
      text,
      paragraph,
      offset,
      0,
      null,
      false,
      null,
      paragraphIndex,
      codeGroups,
      spoilerRects,
    );
  }

  /// 遍历 InlineSpan 树，同时收集 code 和 spoiler
  (int, String?) _visitInlineSpan(
    InlineSpan span,
    RenderParagraph paragraph,
    Offset offset,
    int charIndex,
    TextStyle? parentStyle,
    bool parentIsSpoiler,
    String? currentSpoilerId,
    int paragraphIndex,
    List<List<Rect>> codeGroups,
    List<_TempRect> spoilerRects,
  ) {
    if (span is TextSpan) {
      final effectiveStyle = parentStyle?.merge(span.style) ?? span.style;
      final textLength = span.text?.length ?? 0;

      // 检测标记
      final isCode = isCodeMarkerStyle(effectiveStyle);
      final hasSpoilerMarker = isSpoilerMarkerStyle(effectiveStyle);
      final inSpoiler = hasSpoilerMarker || parentIsSpoiler;

      // 决定 spoiler ID（使用段落遍历索引 + charIndex，跨 rebuild 稳定）
      String? spoilerId = currentSpoilerId;
      if (inSpoiler && spoilerId == null) {
        spoilerId = 'spoiler_${paragraphIndex}_$charIndex';
      }

      if (textLength > 0) {
        // 只对 code/spoiler 标记的 span 调用 getBoxesForSelection
        // 非标记 span 跳过，避免对大量普通文本做昂贵的布局计算
        if (isCode || inSpoiler) {
          try {
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: charIndex, extentOffset: charIndex + textLength),
            );

            // 收集 code rects
            if (isCode) {
              final rects = <Rect>[];
              for (final box in boxes) {
                final rect = Rect.fromLTRB(
                  offset.dx + box.left,
                  offset.dy + box.top,
                  offset.dx + box.right,
                  offset.dy + box.bottom,
                );
                if (rect.width > 0 && rect.height > 0) {
                  rects.add(rect);
                }
              }
              if (rects.isNotEmpty) {
                codeGroups.add(rects);
              }
            }

            // 收集 spoiler rects
            if (inSpoiler) {
              const codeHPadding = 3.5;
              const codeVPadding = 1.5;

              for (final box in boxes) {
                var rect = Rect.fromLTRB(
                  offset.dx + box.left,
                  offset.dy + box.top,
                  offset.dx + box.right,
                  offset.dy + box.bottom,
                );

                // 如果同时是 code，扩展范围以覆盖 code 背景的 padding
                if (isCode) {
                  rect = Rect.fromLTRB(
                    rect.left - codeHPadding,
                    rect.top - codeVPadding,
                    rect.right + codeHPadding,
                    rect.bottom + codeVPadding,
                  );
                }

                if (rect.width > 0 && rect.height > 0) {
                  spoilerRects.add(_TempRect(rect: rect, groupId: spoilerId!));
                }
              }
            }
          } catch (e) {
            // 忽略错误
          }
        }
      }

      charIndex += textLength;

      if (span.children != null) {
        String? childSpoilerId = spoilerId;
        for (final child in span.children!) {
          final result = _visitInlineSpan(
            child,
            paragraph,
            offset,
            charIndex,
            effectiveStyle,
            inSpoiler,
            childSpoilerId,
            paragraphIndex,
            codeGroups,
            spoilerRects,
          );
          charIndex = result.$1;
          if (result.$2 != null && inSpoiler) {
            // 只在当前 span 本身是 spoiler 上下文时，才把子节点的 spoilerId 传给后续兄弟
            // 这样同一 spoiler 元素内的子节点共享 ID，但不同 spoiler 元素各自独立
            childSpoilerId = result.$2;
            spoilerId ??= result.$2;
          }
        }
      }

      return (charIndex, spoilerId);
    } else if (span is WidgetSpan) {
      return (charIndex + 1, currentSpoilerId);
    }

    return (charIndex, currentSpoilerId);
  }

  List<SpoilerGroup> _buildSpoilerGroups(List<_TempRect> tempRects) {
    final Map<String, List<SpoilerRect>> groupMap = {};

    for (final temp in tempRects) {
      groupMap.putIfAbsent(temp.groupId, () => []).add(
        SpoilerRect(rect: temp.rect),
      );
    }

    final groups = <SpoilerGroup>[];
    for (final entry in groupMap.entries) {
      final normalizedRects = normalizeRowHeights(entry.value);
      groups.add(SpoilerGroup(id: entry.key, rects: normalizedRects));
    }
    return groups;
  }

  void _handleTap(Offset position) {
    for (final group in _spoilerGroups) {
      if (!group.isRevealed && group.containsPoint(position)) {
        group.isRevealed = true;
        widget.onReveal?.call(group.id);
        setState(() {});
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = theme.scaffoldBackgroundColor;

    final activeGroups = _spoilerGroups.where((g) => !g.isRevealed).toList();
    final hasCodeBackground = _codeGroups.isNotEmpty;
    final hasSpoilerOverlay = activeGroups.isNotEmpty;

    // 没有任何装饰层且从未出现过 spoiler 时，直接返回子组件，避免 Stack 开销
    // 注意：有 spoiler 组时必须保留 Stack，否则揭示后 widget tree 重构会导致 rescan → ID 变化
    if (!hasCodeBackground && !hasSpoilerOverlay && _spoilerGroups.isEmpty) {
      return widget.child;
    }

    return GestureDetector(
      onTapDown: hasSpoilerOverlay ? (details) => _handleTap(details.localPosition) : null,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          // Code 背景层（最底层）
          if (hasCodeBackground)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  child: CustomPaint(
                    painter: InlineCodePainter(
                      groups: _codeGroups,
                      isDark: isDark,
                    ),
                  ),
                ),
              ),
            ),
          // 内容层
          widget.child,
          // Spoiler 粒子层（最顶层）
          if (hasSpoilerOverlay)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: InlineSpoilerPainter(
                        groups: activeGroups,
                        isDark: isDark,
                        backgroundColor: backgroundColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 临时区域数据（扫描时使用）
class _TempRect {
  final Rect rect;
  final String groupId;
  _TempRect({required this.rect, required this.groupId});
}
