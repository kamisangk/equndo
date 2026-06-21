/// Cookie 值编解码工具
/// Dart 的 io.Cookie 严格遵循 RFC 6265，禁止值中包含双引号、逗号等字符，
/// 但浏览器允许这些字符（如 g_state 的 JSON 值）。
/// 对不合规的值进行 URL 编码后加前缀存储，在所有出口处解码还原。
class CookieValueCodec {
  static const prefix = '~enc~';

  /// 编码不合规的 cookie 值
  static String encode(String value) => '$prefix${Uri.encodeComponent(value)}';

  /// 解码还原浏览器原始值；未编码的值原样返回
  static String decode(String value) {
    if (value.startsWith(prefix)) {
      return Uri.decodeComponent(value.substring(prefix.length));
    }
    return value;
  }
}
