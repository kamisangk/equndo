import 'package:flutter/foundation.dart';

import '../l10n/s.dart';
import 'log/log_writer.dart';
import 'toast_service.dart';

/// 全局错误处理器
class AppErrorHandler {
  AppErrorHandler._();

  /// 处理非网络层的意外异常
  ///
  /// DioException 由 ErrorInterceptor 统一处理（toast + 拦截），
  /// 此方法用于捕获其余程序异常（解析错误、类型转换、未知响应格式等），
  /// 显示通用 toast 并写入本地日志。
  static void handleUnexpected(Object error, StackTrace stackTrace) {
    debugPrint('[AppErrorHandler] 意外异常: $error\n$stackTrace');

    // 尝试提取有意义的错误信息，避免总是显示通用提示
    String? errorMessage;
    if (error is Exception) {
      final str = error.toString();
      // Exception.toString() 格式为 "Exception: 具体信息"
      const prefix = 'Exception: ';
      if (str.startsWith(prefix) && str.length > prefix.length) {
        errorMessage = str.substring(prefix.length);
      }
    }

    ToastService.showError(errorMessage ?? S.current.toast_operationFailedRetry);
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'error',
      'type': 'unexpected',
      'error': error.toString(),
      'errorType': error.runtimeType.toString(),
      'stackTrace': stackTrace.toString(),
    });
  }
}
