import 'package:flutter/foundation.dart';
import 'html_chunk.dart';
import 'html_chunker.dart';

/// HTML 分块缓存服务
///
/// 提供后台预解析和缓存功能，减少 UI 线程阻塞
class HtmlChunkCache {
  static final HtmlChunkCache _instance = HtmlChunkCache._();
  static HtmlChunkCache get instance => _instance;

  HtmlChunkCache._();

  /// LRU 缓存，key 为 (hashCode, length) 复合键，避免单一 hashCode 碰撞
  final Map<(int, int), List<HtmlChunk>> _cache = {};

  /// 缓存最大条目数
  static const int _maxCacheSize = 100;

  /// 正在解析中的任务
  final Set<(int, int)> _pendingKeys = {};

  /// 生成复合缓存 key
  static (int, int) _keyOf(String html) => (html.hashCode, html.length);

  /// 获取缓存的分块结果
  List<HtmlChunk>? get(String html) {
    final key = _keyOf(html);
    final result = _cache[key];
    if (result != null) {
      // LRU: 移到末尾
      _cache.remove(key);
      _cache[key] = result;
    }
    return result;
  }

  /// 同步解析并缓存（用于短内容）
  List<HtmlChunk> parseSync(String html) {
    final cached = get(html);
    if (cached != null) return cached;

    final chunks = HtmlChunker.chunk(html);
    _put(_keyOf(html), chunks);
    return chunks;
  }

  /// 异步解析并缓存（用于长内容，在后台 isolate 执行）
  Future<List<HtmlChunk>> parseAsync(String html) async {
    final key = _keyOf(html);

    // 检查缓存
    final cached = get(html);
    if (cached != null) return cached;

    // 避免重复解析
    if (_pendingKeys.contains(key)) {
      // 等待解析完成
      while (_pendingKeys.contains(key)) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      return get(html) ?? HtmlChunker.chunk(html);
    }

    _pendingKeys.add(key);

    try {
      // 在后台 isolate 解析
      final chunks = await compute(_parseInIsolate, html);
      _put(key, chunks);
      return chunks;
    } finally {
      _pendingKeys.remove(key);
    }
  }

  /// 预加载：异步解析但不等待结果
  void preload(String html) {
    final key = _keyOf(html);
    if (_cache.containsKey(key) || _pendingKeys.contains(key)) {
      return; // 已缓存或正在解析
    }

    // 短内容直接同步解析
    if (html.length < 5000) {
      parseSync(html);
      return;
    }

    // 长内容后台解析
    parseAsync(html);
  }

  /// 批量预加载
  void preloadAll(List<String> htmlList) {
    for (final html in htmlList) {
      preload(html);
    }
  }

  /// 检查是否已缓存
  bool isCached(String html) {
    return _cache.containsKey(_keyOf(html));
  }

  /// 清除缓存
  void clear() {
    _cache.clear();
    _pendingKeys.clear();
  }

  void _put((int, int) key, List<HtmlChunk> chunks) {
    // LRU 淘汰
    while (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = chunks;
  }
}

/// 在 isolate 中执行的解析函数
List<HtmlChunk> _parseInIsolate(String html) {
  return HtmlChunker.chunk(html);
}
