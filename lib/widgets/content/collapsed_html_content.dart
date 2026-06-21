import 'package:flutter/material.dart';
import '../../services/discourse_cache_manager.dart';
import '../../utils/url_helper.dart';

/// 一个支持 maxLines 截断的简化 HTML 渲染组件
/// 主要用于个人简介的收起状态显示，保留 emoji 图片
class CollapsedHtmlContent extends StatelessWidget {
  final String html;
  final TextStyle? textStyle;
  final int maxLines;
  final TextOverflow overflow;

  const CollapsedHtmlContent({
    super.key,
    required this.html,
    this.textStyle,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    return _buildRichText(context);
  }

  Widget _buildRichText(BuildContext context) {
    final spans = _parseHtmlToSpans(html, textStyle, context);
    
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
      style: textStyle,
    );
  }

  List<InlineSpan> _parseHtmlToSpans(String htmlContent, TextStyle? style, BuildContext context) {
    final List<InlineSpan> spans = [];
    final imgRegExp = RegExp(
      r'''<img[^>]+src=["']([^"']+)["'][^>]*alt=["']([^"']*)["'][^>]*>|<img[^>]+alt=["']([^"']*)["'][^>]*src=["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    );
    
    int lastIndex = 0;
    
    // 简单的解析循环
    for (final match in imgRegExp.allMatches(htmlContent)) {
      // 添加前面的文本
      if (match.start > lastIndex) {
        final text = _stripTags(htmlContent.substring(lastIndex, match.start));
        if (text.isNotEmpty) {
          spans.add(TextSpan(text: text, style: style));
        }
      }

      // 添加图片（通常是 emoji）
      final src = match.group(1) ?? match.group(4);
      final alt = match.group(2) ?? match.group(3);
      // 判断是否是 emoji (class="emoji")
      final isEmoji = match.group(0)?.contains('class="emoji"') ?? false;

      if (src != null && isEmoji) {
        // 修正相对路径
        final fullUrl = UrlHelper.resolveUrlWithCdn(src);
        
        // 计算合适的 Emoji 尺寸
        final double emojiSize = (style?.fontSize ?? 14.0) * 1.3;
        
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Image(
              image: discourseImageProvider(fullUrl),
              width: emojiSize,
              height: emojiSize,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Text(alt ?? ''),
            ),
          ),
        );
      } else {
         // 非 emoji 图片，或者是普通图片，在简介里通常不显示大图，或者显示 alt
         if (alt != null && alt.isNotEmpty) {
           spans.add(TextSpan(text: alt, style: style));
         }
      }

      lastIndex = match.end;
    }

    // 添加剩余文本
    if (lastIndex < htmlContent.length) {
      final text = _stripTags(htmlContent.substring(lastIndex));
      if (text.isNotEmpty) {
        spans.add(TextSpan(text: text, style: style));
      }
    }

    return spans;
  }

  String _stripTags(String html) {
    // 移除所有 HTML 标签，只保留内容
    // 替换 <br> 为换行
    var text = html.replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n');
    // 移除其他标签
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');
    // 解码实体字符 (简单处理)
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    return text;
  }
}
