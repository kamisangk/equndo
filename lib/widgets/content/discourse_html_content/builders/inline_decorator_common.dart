import 'package:flutter/material.dart';

/// 用于标记 spoiler 的特殊字体名称
const String spoilerMarkerFont = '_SpoilerMarker_';

/// 用于标记内联代码的特殊字体名称
const String codeMarkerFont = '_InlineCode_';

/// 检查样式是否是 spoiler 标记
bool isSpoilerMarkerStyle(TextStyle? style) {
  if (style == null) return false;
  final fontFamily = style.fontFamily ?? '';
  if (fontFamily.contains(spoilerMarkerFont)) return true;
  final fallback = style.fontFamilyFallback ?? [];
  for (final f in fallback) {
    if (f.contains(spoilerMarkerFont)) return true;
  }
  return false;
}

/// 检查样式是否是内联代码
bool isCodeMarkerStyle(TextStyle? style) {
  if (style == null) return false;
  final fontFamily = style.fontFamily ?? '';
  if (fontFamily.contains(codeMarkerFont)) return true;
  final fallback = style.fontFamilyFallback ?? [];
  for (final f in fallback) {
    if (f.contains(codeMarkerFont)) return true;
  }
  return false;
}

/// 获取内联代码的 CSS 样式
Map<String, String> getInlineCodeStyles(bool isDark, {bool isInSpoiler = false}) {
  final fontFamily = isInSpoiler
      ? '$spoilerMarkerFont, $codeMarkerFont, FiraCode, monospace'
      : '$codeMarkerFont, FiraCode, monospace';
  return {
    'font-family': fontFamily,
    'background-color': '#00000000',
    'color': isDark ? '#b0b0b0' : '#666666',
    'font-size': '0.85em',
  };
}

/// 获取 spoiler 的 CSS 样式
Map<String, String> getSpoilerStyles() {
  return {
    'font-family': '$spoilerMarkerFont, inherit',
  };
}

/// 构建 click-count Widget
Widget buildClickCountWidget({
  required String count,
  required bool isDark,
}) {
  final bgColor = isDark ? const Color(0xFF3a3d47) : const Color(0xFFe8ebef);
  final textColor = isDark ? const Color(0xFF9ca3af) : const Color(0xFF6b7280);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      count,
      style: TextStyle(color: textColor, fontSize: 10),
    ),
  );
}
