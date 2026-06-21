import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 让任意 Widget 参与 SelectionArea 的文本选择
///
/// 基于 Flutter 官方示例 (selectable_region.0.dart)，
/// 将子 Widget 注册到选择系统中，选中时返回指定的纯文本内容。
/// 用于让 emoji 图片、inline 图标等参与划词选择。
class SelectableAdapter extends StatelessWidget {
  const SelectableAdapter({
    super.key,
    required this.selectedText,
    required this.child,
  });

  /// 选中时返回的纯文本（如 emoji 的 ":smile:"）
  final String selectedText;

  /// 子 Widget（通常是 Image）
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
    if (registrar == null) {
      return child;
    }
    return _SelectableAdapterWidget(
      registrar: registrar,
      selectedText: selectedText,
      child: child,
    );
  }
}

class _SelectableAdapterWidget extends SingleChildRenderObjectWidget {
  const _SelectableAdapterWidget({
    required this.registrar,
    required this.selectedText,
    required Widget child,
  }) : super(child: child);

  final SelectionRegistrar registrar;
  final String selectedText;

  @override
  _RenderSelectableAdapter createRenderObject(BuildContext context) {
    return _RenderSelectableAdapter(
      DefaultSelectionStyle.of(context).selectionColor ?? Colors.blue.withValues(alpha: 0.4),
      registrar,
      selectedText,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderSelectableAdapter renderObject) {
    renderObject
      ..selectionColor = DefaultSelectionStyle.of(context).selectionColor ?? Colors.blue.withValues(alpha: 0.4)
      ..registrar = registrar
      ..selectedText = selectedText;
  }
}

class _RenderSelectableAdapter extends RenderProxyBox
    with Selectable, SelectionRegistrant {
  _RenderSelectableAdapter(
    Color selectionColor,
    SelectionRegistrar registrar,
    this._selectedText,
  ) : _selectionColor = selectionColor,
      _geometry = ValueNotifier<SelectionGeometry>(_noSelection) {
    this.registrar = registrar;
    _geometry.addListener(markNeedsPaint);
  }

  static const SelectionGeometry _noSelection = SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: true,
  );

  final ValueNotifier<SelectionGeometry> _geometry;

  String _selectedText;
  set selectedText(String value) {
    if (_selectedText == value) return;
    _selectedText = value;
  }

  Color get selectionColor => _selectionColor;
  Color _selectionColor;
  set selectionColor(Color value) {
    if (_selectionColor == value) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  // ValueListenable APIs

  @override
  void addListener(VoidCallback listener) => _geometry.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _geometry.removeListener(listener);

  @override
  SelectionGeometry get value => _geometry.value;

  // Selectable APIs

  @override
  List<Rect> get boundingBoxes => <Rect>[paintBounds];

  Rect _getSelectionHighlightRect() {
    return Rect.fromLTWH(0, 0, size.width, size.height);
  }

  Offset? _start;
  Offset? _end;

  void _updateGeometry() {
    if (_start == null || _end == null) {
      _geometry.value = _noSelection;
      return;
    }
    final renderObjectRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final selectionRect = Rect.fromPoints(_start!, _end!);
    if (renderObjectRect.intersect(selectionRect).isEmpty) {
      _geometry.value = _noSelection;
    } else {
      final highlightRect = _getSelectionHighlightRect();
      final firstPoint = SelectionPoint(
        localPosition: highlightRect.bottomLeft,
        lineHeight: highlightRect.size.height,
        handleType: TextSelectionHandleType.left,
      );
      final secondPoint = SelectionPoint(
        localPosition: highlightRect.bottomRight,
        lineHeight: highlightRect.size.height,
        handleType: TextSelectionHandleType.right,
      );
      final bool isReversed;
      if (_start!.dy > _end!.dy) {
        isReversed = true;
      } else if (_start!.dy < _end!.dy) {
        isReversed = false;
      } else {
        isReversed = _start!.dx > _end!.dx;
      }
      _geometry.value = SelectionGeometry(
        status: SelectionStatus.uncollapsed,
        hasContent: true,
        startSelectionPoint: isReversed ? secondPoint : firstPoint,
        endSelectionPoint: isReversed ? firstPoint : secondPoint,
        selectionRects: <Rect>[highlightRect],
      );
    }
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    SelectionResult result = SelectionResult.none;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final renderObjectRect = Rect.fromLTWH(0, 0, size.width, size.height);
        final point = globalToLocal((event as SelectionEdgeUpdateEvent).globalPosition);
        final adjustedPoint = SelectionUtils.adjustDragOffset(renderObjectRect, point);
        if (event.type == SelectionEventType.startEdgeUpdate) {
          _start = adjustedPoint;
        } else {
          _end = adjustedPoint;
        }
        result = SelectionUtils.getResultBasedOnRect(renderObjectRect, point);
      case SelectionEventType.clear:
        _start = _end = null;
      case SelectionEventType.selectAll:
      case SelectionEventType.selectWord:
      case SelectionEventType.selectParagraph:
        _start = Offset.zero;
        _end = Offset.infinite;
      case SelectionEventType.granularlyExtendSelection:
        result = SelectionResult.end;
        final extendEvent = event as GranularlyExtendSelectionEvent;
        if (_start == null || _end == null) {
          if (extendEvent.forward) {
            _start = _end = Offset.zero;
          } else {
            _start = _end = Offset.infinite;
          }
        }
        final newOffset = extendEvent.forward ? Offset.infinite : Offset.zero;
        if (extendEvent.isEnd) {
          if (newOffset == _end) {
            result = extendEvent.forward ? SelectionResult.next : SelectionResult.previous;
          }
          _end = newOffset;
        } else {
          if (newOffset == _start) {
            result = extendEvent.forward ? SelectionResult.next : SelectionResult.previous;
          }
          _start = newOffset;
        }
      case SelectionEventType.directionallyExtendSelection:
        result = SelectionResult.end;
        final extendEvent = event as DirectionallyExtendSelectionEvent;
        final horizontalBaseLine = globalToLocal(Offset(event.dx, 0)).dx;
        final Offset newOffset;
        final bool forward;
        switch (extendEvent.direction) {
          case SelectionExtendDirection.backward:
          case SelectionExtendDirection.previousLine:
            forward = false;
            if (_start == null || _end == null) {
              _start = _end = Offset.infinite;
            }
            if (extendEvent.direction == SelectionExtendDirection.previousLine ||
                horizontalBaseLine < 0) {
              newOffset = Offset.zero;
            } else {
              newOffset = Offset.infinite;
            }
          case SelectionExtendDirection.nextLine:
          case SelectionExtendDirection.forward:
            forward = true;
            if (_start == null || _end == null) {
              _start = _end = Offset.zero;
            }
            if (extendEvent.direction == SelectionExtendDirection.nextLine ||
                horizontalBaseLine > size.width) {
              newOffset = Offset.infinite;
            } else {
              newOffset = Offset.zero;
            }
        }
        if (extendEvent.isEnd) {
          if (newOffset == _end) {
            result = forward ? SelectionResult.next : SelectionResult.previous;
          }
          _end = newOffset;
        } else {
          if (newOffset == _start) {
            result = forward ? SelectionResult.next : SelectionResult.previous;
          }
          _start = newOffset;
        }
    }
    _updateGeometry();
    return result;
  }

  @override
  SelectedContent? getSelectedContent() {
    return value.hasSelection ? SelectedContent(plainText: _selectedText) : null;
  }

  @override
  SelectedContentRange? getSelection() {
    if (!value.hasSelection) return null;
    return SelectedContentRange(startOffset: 0, endOffset: _selectedText.length);
  }

  @override
  int get contentLength => _selectedText.length;

  LayerLink? _startHandle;
  LayerLink? _endHandle;

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (_startHandle == startHandle && _endHandle == endHandle) return;
    _startHandle = startHandle;
    _endHandle = endHandle;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_geometry.value.hasSelection) return;

    // 绘制选中高亮
    final selectionPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _selectionColor;
    context.canvas.drawRect(_getSelectionHighlightRect().shift(offset), selectionPaint);

    if (_startHandle != null) {
      context.pushLayer(
        LeaderLayer(link: _startHandle!, offset: offset + value.startSelectionPoint!.localPosition),
        (PaintingContext context, Offset offset) {},
        Offset.zero,
      );
    }
    if (_endHandle != null) {
      context.pushLayer(
        LeaderLayer(link: _endHandle!, offset: offset + value.endSelectionPoint!.localPosition),
        (PaintingContext context, Offset offset) {},
        Offset.zero,
      );
    }
  }

  @override
  void dispose() {
    _geometry.dispose();
    _startHandle = null;
    _endHandle = null;
    super.dispose();
  }
}
