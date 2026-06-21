import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../adapters/cronet_fallback_service.dart';

/// Cronet 降级拦截器
/// 在请求失败时判断是否是 Cronet 导致的,如果是则自动降级并重试。
/// 降级后 _DynamicAdapter 会在下次请求时自动检测到 hasFallenBack 变化并切换适配器。
class CronetFallbackInterceptor extends Interceptor {
  CronetFallbackInterceptor(this._dio);

  final Dio _dio;
  bool _isRetrying = false;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 避免无限重试
    if (_isRetrying) {
      handler.next(err);
      return;
    }

    // 检查是否是 Cronet 错误
    final isCronetError = CronetFallbackService.isCronetError(err.error);

    if (!isCronetError) {
      handler.next(err);
      return;
    }

    // 确认是 Cronet 错误,触发降级
    debugPrint('[Cronet] Detected Cronet error: ${err.error}');

    final fallbackService = CronetFallbackService.instance;

    // 如果已经降级过了,不再重试
    if (fallbackService.hasFallenBack) {
      handler.next(err);
      return;
    }

    // 触发降级，_DynamicAdapter 会在重试请求时自动切换适配器
    await fallbackService.triggerFallback(err.error.toString());
    debugPrint('[Cronet] Fallback triggered, retrying request');

    // 重试请求
    _isRetrying = true;
    try {
      final retryOptions = err.requestOptions;
      retryOptions.headers.remove('cookie');
      retryOptions.headers.remove('Cookie');
      final response = await _dio.fetch(retryOptions);
      handler.resolve(response);
    } catch (e) {
      debugPrint('[Cronet] Retry failed: $e');
      handler.next(err);
    } finally {
      _isRetrying = false;
    }
  }
}
