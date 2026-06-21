import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../../../../services/highlighter_service.dart';

/// 构建内联代码
Widget buildInlineCode({
  required ThemeData theme,
  required dynamic element,
  required double baseFontSize,
}) {
  final isDark = theme.brightness == Brightness.dark;
  final text = element.text ?? '';
  final fontSize = baseFontSize * 0.85;

  // 使用 FiraCode 字体
  final codeStyle = HighlighterService.instance.firaCodeStyle.copyWith(
    color: isDark ? const Color(0xFFb0b0b0) : const Color(0xFF666666),
    fontSize: fontSize,
    height: 1.2,
  );

  return InlineCustomWidget(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3a3a3a) : const Color(0xFFe8e8e8),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: codeStyle),
    ),
  );
}
