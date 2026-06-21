import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'html_chunk.dart';

/// HTML 分割器
class HtmlChunker {
  /// 块级元素标签（需要独立成块）
  static const _blockTags = {
    'table',
    'pre',
    'aside',
    'blockquote',
    'details',
    'hr',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'dl',
    'figure',
    'video',
    'audio',
  };

  /// 需要特殊处理的类名
  static const _specialClasses = {'spoiler', 'spoiled'};

  /// div 元素中需要独立成块的类名
  static const _blockDivClasses = {'md-table'};

  /// 最大段落合并字符数（增大以减少块数量，降低 HtmlWidget 实例开销）
  static const _maxMergeLength = 2000;

  /// 最大段落合并数
  static const _maxMergeParagraphs = 8;

  /// 分割 HTML 为块列表
  static List<HtmlChunk> chunk(String html) {
    if (html.isEmpty) return [];

    final document = html_parser.parseFragment(html);
    final chunks = <HtmlChunk>[];
    final pendingNodes = <dom.Node>[];
    int pendingLength = 0;

    void flushPending() {
      if (pendingNodes.isEmpty) return;

      final buffer = StringBuffer();
      for (final node in pendingNodes) {
        if (node is dom.Element) {
          buffer.write(node.outerHtml);
        } else if (node is dom.Text) {
          buffer.write(node.text);
        }
      }

      final content = buffer.toString().trim();
      if (content.isNotEmpty) {
        chunks.add(HtmlChunk(
          html: content,
          type: HtmlChunkType.paragraph,
          index: chunks.length,
        ));
      }

      pendingNodes.clear();
      pendingLength = 0;
    }

    for (final node in document.nodes) {
      if (node is dom.Element) {
        // 检查是否是块级元素
        if (_isBlockElement(node)) {
          flushPending();
          chunks.add(HtmlChunk(
            html: node.outerHtml,
            type: _getChunkType(node),
            index: chunks.length,
          ));
        } else {
          // 内联元素或短段落，累积
          final nodeLength = node.outerHtml.length;
          pendingNodes.add(node);
          pendingLength += nodeLength;

          // 达到合并阈值时强制分块
          if (pendingLength > _maxMergeLength ||
              pendingNodes.length >= _maxMergeParagraphs) {
            flushPending();
          }
        }
      } else if (node is dom.Text) {
        final text = node.text;
        if (text.trim().isNotEmpty) {
          pendingNodes.add(node);
          pendingLength += text.length;
        }
      }
    }

    flushPending();

    // 后处理：将 chunk 开头的孤立 <br> 替换为 lb-spacer 占位标记
    // 分块切割可能把 lightbox 之间的 <br> 切到下一个 chunk 开头，
    // 预处理无法匹配到它（前面没有 </a></div>），需要在这里替换。
    for (int i = 1; i < chunks.length; i++) {
      final chunk = chunks[i];
      if (chunk.type == HtmlChunkType.paragraph &&
          chunk.html.startsWith('<br')) {
        final replaced = chunk.html.replaceFirst(
          RegExp(r'^<br\s*/?>'),
          '<div class="lb-spacer"></div>',
        );
        chunks[i] = HtmlChunk(
          html: replaced,
          type: chunk.type,
          index: chunk.index,
        );
      }
    }

    // 如果只有一个块，直接返回原 HTML（避免不必要的拆分）
    if (chunks.length == 1) {
      return [
        HtmlChunk(
          html: html,
          type: chunks.first.type,
          index: 0,
        )
      ];
    }

    return chunks;
  }

  static bool _isBlockElement(dom.Element element) {
    final tagName = element.localName?.toLowerCase() ?? '';

    // 标签名匹配
    if (_blockTags.contains(tagName)) return true;

    // div 元素检查特殊类名和块级类名
    if (tagName == 'div') {
      final classes = element.classes;
      if (classes.any((c) => _specialClasses.contains(c))) return true;
      if (classes.any((c) => _blockDivClasses.contains(c))) return true;
    }

    // span 元素检查特殊类名
    if (tagName == 'span') {
      final classes = element.classes;
      if (classes.any((c) => _specialClasses.contains(c))) return true;
    }

    return false;
  }

  static HtmlChunkType _getChunkType(dom.Element element) {
    final tagName = element.localName?.toLowerCase() ?? '';

    switch (tagName) {
      case 'table':
        return HtmlChunkType.table;
      case 'pre':
        return HtmlChunkType.codeBlock;
      case 'blockquote':
        return HtmlChunkType.blockquote;
      case 'details':
        return HtmlChunkType.details;
      case 'hr':
        return HtmlChunkType.divider;
      case 'ul':
      case 'ol':
      case 'dl':
        return HtmlChunkType.list;
      case 'aside':
        if (element.classes.contains('quote')) return HtmlChunkType.quoteCard;
        if (element.classes.contains('onebox')) return HtmlChunkType.onebox;
        return HtmlChunkType.paragraph;
      case 'div':
        if (element.classes.contains('md-table')) return HtmlChunkType.table;
        return HtmlChunkType.paragraph;
      default:
        if (tagName.startsWith('h') && tagName.length == 2) {
          return HtmlChunkType.heading;
        }
        if (element.classes.contains('spoiler') ||
            element.classes.contains('spoiled')) {
          return HtmlChunkType.spoiler;
        }
        return HtmlChunkType.paragraph;
    }
  }
}
