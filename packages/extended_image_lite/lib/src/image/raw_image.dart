import 'dart:ui' as ui show Image;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../gesture/utils.dart';
import '../typedef.dart';
import 'render_image.dart';

/// A widget that displays a [dart:ui.Image] directly.
/// Simplified version without editor support.
class ExtendedRawImage extends LeafRenderObjectWidget {
  const ExtendedRawImage({
    super.key,
    this.image,
    this.width,
    this.height,
    this.scale = 1.0,
    this.color,
    this.opacity,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.invertColors = false,
    this.filterQuality = FilterQuality.low,
    this.sourceRect,
    this.beforePaintImage,
    this.afterPaintImage,
    this.gestureDetails,
    this.isAntiAlias = false,
    this.debugImageLabel,
    this.layoutInsets = EdgeInsets.zero,
  });

  /// details about gesture
  final GestureDetails? gestureDetails;

  ///you can paint anything if you want before paint image.
  final BeforePaintImage? beforePaintImage;

  ///you can paint anything if you want after paint image.
  final AfterPaintImage? afterPaintImage;

  /// The image to display.
  final ui.Image? image;

  /// A string identifying the source of the image.
  final String? debugImageLabel;

  /// If non-null, require the image to have this width.
  final double? width;

  /// If non-null, require the image to have this height.
  final double? height;

  /// Specifies the image's scale.
  final double scale;

  /// If non-null, this color is blended with each image pixel using [colorBlendMode].
  final Color? color;

  /// If non-null, the value from the [Animation] is multiplied with the opacity
  /// of each image pixel before painting onto the canvas.
  final Animation<double>? opacity;

  /// Used to set the filterQuality of the image.
  final FilterQuality filterQuality;

  /// Used to combine [color] with this image.
  final BlendMode? colorBlendMode;

  /// How to inscribe the image into the space allocated during layout.
  final BoxFit? fit;

  /// How to align the image within its bounds.
  final AlignmentGeometry alignment;

  /// How to paint any portions of the layout bounds not covered by the image.
  final ImageRepeat repeat;

  /// The center slice for a nine-patch image.
  final Rect? centerSlice;

  /// Whether to paint the image in the direction of the [TextDirection].
  final bool matchTextDirection;

  /// Whether the colors of the image are inverted when drawn.
  final bool invertColors;

  ///input Rect, you can use this to crop image.
  final Rect? sourceRect;

  /// Insets to apply before laying out the image.
  final EdgeInsets layoutInsets;

  /// Whether to paint the image with anti-aliasing.
  final bool isAntiAlias;

  @override
  ExtendedRenderImage createRenderObject(BuildContext context) {
    assert(
      (!matchTextDirection && alignment is Alignment) ||
          debugCheckHasDirectionality(context),
    );
    assert(
      image?.debugGetOpenHandleStackTraces()?.isNotEmpty ?? true,
      'Creator of a RawImage disposed of the image when the RawImage still '
      'needed it.',
    );
    return ExtendedRenderImage(
      image: image?.clone(),
      debugImageLabel: debugImageLabel,
      width: width,
      height: height,
      scale: scale,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      textDirection:
          matchTextDirection || alignment is! Alignment
              ? Directionality.of(context)
              : null,
      invertColors: invertColors,
      isAntiAlias: isAntiAlias,
      filterQuality: filterQuality,
      sourceRect: sourceRect,
      beforePaintImage: beforePaintImage,
      afterPaintImage: afterPaintImage,
      gestureDetails: gestureDetails,
      layoutInsets: layoutInsets,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    ExtendedRenderImage renderObject,
  ) {
    assert(
      image?.debugGetOpenHandleStackTraces()?.isNotEmpty ?? true,
      'Creator of a RawImage disposed of the image when the RawImage still '
      'needed it.',
    );
    renderObject
      ..image = image?.clone()
      ..debugImageLabel = debugImageLabel
      ..width = width
      ..height = height
      ..scale = scale
      ..color = color
      ..opacity = opacity
      ..colorBlendMode = colorBlendMode
      ..fit = fit
      ..alignment = alignment
      ..repeat = repeat
      ..centerSlice = centerSlice
      ..matchTextDirection = matchTextDirection
      ..textDirection =
          matchTextDirection || alignment is! Alignment
              ? Directionality.of(context)
              : null
      ..invertColors = invertColors
      ..isAntiAlias = isAntiAlias
      ..filterQuality = filterQuality
      ..layoutInsets = layoutInsets
      ..afterPaintImage = afterPaintImage
      ..beforePaintImage = beforePaintImage
      ..sourceRect = sourceRect
      ..gestureDetails = gestureDetails;
  }

  @override
  void didUnmountRenderObject(ExtendedRenderImage renderObject) {
    renderObject.image = null;
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
    properties.add(DiagnosticsProperty<bool>('invertColors', invertColors));
    properties.add(EnumProperty<FilterQuality>('filterQuality', filterQuality));
    properties.add(
      DiagnosticsProperty<EdgeInsets>('layoutInsets', layoutInsets),
    );
  }
}
