/// 请求调度器的全局配置
///
/// 用户可通过「网络设置 → 限流设置」调整。
/// [RequestSchedulerInterceptor] 在每次请求时动态读取这些值。
class RequestSchedulerConfig {
  RequestSchedulerConfig._();

  /// 最大并发请求数（默认 3）
  static int maxConcurrent = 3;

  /// 滑动窗口内最大请求数（默认 6）
  static int maxPerWindow = 6;

  /// 滑动窗口时长，单位秒（默认 3）
  static int windowSeconds = 3;
}
