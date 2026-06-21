import 'package:flutter/foundation.dart';

import 'preloaded_data_service.dart';
import '../utils/url_helper.dart';
import '../utils/emoji_shortcodes.dart';

/// Emoji URL 解析器
///
/// 与 Discourse 官方逻辑一致：
/// - 自定义 emoji（如 bili_114）：从预加载数据 `customEmoji` 注册，URL 由服务端提供
/// - 标准 emoji（如 heart、smile）：URL 确定性拼接 `/images/emoji/twitter/{name}.png`
/// - 不依赖 `/emojis.json` API（该接口仅供 emoji picker 使用）
class EmojiHandler {
  static final EmojiHandler _instance = EmojiHandler._internal();
  factory EmojiHandler() => _instance;
  EmojiHandler._internal();

  /// 自定义 emoji 名称 -> URL 映射（对应 Discourse 的 extendedEmojiMap）
  Map<String, String>? _customEmojiMap;

  /// 从预加载数据注册自定义 emoji
  ///
  /// 必须在 [PreloadedDataService().ensureLoaded()] 之后调用。
  void init() {
    if (_customEmojiMap != null) return;

    _customEmojiMap = {};

    try {
      final customEmojis = PreloadedDataService().customEmoji;
      if (customEmojis != null) {
        for (final emoji in customEmojis) {
          final name = emoji['name'] as String?;
          final url = emoji['url'] as String?;
          if (name != null && url != null) {
            _customEmojiMap![name] = url;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load custom emojis: $e');
    }
  }

  /// 将文本中的 :emoji: 替换为 HTML img 标签
  String replaceEmojis(String text) {
    return text.replaceAllMapped(emojiShortcodeRegex, (match) {
      final name = normalizeEmojiShortcodeName(match.group(1)!);
      final fullUrl = getEmojiUrl(name);
      return '<img src="$fullUrl" alt=":$name:" class="emoji" title=":$name:">';
    });
  }

  /// 获取 emoji 的完整 URL
  ///
  /// 优先查找自定义 emoji（有服务端提供的真实 URL），
  /// 未找到则使用标准 emoji 的确定性路径。
  String getEmojiUrl(String name) {
    final normalized = normalizeEmojiShortcodeName(name);

    // 优先查自定义 emoji（如 bili_114、tsai 等）
    final customUrl = _customEmojiMap?[normalized];
    if (customUrl != null) {
      return UrlHelper.resolveUrlWithCdn(customUrl);
    }

    final toneMatch = RegExp(r'^([^\s:]+):t([1-6])$').firstMatch(normalized);
    if (toneMatch != null) {
      final base = toneMatch.group(1)!;
      final tone = toneMatch.group(2)!;
      return UrlHelper.resolveUrlWithCdn(
        '/images/emoji/twitter/$base/t$tone.png?v=12',
      );
    }

    // 标准 emoji，URL 确定性拼接（与 Discourse buildEmojiUrl 一致）
    return UrlHelper.resolveUrlWithCdn(
      '/images/emoji/twitter/$normalized.png?v=12',
    );
  }
}
