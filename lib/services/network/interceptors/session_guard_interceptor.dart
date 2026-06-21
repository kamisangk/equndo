import 'package:dio/dio.dart';

import '../../auth_session.dart';

/// 会话代守卫拦截器
/// - onRequest: 将当前 generation 戳入请求 extra + 合并 CancelToken
/// - onResponse: 检查 generation 是否仍有效，过期则丢弃
/// - onError: 同上
class SessionGuardInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final session = AuthSession();
    options.extra['_sessionGeneration'] = session.generation;

    // 合并 CancelToken：如果请求自带 cancelToken，用 _MergedCancelToken
    // 否则直接使用 session 的 cancelToken
    final existing = options.cancelToken;
    if (existing != null && !existing.isCancelled) {
      final merged = _MergedCancelToken(existing, session.cancelToken);
      merged.requestOptions = options;
      options.cancelToken = merged;
    } else {
      options.cancelToken = session.cancelToken;
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final gen = response.requestOptions.extra['_sessionGeneration'] as int?;
    if (gen != null && !AuthSession().isValid(gen)) {
      // 丢弃过期会话的响应
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          type: DioExceptionType.cancel,
          error: '会话已过期 (gen=$gen, current=${AuthSession().generation})',
        ),
        true,
      );
      return;
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 过期会话的错误转为 cancel 类型，但仍需通过 next 传播，
    // 确保后续拦截器（如 RequestSchedulerInterceptor）能正常释放资源
    final gen = err.requestOptions.extra['_sessionGeneration'] as int?;
    if (gen != null && !AuthSession().isValid(gen)) {
      handler.next(
        DioException(
          requestOptions: err.requestOptions,
          type: DioExceptionType.cancel,
          error: '会话已过期 (gen=$gen)',
        ),
      );
      return;
    }
    handler.next(err);
  }
}

/// 合并两个 CancelToken：任一取消则整体取消
class _MergedCancelToken extends CancelToken {
  _MergedCancelToken(CancelToken a, CancelToken b) {
    void onCancel(CancelToken source) {
      if (!isCancelled) {
        cancel(source.cancelError?.error?.toString());
      }
    }
    a.whenCancel.then((_) => onCancel(a));
    b.whenCancel.then((_) => onCancel(b));
  }
}
