import 'dart:math';

/// 客户端 ID 生成器
/// 生成全局唯一的客户端标识符，用于 MessageBus、追踪等场景
class ClientIdGenerator {
  static final Random _random = Random();

  /// 生成 32 位随机客户端 ID
  /// 字符集：a-z0-9（36个字符）
  /// 熵空间：36^32 ≈ 6.3×10^49
  static String generate() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(32, (_) => chars[_random.nextInt(chars.length)]).join();
  }
}
