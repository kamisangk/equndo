/// HTML 块类型枚举
enum HtmlChunkType {
  paragraph, // 段落（可能包含多个连续的 <p>、文本）
  codeBlock, // 代码块 <pre><code>
  table, // 表格 <table>
  quoteCard, // 引用卡片 <aside class="quote">
  onebox, // 链接卡片 <aside class="onebox">
  blockquote, // 普通引用 <blockquote>
  spoiler, // 折叠内容 .spoiler/.spoiled
  heading, // 标题 <h1>-<h6>
  list, // 列表 <ul>/<ol>
  divider, // 分割线 <hr>
  details, // 折叠详情 <details>
}

/// HTML 块数据
class HtmlChunk {
  final String html;
  final HtmlChunkType type;
  final int index;

  const HtmlChunk({
    required this.html,
    required this.type,
    required this.index,
  });
}
