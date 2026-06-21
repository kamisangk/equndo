import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as http;
import '../constants.dart';
import 'network/discourse_dio.dart';

/// 包装 Dio 的 http.BaseClient 实现,给 flutter_cache_manager / image 下载用。
///
/// **双 dio 策略**(按 request URL host 选)
/// - **主域** (`linux.do` 及其子域):用 `_mainDomainDio`,带 cookie。
///   原因:`/uploads/secure-uploads/*` 私密图、user_avatar 在某些配置下需要
///   session cookie 才能访问。关掉 cookie 会让这些图 403。
///   但仍关掉 CfChallenge / Retry(图片自动 CF 验证 / 重试意义不大)。
///
/// - **第三方 CDN** (`s.pwsh.us.kg` / `cdn.ldstatic.com` / 其它):用 `_cdnDio`,
///   **完全不带 cookie**。CDN 根本不读 cookie header,带过去也无效;反而每张
///   图都触发 cookie jar 磁盘读写,30 张同屏 = 60 次磁盘 IO + cookie jar 锁
///   争用,这是"PNG 等半天"的根因。
class DioHttpClient extends http.BaseClient {
  static DioHttpClient? _instance;

  final dio.Dio _mainDomainDio;
  final dio.Dio _cdnDio;

  factory DioHttpClient() {
    _instance ??= DioHttpClient._internal();
    return _instance!;
  }

  DioHttpClient._internal()
      : _mainDomainDio = DiscourseDio.create(
          defaultHeaders: _imageHeaders,
          maxConcurrent: null,
          enableCookies: true, // 主域需要 cookie 走 secure-uploads
          enableCfChallenge: false,
          enableRetry: false,
          enableNetworkLog: false, // 几百张图都 log 占主线程
        ),
        _cdnDio = DiscourseDio.create(
          defaultHeaders: _imageHeaders,
          maxConcurrent: null,
          enableCookies: false, // CDN 完全不需要 cookie
          enableCfChallenge: false,
          enableRetry: false,
          enableNetworkLog: false,
        );

  static const Map<String, String> _imageHeaders = {
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// 全局图片下载并发上限。
  ///
  /// flutter_cache_manager 的 WebHelper 虽然每个 manager 限 10 并发,但
  /// 内容 / emoji / sticker / 外部 4 个 manager 共享同一条网络:emoji 与
  /// sticker 面板同时 keep-alive、再叠加贴内图片时,瞬时 30+ 并发会造成
  /// TLS 握手风暴、带宽互相挤占和 CDN 限流(429→裂图)。这里在 Dio 层做
  /// 全局兜底。
  ///
  /// 实现上 [send] 会把 body **完整读进内存后**才返回并在 finally 释放槽:
  /// - 并发槽覆盖整个 body 传输阶段,限流不是只限"拿到响应头";
  /// - WebHelper 对非 200/304 响应直接 throw、从不消费 body 流,如果释放
  ///   时机挂在"调用方读完流"上,每个失败响应都会泄漏一个槽,8 次 404/429
  ///   之后全 app 图片下载死锁。读完再返回让释放变成确定性的。
  /// 经此 client 的都是图片/小文件(cache manager 专用),8 并发 × 几 MB
  /// 的瞬时内存可控;进度事件本来就没有 UI 在消费,无损失。
  static final _Semaphore _downloadSemaphore = _Semaphore(8);

  /// 提取 [AppConstants.baseUrl] 的 host(例如 `linux.do`),用于判断主域。
  /// 注意是 host 比对而不是 URL prefix 比对 —— 子域(`auth.linux.do` 等)
  /// 也算主域,会走带 cookie 的 dio。
  static final String _mainHost = Uri.parse(AppConstants.baseUrl).host;

  bool _isMainDomain(Uri url) {
    final host = url.host;
    if (host.isEmpty) return false;
    // 主域精确匹配 或 是主域的子域(*.linux.do)
    return host == _mainHost || host.endsWith('.$_mainHost');
  }

  dio.Dio _selectDio(Uri url) =>
      _isMainDomain(url) ? _mainDomainDio : _cdnDio;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _downloadSemaphore.acquire();
    try {
      // 转换 headers
      final headers = <String, dynamic>{};
      request.headers.forEach((key, value) {
        headers[key] = value;
      });

      // 获取请求体
      Uint8List? bodyBytes;
      if (request is http.Request && request.bodyBytes.isNotEmpty) {
        bodyBytes = request.bodyBytes;
      } else if (request is http.MultipartRequest) {
        // MultipartRequest 需要特殊处理
        final stream = request.finalize();
        final bytes = await stream.toBytes();
        bodyBytes = Uint8List.fromList(bytes);
      }

      // 按 host 选 dio:主域用 _mainDomainDio(带 cookie),CDN 用 _cdnDio(lean)
      final response = await _selectDio(request.url).request<dio.ResponseBody>(
        request.url.toString(),
        options: dio.Options(
          method: request.method,
          headers: headers,
          responseType: dio.ResponseType.stream,
          // 接受所有状态码，让调用方处理
          validateStatus: (status) => true,
        ),
        data: bodyBytes != null ? Stream.fromIterable([bodyBytes]) : null,
      );

      // 转换响应 headers
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      // 在并发槽内读完整个 body(见 _downloadSemaphore 注释)
      final builder = BytesBuilder(copy: false);
      final responseBody = response.data;
      if (responseBody != null) {
        await for (final chunk in responseBody.stream) {
          builder.add(chunk);
        }
      }
      final bodyData = builder.takeBytes();

      return http.StreamedResponse(
        Stream.value(bodyData),
        response.statusCode ?? 200,
        headers: responseHeaders,
        // 用实际字节数而不是 content-length header:gzip 解压后两者可能不一致
        contentLength: bodyData.length,
        request: request,
        reasonPhrase: response.statusMessage,
      );
    } on dio.DioException catch (e) {
      // 将 DioException 转换为 http 包可以理解的异常
      if (e.type == dio.DioExceptionType.connectionTimeout ||
          e.type == dio.DioExceptionType.receiveTimeout) {
        throw http.ClientException('Request timeout: ${e.message}', request.url);
      }
      throw http.ClientException('Dio error: ${e.message}', request.url);
    } finally {
      _downloadSemaphore.release();
    }
  }

  @override
  void close() {
    // 不关闭共享的 Dio 实例
  }
}

/// 简单异步信号量,限制全局图片下载并发。
class _Semaphore {
  _Semaphore(this.maxCount);

  final int maxCount;
  int _current = 0;
  final _queue = <Completer<void>>[];

  Future<void> acquire() {
    if (_current < maxCount) {
      _current++;
      return Future.value();
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _current--;
    }
  }
}
