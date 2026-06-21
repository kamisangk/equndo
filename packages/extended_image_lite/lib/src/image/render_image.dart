import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart' hide Image;
import 'package:flutter/rendering.dart';

import '../gesture/utils.dart';
import '../typedef.dart';
import 'painting.dart';

/// Render object for displaying images with gesture support.
/// Simplified version without editor support.
class ExtendedRenderImage extends RenderBox {
  ExtendedRenderImage({
    ui.Image? image,
    this.debugImageLabel,
    double? width,
    double? height,
    double scale = 1.0,
    Color? color,
    Animation<double>? opacity,
    BlendMode? colorBlendMode,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    ImageRepeat repeat = ImageRepeat.noRepeat,
    Rect? centerSlice,
    bool matchTextDirection = false,
    TextDirection? textDirection,
    bool invertColors = false,
    bool isAntiAlias = false,
    FilterQuality filterQuality = FilterQuality.low,
    Rect? sourceRect,
    AfterPaintImage? afterPaintImage,
    BeforePaintImage? beforePaintImage,
    GestureDetails? gestureDetails,
    EdgeInsets layoutInsets = EdgeInsets.zero,
  }) : _image = image,
       _width = width,
       _height = height,
       _scale = scale,
       _color = color,
       _opacity = opacity,
       _colorBlendMode = colorBlendMode,
       _fit = fit,
       _alignment = alignment,
       _repeat = repeat,
       _centerSlice = centerSlice,
       _matchTextDirection = matchTextDirection,
       _invertColors = invertColors,
       _textDirection = textDirection,
       _isAntiAlias = isAntiAlias,
       _filterQuality = filterQuality,
       _sourceRect = sourceRect,
       _beforePaintImage = beforePaintImage,
       _afterPaintImage = afterPaintImage,
       _gestureDetails = gestureDetails,
       _layoutInsets = layoutInsets {
    _updateColorFilter();
  }

  EdgeInsets _layoutInsets;
  EdgeInsets get layoutInsets => _layoutInsets;
  set layoutInsets(EdgeInsets value) {
    if (value == _layoutInsets) {
      return;
    }
    _layoutInsets = value;
    markNeedsPaint();
  }

  GestureDetails? _gestureDetails;
  GestureDetails? get gestureDetails => _gestureDetails;
  set gestureDetails(GestureDetails? value) {
    if (value == _gestureDetails) {
      return;
    }
    _gestureDetails = value;
    markNeedsPaint();
  }

  BeforePaintImage? _beforePaintImage;
  BeforePaintImage? get beforePaintImage => _beforePaintImage;
  set beforePaintImage(BeforePaintImage? value) {
    if (value == _beforePaintImage) {
      return;
    }
    _beforePaintImage = value;
    markNeedsPaint();
  }

  AfterPaintImage? _afterPaintImage;
  AfterPaintImage? get afterPaintImage => _afterPaintImage;
  set afterPaintImage(AfterPaintImage? value) {
    if (value == _afterPaintImage) {
      return;
    }
    _afterPaintImage = value;
    markNeedsPaint();
  }

  Rect? _sourceRect;
  Rect? get sourceRect => _sourceRect;
  set sourceRect(Rect? value) {
    if (value == _sourceRect) {
      return;
    }
    _sourceRect = value;
    markNeedsPaint();
  }

  Alignment? _resolvedAlignment;
  bool? _flipHorizontally;

  void _resolve() {
    if (_resolvedAlignment != null) {
      return;
    }
    _resolvedAlignment = alignment.resolve(textDirection);
    _flipHorizontally =
        matchTextDirection && textDirection == TextDirection.rtl;
  }

  void _markNeedResolution() {
    _resolvedAlignment = null;
    _flipHorizontally = null;
    markNeedsPaint();
  }

  ui.Image? get image => _image;
  ui.Image? _image;
  set image(ui.Image? value) {
    if (value == _image) {
      return;
    }
    if (value != null && _image != null && value.isCloneOf(_image!)) {
      value.dispose();
      return;
    }
    _image?.dispose();
    _image = value;
    markNeedsPaint();
    if (_width == null || _height == null) {
      markNeedsLayout();
    }
  }

  String? debugImageLabel;

  double? get width => _width;
  double? _width;
  set width(double? value) {
    if (value == _width) {
      return;
    }
    _width = value;
    markNeedsLayout();
  }

  double? get height => _height;
  double? _height;
  set height(double? value) {
    if (value == _height) {
      return;
    }
    _height = value;
    markNeedsLayout();
  }

  double get scale => _scale;
  double _scale;
  set scale(double value) {
    if (value == _scale) {
      return;
    }
    _scale = value;
    markNeedsLayout();
  }

  ColorFilter? _colorFilter;

  void _updateColorFilter() {
    if (_color == null) {
      _colorFilter = null;
    } else {
      _colorFilter = ColorFilter.mode(
        _color!,
        _colorBlendMode ?? BlendMode.srcIn,
      );
    }
  }

  Color? get color => _color;
  Color? _color;
  set color(Color? value) {
    if (value == _color) {
      return;
    }
    _color = value;
    _updateColorFilter();
    markNeedsPaint();
  }

  Animation<double>? get opacity => _opacity;
  Animation<double>? _opacity;
  set opacity(Animation<double>? value) {
    if (value == _opacity) {
      return;
    }

    if (attached) {
      _opacity?.removeListener(markNeedsPaint);
    }
    _opacity = value;
    if (attached) {
      value?.addListener(markNeedsPaint);
    }
  }

  FilterQuality get filterQuality => _filterQuality;
  FilterQuality _filterQuality;
  set filterQuality(FilterQuality value) {
    if (value == _filterQuality) {
      return;
    }
    _filterQuality = value;
    markNeedsPaint();
  }

  BlendMode? get colorBlendMode => _colorBlendMode;
  BlendMode? _colorBlendMode;
  set colorBlendMode(BlendMode? value) {
    if (value == _colorBlendMode) {
      return;
    }
    _colorBlendMode = value;
    _updateColorFilter();
    markNeedsPaint();
  }

  BoxFit? get fit => _fit;
  BoxFit? _fit;
  set fit(BoxFit? value) {
    if (value == _fit) {
      return;
    }
    _fit = value;
    markNeedsPaint();
  }

  AlignmentGeometry get alignment => _alignment;
  AlignmentGeometry _alignment;
  set alignment(AlignmentGeometry value) {
    if (value == _alignment) {
      return;
    }
    _alignment = value;
    _markNeedResolution();
  }

  ImageRepeat get repeat => _repeat;
  ImageRepeat _repeat;
  set repeat(ImageRepeat value) {
    if (value == _repeat) {
      return;
    }
    _repeat = value;
    markNeedsPaint();
  }

  Rect? get centerSlice => _centerSlice;
  Rect? _centerSlice;
  set centerSlice(Rect? value) {
    if (value == _centerSlice) {
      return;
    }
    _centerSlice = value;
    markNeedsPaint();
  }

  bool get invertColors => _invertColors;
  bool _invertColors;
  set invertColors(bool value) {
    if (value == _invertColors) {
      return;
    }
    _invertColors = value;
    markNeedsPaint();
  }

  bool get matchTextDirection => _matchTextDirection;
  bool _matchTextDirection;
  set matchTextDirection(bool value) {
    if (value == _matchTextDirection) {
      return;
    }
    _matchTextDirection = value;
    _markNeedResolution();
  }

  TextDirection? get textDirection => _textDirection;
  TextDirection? _textDirection;
  set textDirection(TextDirection? value) {
    if (_textDirection == value) {
      return;
    }
    _textDirection = value;
    _markNeedResolution();
  }

  bool get isAntiAlias => _isAntiAlias;
  bool _isAntiAlias;
  set isAntiAlias(bool value) {
    if (_isAntiAlias == value) {
      return;
    }
    _isAntiAlias = value;
    markNeedsPaint();
  }

  Size _sizeForConstraints(BoxConstraints constraints) {
    constraints = BoxConstraints.tightFor(
      width: _width,
      height: _height,
    ).enforce(constraints);

    if (_image == null) {
      return constraints.smallest;
    }

    return constraints.constrainSizeAndAttemptToPreserveAspectRatio(
      Size(
        _image!.width.toDouble() / _scale,
        _image!.height.toDouble() / _scale,
      ),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    assert(height >= 0.0);
    if (_width == null && _height == null) {
      return 0.0;
    }
    return _sizeForConstraints(
      BoxConstraints.tightForFinite(height: height),
    ).width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    assert(height >= 0.0);
    return _sizeForConstraints(
      BoxConstraints.tightForFinite(height: height),
    ).width;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    assert(width >= 0.0);
    if (_width == null && _height == null) {
      return 0.0;
    }
    return _sizeForConstraints(
      BoxConstraints.tightForFinite(width: width),
    ).height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    assert(width >= 0.0);
    return _sizeForConstraints(
      BoxConstraints.tightForFinite(width: width),
    ).height;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return _sizeForConstraints(constraints);
  }

  @override
  void performLayout() {
    size = _sizeForConstraints(constraints);
  }

  @override
  void attach(covariant PipelineOwner owner) {
    super.attach(owner);
    _opacity?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _opacity?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_image == null) {
      return;
    }
    _resolve();
    assert(_resolvedAlignment != null);
    assert(_flipHorizontally != null);
    Rect rect = offset & size;
    if (gestureDetails != null && gestureDetails!.slidePageOffset != null) {
      rect = rect.shift(-gestureDetails!.slidePageOffset!);
    }
    paintExtendedImage(
      canvas: context.canvas,
      rect: rect,
      image: _image!,
      debugImageLabel: debugImageLabel,
      scale: _scale,
      opacity: _opacity?.value ?? 1.0,
      colorFilter: _colorFilter,
      fit: _fit,
      alignment: _resolvedAlignment!,
      centerSlice: _centerSlice,
      repeat: _repeat,
      flipHorizontally: _flipHorizontally!,
      invertColors: invertColors,
      filterQuality: _filterQuality,
      isAntiAlias: _isAntiAlias,
      customSourceRect: _sourceRect,
      beforePaintImage: beforePaintImage,
      afterPaintImage: afterPaintImage,
      gestureDetails: gestureDetails,
      layoutInsets: layoutInsets,
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<ui.Image>('image', image));
    properties.add(DoubleProperty('width', width, defaultValue: null));
    properties.add(DoubleProperty('height', height, defaultValue: null));
    properties.add(DoubleProperty('scale', scale, defaultValue: 1.0));
    properties.add(ColorProperty('color', color, defaultValue: null));
    properties.add(
      DiagnosticsProperty<Animation<double>?>(
        'opacity',
        opacity,
        defaultValue: null,
      ),
    );
    properties.add(
      EnumProperty<BlendMode>(
        'colorBlendMode',
        colorBlendMode,
        defaultValue: null,
      ),
    );
    properties.add(EnumProperty<BoxFit>('fit', fit, defaultValue: null));
    properties.add(
      DiagnosticsProperty<AlignmentGeometry>(
        'alignment',
        alignment,
        defaultValue: null,
      ),
    );
    properties.add(
      EnumProperty<ImageRepeat>(
        'repeat',
        repeat,
        defaultValue: ImageRepeat.noRepeat,
      ),
    );
    properties.add(
      DiagnosticsProperty<Rect>('centerSlice', centerSlice, defaultValue: null),
    );
    properties.add(
      FlagProperty(
        'matchTextDirection',
        value: matchTextDirection,
        ifTrue: 'match text direction',
      ),
    );
    properties.add(
      EnumProperty<TextDirection>(
        'textDirection',
        textDirection,
        defaultValue: null,
      ),
    );
    properties.add(DiagnosticsProperty<bool>('invertColors', invertColors));
    properties.add(EnumProperty<FilterQuality>('filterQuality', filterQuality));
  }
}
