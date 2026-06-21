import 'dart:convert';
import 'dart:math' as math;

/// SVG 处理工具类
///
/// 提供 SVG 内容清理功能，移除 jovial_svg 不支持的元素。
///
/// jovial_svg 原生支持 CSS `<style>`、`<text>`、`<clipPath>`、`<mask>` 等，
/// 因此只需移除少量不支持的特性：
/// - SMIL 动画元素
/// - `<filter>` 元素和 filter 属性
/// - 嵌套 SVG 标签
class SvgUtils {
  SvgUtils._();

  /// 通过文件内容判断是否为 SVG，而不是依赖 URL 后缀。
  static bool isSvgBytes(List<int> bytes) {
    if (bytes.isEmpty) return false;

    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }

    while (start < bytes.length && bytes[start] <= 32) {
      start++;
    }
    if (start >= bytes.length) return false;

    final end = math.min(bytes.length, start + 4096);
    final sample = utf8
        .decode(bytes.sublist(start, end), allowMalformed: true)
        .trimLeft()
        .toLowerCase();

    if (sample.startsWith('<svg')) return true;
    return sample.startsWith('<?xml') && sample.contains('<svg');
  }

  /// 将 SVG 字节按 UTF-8 解码。
  static String decodeSvgBytes(List<int> bytes) {
    final svg = utf8.decode(bytes, allowMalformed: true);
    return svg.startsWith('\uFEFF') ? svg.substring(1) : svg;
  }

  /// 清理 SVG 内容，移除渲染引擎不支持的元素
  static String sanitize(String svg) {
    String result = svg;

    // 1. 移除 `<filter>` 元素和 filter 属性引用
    result = _removeFilters(result);

    // 2. 移除 SMIL 动画标签
    result = _removeAnimations(result);

    // 3. 处理嵌套的 SVG 标签
    result = _flattenNestedSvg(result);

    return result;
  }

  /// 移除 `<filter>` 元素和相关属性引用
  static String _removeFilters(String content) {
    String result = content;

    // 移除 <filter>...</filter>
    result = result.replaceAll(
      RegExp(
        r'<filter\b[^>]*>.*?</filter>',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );

    // 移除 filter 属性引用
    result = result.replaceAll(
      RegExp(r'\s*filter\s*=\s*"[^"]*"', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'filter\s*:\s*[^;]+;', caseSensitive: false),
      '',
    );

    return result;
  }

  /// 移除 SMIL 动画标签
  static String _removeAnimations(String content) {
    final smilPattern = RegExp(
      r'<(animate|animateTransform|animateMotion|animateColor|set)\b[^>]*(?:/>|>.*?</\1>)',
      caseSensitive: false,
      dotAll: true,
    );
    return content.replaceAll(smilPattern, '');
  }

  /// 处理嵌套的 SVG 标签 - 提取内层 SVG 的内容合并到外层
  static String _flattenNestedSvg(String content) {
    String result = content;

    final nestedSvgPattern = RegExp(
      r'(<svg\b[^>]*>)\s*<svg\b[^>]*>(.*?)</svg>\s*(</svg>)',
      caseSensitive: false,
      dotAll: true,
    );

    while (nestedSvgPattern.hasMatch(result)) {
      result = result.replaceFirstMapped(nestedSvgPattern, (match) {
        final outerStart = match.group(1)!;
        final innerContent = match.group(2)!;
        final outerEnd = match.group(3)!;
        return '$outerStart$innerContent$outerEnd';
      });
    }

    return result;
  }
}
