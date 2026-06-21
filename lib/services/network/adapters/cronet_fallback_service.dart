import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cronet 降级管理服务
/// 负责管理 Cronet 降级状态和原因
class CronetFallbackService extends ChangeNotifier {
  CronetFallbackService._();
  static final instance = CronetFallbackService._();

  // SharedPreferences 键
  static const _hasFallenBackKey = 'cronet_has_fallen_back';
  static const _fallbackReasonKey = 'cronet_fallback_reason';
  static const _forceFallbackKey = 'cronet_force_fallback';

  SharedPreferences? _prefs;
  bool _isInitialized = false;

  // 运行时状态
  bool _hasFallenBack = false;
  String? _fallbackReason;
  bool _forceFallback = false;

  /// 初始化服务
  Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
    _isInitialized = true;

    // 加载手动强制降级状态（用户主动选择，需要保留）
    _forceFallback = prefs.getBool(_forceFallbackKey) ?? false;

    // 冷启动时自动清除上次的自动降级状态，让 Cronet 每次启动都有新机会。
    // 如果 Cronet 确实有问题，本次会话内会再次触发降级并快速切换。
    final previouslyFallenBack = prefs.getBool(_hasFallenBackKey) ?? false;
    if (previouslyFallenBack) {
      debugPrint(
        '[Cronet] Clearing previous auto-fallback on cold start '
        '(reason: ${prefs.getString(_fallbackReasonKey)})',
      );
      await prefs.remove(_hasFallenBackKey);
      await prefs.remove(_fallbackReasonKey);
    }
    _hasFallenBack = false;
    _fallbackReason = null;

    if (_forceFallback) {
      debugPrint('[Cronet] Force fallback is enabled (user preference)');
    }
  }

  /// 是否已降级
  bool get hasFallenBack => _hasFallenBack || _forceFallback;

  /// 是否强制降级
  bool get forceFallback => _forceFallback;

  /// 降级原因
  String? get fallbackReason => _fallbackReason;

  /// 触发降级
  Future<void> triggerFallback(String reason) async {
    if (_hasFallenBack) {
      debugPrint('[Cronet] Already fallen back, ignoring');
      return;
    }

    _hasFallenBack = true;
    _fallbackReason = reason;

    // 持久化状态
    if (_isInitialized && _prefs != null) {
      await _prefs!.setBool(_hasFallenBackKey, true);
      await _prefs!.setString(_fallbackReasonKey, reason);
    }

    debugPrint('[Cronet] Fallback triggered: $reason');
    notifyListeners(); // 通知监听者
  }

  /// 设置强制降级
  Future<void> setForceFallback(bool value) async {
    _forceFallback = value;

    if (_isInitialized && _prefs != null) {
      await _prefs!.setBool(_forceFallbackKey, value);
    }

    debugPrint('[Cronet] Force fallback set to: $value');
    notifyListeners(); // 通知监听者
  }

  /// 重置降级状态
  Future<void> reset() async {
    _hasFallenBack = false;
    _fallbackReason = null;

    if (_isInitialized && _prefs != null) {
      await _prefs!.remove(_hasFallenBackKey);
      await _prefs!.remove(_fallbackReasonKey);
    }

    debugPrint('[Cronet] Fallback state reset');
    notifyListeners(); // 通知监听者
  }

  /// 模拟 Cronet 错误（用于测试）
  Future<void> simulateCronetError() async {
    const simulatedError = '''
[TEST] Simulated Cronet Error
org.chromium.net.cronet.CronetException: All available Cronet providers are disabled.
    at org.chromium.net.impl.CronetUrlRequestContext.createRequest(CronetUrlRequestContext.java:123)
    at io.flutter.plugins.cronet_http.CronetClient.send(CronetClient.java:456)

This is a simulated error for testing the fallback mechanism.
''';
    await triggerFallback(simulatedError);
    debugPrint('[Cronet] Simulated error triggered for testing');
  }

  /// 判断错误是否是 Cronet 特有的
  /// 基于实际错误案例设计的精准识别逻辑
  static bool isCronetError(dynamic error) {
    if (error == null) return false;

    final errorStr = error.toString();
    final errorStrLower = errorStr.toLowerCase();

    // 0. 排除生命周期时序错误（瞬态错误，不代表 Cronet 本身有问题）
    // 例如切换 adapter 时 close 旧 delegate，若有请求在飞则抛
    // "Cannot shutdown with running requests"
    if (_isTransientLifecycleError(errorStrLower)) {
      debugPrint('[Cronet] Ignoring transient lifecycle error');
      return false;
    }

    // 1. 检查堆栈信息中是否包含 Cronet 相关的类
    // 这是最可靠的判断方式
    final cronetStackTracePatterns = [
      'org.chromium.net.cronet', // Cronet 核心类
      'cronetengine', // CronetEngine 相关
      'cronetexception', // Cronet 异常
      'cronetprovider', // Cronet Provider
      'cronet_http', // Dart 包名
    ];

    for (final pattern in cronetStackTracePatterns) {
      if (errorStrLower.contains(pattern)) {
        debugPrint('[Cronet] Detected Cronet error by stack trace: $pattern');
        return true;
      }
    }

    // 2. 检查特定的 Cronet 错误消息
    // 基于实际遇到的错误
    final cronetErrorMessages = [
      'all available cronet providers are disabled',
      'cronet provider',
      'cronetengine',
      'failed to load cronet',
      'cronet initialization failed',
    ];

    for (final message in cronetErrorMessages) {
      if (errorStrLower.contains(message)) {
        debugPrint('[Cronet] Detected Cronet error by message: $message');
        return true;
      }
    }

    // 3. 检查 JNI 调用相关的 Cronet 错误
    // 通过 JNI 调用 Java 代码时的错误特征
    if (errorStrLower.contains('exception in java code called through jni') &&
        errorStrLower.contains('chromium')) {
      debugPrint('[Cronet] Detected Cronet error via JNI');
      return true;
    }

    return false;
  }

  /// 判断是否为瞬态生命周期错误
  /// 这类错误是 CronetEngine 关闭时序问题，不代表 Cronet 功能异常
  static bool _isTransientLifecycleError(String errorStrLower) {
    const transientPatterns = [
      'cannot shutdown with running requests', // close() 时还有请求在飞
      'engine is shut down', // 引擎已关闭后的请求
      'request already started', // 重复启动请求
    ];
    for (final pattern in transientPatterns) {
      if (errorStrLower.contains(pattern)) return true;
    }
    return false;
  }
}
