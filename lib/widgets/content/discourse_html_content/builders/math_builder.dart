import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

/// 构建块级数学公式 (div.math)
/// 居中显示，支持水平滚动（超长公式）
Widget buildMathBlock({
  required BuildContext context,
  required ThemeData theme,
  required dynamic element,
}) {
  final latex = element.text?.trim() ?? '';

  if (latex.isEmpty) {
    return const SizedBox.shrink();
  }

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _buildMathWidget(
          latex: latex,
          textStyle: TextStyle(
            fontSize: 16,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    ),
  );
}

/// 构建行内数学公式 (span.math)
/// 返回 InlineCustomWidget 包裹的 Math.tex()
Widget buildInlineMath({
  required BuildContext context,
  required ThemeData theme,
  required dynamic element,
}) {
  final latex = element.text?.trim() ?? '';

  if (latex.isEmpty) {
    return const SizedBox.shrink();
  }

  return InlineCustomWidget(
    child: _buildMathWidget(
      latex: latex,
      textStyle: TextStyle(
        fontSize: 14,
        color: theme.colorScheme.onSurface,
      ),
    ),
  );
}

/// 内部方法：构建 Math widget，处理错误 fallback
Widget _buildMathWidget({
  required String latex,
  required TextStyle textStyle,
}) {
  return Math.tex(
    latex,
    textStyle: textStyle,
    onErrorFallback: (error) {
      // 解析失败时显示原始 LaTeX 文本
      return Text(
        latex,
        style: textStyle.copyWith(
          fontFamily: 'monospace',
          color: textStyle.color?.withValues(alpha: 0.7),
        ),
      );
    },
  );
}
