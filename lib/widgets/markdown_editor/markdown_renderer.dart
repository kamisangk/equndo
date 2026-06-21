import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import '../content/discourse_html_content/discourse_html_content.dart';
import '../../services/emoji_handler.dart';
import '../../constants.dart';
import '../../utils/url_helper.dart';

/// Markdown 预览组件
/// 使用官方 markdown 包将 Markdown 转换为 HTML，
/// 再用 DiscourseHtmlContent 渲染，保持与帖子显示样式一致
class MarkdownBody extends StatelessWidget {
  final String data;
  /// 内部链接点击回调（话题链接）
  final void Function(int topicId, String? topicSlug, int? postNumber)? onInternalLinkTap;

  const MarkdownBody({super.key, required this.data, this.onInternalLinkTap});
  
  @override
  Widget build(BuildContext context) {
    // 1. 处理 Emoji 替换 (将 :smile: 转为 <img>)
    var processedData = EmojiHandler().replaceEmojis(data);
    
    // 2. 预处理 @用户名 提及（转换为 HTML 链接）
    processedData = _processMentions(processedData);
    
    // 3. 预处理 Discourse 图片格式 (![alt|WxH](url) -> HTML img)
    processedData = _processDiscourseImages(processedData);

    // 3.5 确保标准 markdown 图片前后有空行，使其独占段落
    processedData = processedData.replaceAllMapped(
      RegExp(r'(?<!\n\n)(!\[[^\]]*\]\([^)]+\))'),
      (m) => '\n\n${m.group(1)!}',
    );
    processedData = processedData.replaceAllMapped(
      RegExp(r'(!\[[^\]]*\]\([^)]+\))(?!\n\n)'),
      (m) => '${m.group(1)!}\n\n',
    );
    processedData = processedData.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    processedData = processedData.trim();

    // 4. 预处理 [quote] 标记（转换为占位符，避免被 markdown 解析干扰）
    final quoteBlocks = <String, String>{};
    processedData = _processQuoteBlocks(processedData, quoteBlocks);

    // 5. 预处理 [spoiler] 标记（转换为占位符或行内 HTML）
    final spoilerBlocks = <String, String>{};
    processedData = _processSpoilerBlocks(processedData, spoilerBlocks);

    // 5. 预处理 [grid] 标记（转换为占位符，避免被 markdown 解析干扰）
    final gridBlocks = <String, String>{};
    processedData = _extractGridBlocks(processedData, gridBlocks);

    // 6. 将单个换行转换为硬换行，使预览换行行为符合用户直觉
    processedData = _convertSoftBreaks(processedData);

    // 7. 使用 GitHub Flavored Markdown 扩展集转换为 HTML
    var html = md.markdownToHtml(
      processedData,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );

    // 8. 后处理：将 grid 占位符替换回 div.d-image-grid 包裹的图片
    html = _restoreGridBlocks(html, gridBlocks);

    // 9. 后处理：将 spoiler 占位符替换回 div.spoiler
    html = _restoreSpoilerBlocks(html, spoilerBlocks);

    // 10. 后处理：将 quote 占位符替换回 aside.quote
    html = _restoreQuoteBlocks(html, quoteBlocks);

    // 11. 使用 DiscourseHtmlContent 渲染，与帖子显示保持一致
    return DiscourseHtmlContent(
      html: html,
      textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
        height: 1.5,
      ),
      onInternalLinkTap: onInternalLinkTap,
    );
  }
  
  /// 将单个换行转换为硬换行（行尾添加两个空格）
  /// 标准 Markdown 把单个换行当作空格，但用户通常期望换行就是换行
  String _convertSoftBreaks(String text) {
    final lines = text.split('\n');
    final result = StringBuffer();
    bool inCodeBlock = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.trimLeft().startsWith('```')) {
        inCodeBlock = !inCodeBlock;
      }

      if (!inCodeBlock &&
          i < lines.length - 1 &&
          line.isNotEmpty &&
          lines[i + 1].isNotEmpty &&
          !line.endsWith('  ')) {
        result.write('$line  ');
      } else {
        result.write(line);
      }

      if (i < lines.length - 1) {
        result.write('\n');
      }
    }

    return result.toString();
  }

  /// 处理 Discourse 图片格式：![alt|widthxheight](url) -> <img src="" width="" height="" alt="">
  /// 标准 Markdown 包不识别竖线语法，需要手动转换
  String _processDiscourseImages(String text) {
    // 匹配 ![alt|WxH](url) 格式
    final discourseImageRegex = RegExp(
      r'!\[([^\]|]*)\|(\d+)x(\d+)\]\(([^)\s]+)\)',
    );
    
    return text.replaceAllMapped(discourseImageRegex, (match) {
      final alt = match.group(1) ?? '';
      final width = match.group(2)!;
      final height = match.group(3)!;
      var src = match.group(4) ?? '';

      // upload:// 短链接保留原始值，由下游 widget factory 异步解析
      if (!src.startsWith('upload://')) {
        src = UrlHelper.resolveUrlWithCdn(src);
      }

      return '\n\n<img src="$src" alt="$alt" width="$width" height="$height">\n\n';
    });
    // 清理多余空行（连续 3 个以上换行合并为 2 个）
    // text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }
  
  
  /// 预处理 [spoiler]...[/spoiler] 标记
  /// 块级 spoiler（内容含换行）使用占位符模式，行内 spoiler 直接替换为 HTML
  String _processSpoilerBlocks(String text, Map<String, String> spoilerBlocks) {
    final spoilerRegex = RegExp(
      r'\[spoiler\](.*?)\[/spoiler\]',
      multiLine: true,
      dotAll: true,
    );

    int index = 0;
    return text.replaceAllMapped(spoilerRegex, (match) {
      final content = match.group(1) ?? '';

      if (content.contains('\n')) {
        // 块级 spoiler：使用占位符，避免 markdown 解析器干扰
        final placeholder = '<!--SPOILER_PLACEHOLDER_$index-->';
        spoilerBlocks[placeholder] = content.trim();
        index++;
        return placeholder;
      } else {
        // 行内 spoiler：直接转为 HTML
        return '<span class="spoiler">${_escapeHtml(content)}</span>';
      }
    });
  }

  /// 后处理：将 spoiler 占位符替换为 div.spoiler
  String _restoreSpoilerBlocks(String html, Map<String, String> spoilerBlocks) {
    var result = html;

    for (final entry in spoilerBlocks.entries) {
      final placeholder = entry.key;
      final markdownContent = entry.value;

      // 将 spoiler 内的 markdown 转成 HTML
      final spoilerHtml = md.markdownToHtml(
        markdownContent,
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );

      final replacement = '<div class="spoiler">$spoilerHtml</div>';

      // 替换占位符（可能被 <p> 包裹了）
      result = result.replaceAll('<p>$placeholder</p>', replacement);
      result = result.replaceAll(placeholder, replacement);
    }

    return result;
  }

  /// 转义 HTML 特殊字符
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// 提取 [grid]...[/grid] 块，用唯一占位符替换
  /// 这样 markdown 解析器会正常处理其中的图片为 <img> 标签
  String _extractGridBlocks(String text, Map<String, String> gridBlocks) {
    final gridRegex = RegExp(
      r'\[grid\]\s*(.*?)\s*\[/grid\]',
      multiLine: true,
      dotAll: true,
    );
    
    int index = 0;
    return text.replaceAllMapped(gridRegex, (match) {
      final content = match.group(1) ?? '';
      final placeholder = '<!--GRID_PLACEHOLDER_$index-->';
      gridBlocks[placeholder] = content;
      index++;
      return placeholder;
    });
  }
  
  /// 后处理：将 grid 占位符替换为 div.d-image-grid 包裹的图片
  String _restoreGridBlocks(String html, Map<String, String> gridBlocks) {
    var result = html;
    
    for (final entry in gridBlocks.entries) {
      final placeholder = entry.key;
      var markdownContent = entry.value;

      // 预处理 Discourse 图片格式（grid 内也可能包含 ![alt|WxH](url)）
      markdownContent = _processDiscourseImages(markdownContent);

      // 将 grid 内的 markdown 图片转成 HTML
      var gridHtml = md.markdownToHtml(
        markdownContent,
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
      
      // 移除 markdown 生成的 <p> 标签包裹，只保留 <img> 标签
      gridHtml = gridHtml.replaceAll(RegExp(r'</?p>'), '');
      
      // 用 d-image-grid div 包裹
      final replacement = '<div class="d-image-grid">$gridHtml</div>';
      
      // 替换占位符（可能被 <p> 包裹了）
      result = result.replaceAll('<p>$placeholder</p>', replacement);
      result = result.replaceAll(placeholder, replacement);
    }
    
    return result;
  }
  
  /// 预处理 [quote="username, post:N, topic:T"]...[/quote] 标记
  /// 将其替换为占位符，避免被 markdown 解析器干扰
  String _processQuoteBlocks(String text, Map<String, String> quoteBlocks) {
    final quoteRegex = RegExp(
      r'\[quote(?:="([^"]*)")?\](.*?)\[/quote\]',
      multiLine: true,
      dotAll: true,
    );

    int index = 0;
    return text.replaceAllMapped(quoteRegex, (match) {
      final attrs = match.group(1) ?? '';
      final content = match.group(2) ?? '';
      final placeholder = '<!--QUOTE_PLACEHOLDER_$index-->';
      quoteBlocks[placeholder] = '$attrs\n$content';
      index++;
      return placeholder;
    });
  }

  /// 后处理：将 quote 占位符替换为 aside.quote HTML
  String _restoreQuoteBlocks(String html, Map<String, String> quoteBlocks) {
    var result = html;

    for (final entry in quoteBlocks.entries) {
      final placeholder = entry.key;
      final raw = entry.value;
      final firstNewline = raw.indexOf('\n');
      final attrs = firstNewline >= 0 ? raw.substring(0, firstNewline) : '';
      final markdownContent = firstNewline >= 0 ? raw.substring(firstNewline + 1) : raw;

      // 解析属性
      String? username;
      String? post;
      String? topic;
      if (attrs.isNotEmpty) {
        // 格式: "username, post:N, topic:T"
        final parts = attrs.split(',').map((s) => s.trim()).toList();
        if (parts.isNotEmpty) username = parts[0];
        for (final part in parts.skip(1)) {
          if (part.startsWith('post:')) {
            post = part.substring(5);
          } else if (part.startsWith('topic:')) {
            topic = part.substring(6);
          }
        }
      }

      // 将引用内的 markdown 转成 HTML
      final quoteHtml = md.markdownToHtml(
        markdownContent.trim(),
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );

      // 构建 aside.quote HTML（与 Discourse 的格式一致）
      final dataAttrs = StringBuffer();
      if (username != null) dataAttrs.write(' data-username="$username"');
      if (post != null) dataAttrs.write(' data-post="$post"');
      if (topic != null) dataAttrs.write(' data-topic="$topic"');

      final replacement = '<aside class="quote"$dataAttrs>'
          '<blockquote>$quoteHtml</blockquote>'
          '</aside>';

      result = result.replaceAll('<p>$placeholder</p>', replacement);
      result = result.replaceAll(placeholder, replacement);
    }

    return result;
  }

  /// 将 @用户名 转换为 HTML 链接
  /// 匹配规则：@ 后面跟字母、数字、下划线、连字符
  String _processMentions(String text) {
    // 匹配 @用户名，但不匹配邮箱中的 @
    // 要求 @ 前面是空白/开头，后面是合法的用户名字符
    final mentionRegex = RegExp(r'(?<=^|\s)@([\w_-]+)(?=\s|$|[,.!?;:]|\))', multiLine: true);
    
    return text.replaceAllMapped(mentionRegex, (match) {
      final username = match.group(1)!;
      // 生成与 Discourse 一致的 mention 链接格式
      return '<a class="mention" href="${AppConstants.baseUrl}/u/$username">@$username</a>';
    });
  }
}
