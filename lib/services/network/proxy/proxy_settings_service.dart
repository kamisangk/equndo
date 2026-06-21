import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants.dart';
import '../../../l10n/s.dart';

enum UpstreamProxyProtocol {
  http('http', 'HTTP'),
  socks5('socks5', 'SOCKS5'),
  shadowsocks('shadowsocks', 'Shadowsocks');

  const UpstreamProxyProtocol(this.storageValue, this.displayName);

  final String storageValue;
  final String displayName;

  static UpstreamProxyProtocol fromStorage(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'socks':
      case 'socks5':
      case 'socks5h':
        return UpstreamProxyProtocol.socks5;
      case 'ss':
      case 'shadowsocks':
        return UpstreamProxyProtocol.shadowsocks;
      case 'http':
      default:
        return UpstreamProxyProtocol.http;
    }
  }
}

class ProxyTestResult {
  const ProxyTestResult({
    required this.success,
    required this.summary,
    required this.detail,
    required this.targetUrl,
    required this.testedAt,
    this.latency,
    this.statusCode,
  });

  final bool success;
  final String summary;
  final String detail;
  final String targetUrl;
  final DateTime testedAt;
  final Duration? latency;
  final int? statusCode;
}

/// 上游代理设置数据模型
class ProxySettings {
  const ProxySettings({
    this.enabled = false,
    this.protocol = UpstreamProxyProtocol.http,
    this.host = '',
    this.port = 0,
    this.username,
    this.password,
    this.cipher = '',
  });

  /// 是否启用上游代理
  final bool enabled;
  /// 上游代理协议
  final UpstreamProxyProtocol protocol;
  /// 上游代理服务器地址
  final String host;
  /// 上游代理服务器端口
  final int port;
  /// 用户名（可选）
  final String? username;
  /// 密码（可选）
  final String? password;
  /// Shadowsocks 加密算法
  final String cipher;

  /// 是否已填写服务器地址和端口
  bool get hasServer => host.isNotEmpty && port > 0;

  /// 代理是否有效配置
  bool get isValid {
    if (!enabled || host.isEmpty || port <= 0) {
      return false;
    }
    if (protocol == UpstreamProxyProtocol.shadowsocks) {
      return ProxySettingsService.validateShadowsocksSecret(
            cipher: cipher,
            secret: password,
          ) ==
          null;
    }
    return true;
  }

  bool get isShadowsocks => protocol == UpstreamProxyProtocol.shadowsocks;

  ProxySettings copyWith({
    bool? enabled,
    UpstreamProxyProtocol? protocol,
    String? host,
    int? port,
    String? username,
    String? password,
    String? cipher,
  }) {
    return ProxySettings(
      enabled: enabled ?? this.enabled,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      cipher: cipher ?? this.cipher,
    );
  }
}

/// 上游代理设置服务
class ProxySettingsService {
  ProxySettingsService._internal();

  static final ProxySettingsService instance = ProxySettingsService._internal();

  static const _enabledKey = 'http_proxy_enabled';
  static const _protocolKey = 'upstream_proxy_protocol';
  static const _hostKey = 'http_proxy_host';
  static const _portKey = 'http_proxy_port';
  static const _usernameKey = 'http_proxy_username';
  static const _passwordKey = 'http_proxy_password';
  static const _cipherKey = 'upstream_proxy_cipher';
  static const supportedShadowsocksCiphers = <String>[
    'aes-128-gcm',
    'aes-256-gcm',
    'chacha20-ietf-poly1305',
    '2022-blake3-aes-256-gcm',
  ];
  static const _shadowsocks2022KeyLengths = <String, int>{
    '2022-blake3-aes-256-gcm': 32,
  };

  final ValueNotifier<ProxySettings> notifier = ValueNotifier(
    const ProxySettings(),
  );
  final ValueNotifier<ProxyTestResult?> testResultNotifier =
      ValueNotifier<ProxyTestResult?>(null);
  final ValueNotifier<bool> isTesting = ValueNotifier(false);

  SharedPreferences? _prefs;
  int _version = 0;
  Future<ProxyTestResult>? _activeTest;

  /// 版本号，用于触发适配器重建
  int get version => _version;

  ProxySettings get current => notifier.value;

  Future<void> initialize(SharedPreferences prefs) async {
    if (_prefs != null) return;
    _prefs = prefs;

    final enabled = prefs.getBool(_enabledKey) ?? false;
    final protocol = UpstreamProxyProtocol.fromStorage(
      prefs.getString(_protocolKey),
    );
    final host = prefs.getString(_hostKey) ?? '';
    final port = prefs.getInt(_portKey) ?? 0;
    final username = prefs.getString(_usernameKey);
    final password = prefs.getString(_passwordKey);
    final cipher = prefs.getString(_cipherKey) ?? '';

    notifier.value = ProxySettings(
      enabled: enabled,
      protocol: protocol,
      host: host,
      port: port,
      username: username,
      password: password,
      cipher: cipher,
    );
  }

  /// 启用/禁用上游 HTTP 代理
  Future<void> setEnabled(bool enabled) async {
    final prefs = _prefs;
    if (prefs == null) return;

    notifier.value = notifier.value.copyWith(enabled: enabled);
    await prefs.setBool(_enabledKey, enabled);
    _touch();
  }

  /// 设置上游代理服务器地址、协议和端口
  Future<void> setServer({
    required UpstreamProxyProtocol protocol,
    required String host,
    required int port,
    String? username,
    String? password,
    String? cipher,
  }) async {
    final prefs = _prefs;
    if (prefs == null) return;

    notifier.value = ProxySettings(
      enabled: notifier.value.enabled,
      protocol: protocol,
      host: host,
      port: port,
      username: protocol == UpstreamProxyProtocol.shadowsocks ? null : username,
      password: password,
      cipher: protocol == UpstreamProxyProtocol.shadowsocks
          ? normalizeShadowsocksCipher(cipher)
          : '',
    );

    await prefs.setString(_protocolKey, protocol.storageValue);
    await prefs.setString(_hostKey, host);
    await prefs.setInt(_portKey, port);

    if (username != null && username.isNotEmpty) {
      await prefs.setString(_usernameKey, username);
    } else {
      await prefs.remove(_usernameKey);
    }

    if (password != null && password.isNotEmpty) {
      await prefs.setString(_passwordKey, password);
    } else {
      await prefs.remove(_passwordKey);
    }

    final normalizedCipher = protocol == UpstreamProxyProtocol.shadowsocks
        ? normalizeShadowsocksCipher(cipher)
        : '';
    if (normalizedCipher.isNotEmpty) {
      await prefs.setString(_cipherKey, normalizedCipher);
    } else {
      await prefs.remove(_cipherKey);
    }

    _resetTestResult();
    _touch();
  }

  Future<ProxyTestResult> testCurrentAvailability() {
    return testAvailability(current);
  }

  Future<ProxyTestResult> testAvailability(ProxySettings settings) {
    final inFlight = _activeTest;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _runAvailabilityTest(settings);
    _activeTest = future;
    isTesting.value = true;
    future.then((result) {
      testResultNotifier.value = result;
    }).whenComplete(() {
      if (identical(_activeTest, future)) {
        _activeTest = null;
      }
      isTesting.value = false;
    });
    return future;
  }

  void _resetTestResult() {
    testResultNotifier.value = null;
  }

  void _touch() {
    _version++;
    notifier.value = notifier.value.copyWith();
  }

  Future<ProxyTestResult> _runAvailabilityTest(ProxySettings settings) async {
    final targetUri = Uri.parse(AppConstants.baseUrl);
    final now = DateTime.now();
    if (!settings.hasServer) {
      return ProxyTestResult(
        success: false,
        summary: S.current.proxy_notConfigured,
        detail: S.current.proxy_fillAddressPort,
        targetUrl: targetUri.toString(),
        testedAt: now,
      );
    }
    if (settings.protocol == UpstreamProxyProtocol.shadowsocks) {
      final secretError = validateShadowsocksSecret(
        cipher: settings.cipher,
        secret: settings.password,
      );
      if (secretError != null) {
        return ProxyTestResult(
          success: false,
          summary: S.current.proxy_ssIncomplete,
          detail: secretError,
          targetUrl: targetUri.toString(),
          testedAt: now,
        );
      }
      return ProxyTestResult(
        success: true,
        summary: S.current.proxy_ssSaved,
        detail: S.current.proxy_ssSavedDetail,
        targetUrl: targetUri.toString(),
        testedAt: now,
      );
    }

    final timeout = const Duration(seconds: 8);
    final authorityPort = targetUri.hasPort
        ? targetUri.port
        : (targetUri.scheme == 'https' ? 443 : 80);
    final authority = '${targetUri.host}:$authorityPort';
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    SecureSocket? secureSocket;

    try {
      socket = await Socket.connect(
        settings.host,
        settings.port,
        timeout: timeout,
      );

      switch (settings.protocol) {
        case UpstreamProxyProtocol.http:
          await _establishHttpTunnel(
            socket,
            settings,
            authority: authority,
            timeout: timeout,
          );
          break;
        case UpstreamProxyProtocol.socks5:
          await _establishSocks5Tunnel(
            socket,
            settings,
            host: targetUri.host,
            port: authorityPort,
            timeout: timeout,
          );
          break;
        case UpstreamProxyProtocol.shadowsocks:
          break;
      }
      secureSocket = await SecureSocket.secure(
        socket,
        host: targetUri.host,
      ).timeout(timeout);

      final statusCode = await _requestAvailability(
        secureSocket,
        targetUri,
        timeout: timeout,
      );
      stopwatch.stop();

      return ProxyTestResult(
        success: true,
        summary: S.current.proxy_testSuccess,
        detail: '已通过 ${settings.protocol.displayName} 代理访问 ${targetUri.host}，HTTP $statusCode',
        targetUrl: targetUri.toString(),
        testedAt: DateTime.now(),
        latency: stopwatch.elapsed,
        statusCode: statusCode,
      );
    } on TimeoutException {
      stopwatch.stop();
      return ProxyTestResult(
        success: false,
        summary: S.current.proxy_testTimeout,
        detail: '连接或握手超过 ${timeout.inSeconds} 秒，未能完成 ${targetUri.host} 可用性验证',
        targetUrl: targetUri.toString(),
        testedAt: DateTime.now(),
        latency: stopwatch.elapsed,
      );
    } on TlsException catch (error) {
      stopwatch.stop();
      return ProxyTestResult(
        success: false,
        summary: S.current.proxy_testTlsFailed,
        detail: error.toString(),
        targetUrl: targetUri.toString(),
        testedAt: DateTime.now(),
        latency: stopwatch.elapsed,
      );
    } on HttpException catch (error) {
      stopwatch.stop();
      return ProxyTestResult(
        success: false,
        summary: S.current.proxy_testFailed,
        detail: error.message,
        targetUrl: targetUri.toString(),
        testedAt: DateTime.now(),
        latency: stopwatch.elapsed,
      );
    } on SocketException catch (error) {
      stopwatch.stop();
      return ProxyTestResult(
        success: false,
        summary: S.current.proxy_cannotConnect,
        detail: error.message,
        targetUrl: targetUri.toString(),
        testedAt: DateTime.now(),
        latency: stopwatch.elapsed,
      );
    } catch (error) {
      stopwatch.stop();
      return ProxyTestResult(
        success: false,
        summary: S.current.proxy_testFailed,
        detail: error.toString(),
        targetUrl: targetUri.toString(),
        testedAt: DateTime.now(),
        latency: stopwatch.elapsed,
      );
    } finally {
      try {
        secureSocket?.destroy();
      } catch (_) {}
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  Future<void> _establishHttpTunnel(
    Socket socket,
    ProxySettings settings, {
    required String authority,
    required Duration timeout,
  }) async {
    final request = StringBuffer()
      ..write('CONNECT $authority HTTP/1.1\r\n')
      ..write('Host: $authority\r\n')
      ..write('Proxy-Connection: Keep-Alive\r\n');

    final username = settings.username?.trim() ?? '';
    final password = settings.password?.trim() ?? '';
    if (username.isNotEmpty || password.isNotEmpty) {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      request.write('Proxy-Authorization: Basic $credentials\r\n');
    }
    request.write('\r\n');

    socket.add(utf8.encode(request.toString()));
    await socket.flush();

    final reader = _SocketByteReader(socket);
    try {
      final responseBytes = await reader.readUntilHeaderEnd(timeout);
      final statusLine = ascii
          .decode(responseBytes, allowInvalid: true)
          .split('\r\n')
          .first
          .trim();
      final parts = statusLine.split(RegExp(r'\s+'));
      final statusCode = parts.length > 1 ? parts[1] : null;
      final code = int.tryParse(statusCode ?? '');

      if (code == 200) {
        return;
      }
      if (code == 407) {
        throw HttpException(S.current.proxy_httpAuthFailed);
      }
      throw HttpException('HTTP 代理 CONNECT 失败：$statusLine');
    } finally {
      reader.pause();
    }
  }

  Future<void> _establishSocks5Tunnel(
    Socket socket,
    ProxySettings settings, {
    required String host,
    required int port,
    required Duration timeout,
  }) async {
    final reader = _SocketByteReader(socket);
    try {
      final username = settings.username?.trim() ?? '';
      final password = settings.password?.trim() ?? '';
      final needsAuth = username.isNotEmpty || password.isNotEmpty;

      socket.add([
        0x05,
        needsAuth ? 0x02 : 0x01,
        0x00,
        if (needsAuth) 0x02,
      ]);
      await socket.flush();

      final greet = await reader.readExact(2, timeout);
      if (greet[0] != 0x05) {
        throw HttpException(S.current.proxy_socks5InvalidVersion);
      }
      if (greet[1] == 0xFF) {
        throw HttpException(S.current.proxy_socks5AuthRejected);
      }
      if (greet[1] == 0x02) {
        final usernameBytes = utf8.encode(username);
        final passwordBytes = utf8.encode(password);
        if (usernameBytes.length > 255 || passwordBytes.length > 255) {
          throw HttpException(S.current.proxy_socks5CredentialsTooLong);
        }
        socket.add([
          0x01,
          usernameBytes.length,
          ...usernameBytes,
          passwordBytes.length,
          ...passwordBytes,
        ]);
        await socket.flush();
        final authReply = await reader.readExact(2, timeout);
        if (authReply[1] != 0x00) {
          throw HttpException(S.current.proxy_socks5AuthFailed);
        }
      } else if (greet[1] != 0x00) {
        throw HttpException('${S.current.proxy_socks5AuthRejected}: 0x${greet[1].toRadixString(16)}');
      }

      final hostBytes = utf8.encode(host);
      if (hostBytes.length > 255) {
        throw HttpException(S.current.proxy_socks5HostnameTooLong);
      }
      socket.add([
        0x05,
        0x01,
        0x00,
        0x03,
        hostBytes.length,
        ...hostBytes,
        (port >> 8) & 0xFF,
        port & 0xFF,
      ]);
      await socket.flush();

      final replyHead = await reader.readExact(4, timeout);
      if (replyHead[0] != 0x05) {
        throw HttpException(S.current.proxy_socks5ConnectInvalidVersion);
      }
      if (replyHead[1] != 0x00) {
        throw HttpException(
          'SOCKS5 CONNECT 失败：${_describeSocks5Reply(replyHead[1])}',
        );
      }

      final atyp = replyHead[3];
      late final int remainLength;
      if (atyp == 0x01) {
        remainLength = 4 + 2;
      } else if (atyp == 0x04) {
        remainLength = 16 + 2;
      } else if (atyp == 0x03) {
        final hostLength = (await reader.readExact(1, timeout))[0];
        remainLength = hostLength + 2;
      } else {
        throw HttpException('${S.current.proxy_socks5AddrTypeNotSupported}: 0x${atyp.toRadixString(16)}');
      }
      await reader.readExact(remainLength, timeout);
    } finally {
      reader.pause();
    }
  }

  Future<int> _requestAvailability(
    SecureSocket socket,
    Uri targetUri, {
    required Duration timeout,
  }) async {
    var path = targetUri.path.isEmpty ? '/' : targetUri.path;
    if (targetUri.hasQuery) {
      path = '$path?${targetUri.query}';
    }

    final request = StringBuffer()
      ..write('GET $path HTTP/1.1\r\n')
      ..write('Host: ${targetUri.host}\r\n')
      ..write('User-Agent: ${AppConstants.userAgent}\r\n')
      ..write('Accept: */*\r\n')
      ..write('Connection: close\r\n\r\n');
    socket.add(utf8.encode(request.toString()));
    await socket.flush();

    final reader = _SocketByteReader(socket);
    try {
      final responseBytes = await reader.readUntilHeaderEnd(timeout);
      final statusLine = ascii
          .decode(responseBytes, allowInvalid: true)
          .split('\r\n')
          .first
          .trim();
      final parts = statusLine.split(RegExp(r'\s+'));
      final code = parts.length > 1 ? parts[1] : null;
      final statusCode = int.tryParse(code ?? '');
      if (statusCode == null) {
        throw HttpException('目标站点响应异常：$statusLine');
      }
      return statusCode;
    } finally {
      await reader.cancel();
    }
  }

  String _describeSocks5Reply(int reply) {
    return switch (reply) {
      0x01 => S.current.proxy_socks5GeneralFailure,
      0x02 => S.current.proxy_socks5NotAllowed,
      0x03 => S.current.proxy_socks5NetworkUnreachable,
      0x04 => S.current.proxy_socks5HostUnreachable,
      0x05 => S.current.proxy_socks5ConnectionRefused,
      0x06 => S.current.proxy_socks5TtlExpired,
      0x07 => S.current.proxy_socks5CommandNotSupported,
      0x08 => S.current.proxy_socks5AddrTypeNotSupported,
      _ => '${S.current.error_unknown}（0x${reply.toRadixString(16)}）',
    };
  }

  static String normalizeShadowsocksCipher(String? cipher) {
    final normalized = (cipher ?? '').trim().toLowerCase();
    if (supportedShadowsocksCiphers.contains(normalized)) {
      return normalized;
    }
    return '';
  }

  static bool isShadowsocks2022Cipher(String? cipher) {
    return _shadowsocks2022KeyLengths.containsKey(
      normalizeShadowsocksCipher(cipher),
    );
  }

  static String? validateShadowsocksSecret({
    required String? cipher,
    required String? secret,
  }) {
    final normalizedCipher = normalizeShadowsocksCipher(cipher);
    if (normalizedCipher.isEmpty) {
      return S.current.proxy_ssSelectCipher;
    }

    final normalizedSecret = (secret ?? '').trim();
    if (normalizedSecret.isEmpty) {
      return isShadowsocks2022Cipher(normalizedCipher)
          ? S.current.proxy_ss2022KeyHint
          : S.current.proxy_ssPasswordHint;
    }

    final requiredKeyLength = _shadowsocks2022KeyLengths[normalizedCipher];
    if (requiredKeyLength == null) {
      return null;
    }

    final decodedKey = _decodeBase64Secret(normalizedSecret);
    if (decodedKey == null) {
      return S.current.proxy_ss2022KeyInvalidBase64;
    }
    if (decodedKey.length != requiredKeyLength) {
      return S.current.proxy_ss2022KeyInvalidLength(requiredKeyLength);
    }
    return null;
  }

  static Uint8List? _decodeBase64Secret(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      return null;
    }
    try {
      return base64.decode(base64.normalize(normalized));
    } catch (_) {
      try {
        return base64Url.decode(base64Url.normalize(normalized));
      } catch (_) {
        return null;
      }
    }
  }
}

class _SocketByteReader {
  _SocketByteReader(Stream<List<int>> stream) {
    _subscription = stream.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _notifyWaiter();
      },
      onError: (Object error, StackTrace stackTrace) {
        _error = error;
        _stackTrace = stackTrace;
        _notifyWaiter();
      },
      onDone: () {
        _done = true;
        _notifyWaiter();
      },
      cancelOnError: false,
    );
  }

  final List<int> _buffer = <int>[];
  late final StreamSubscription<List<int>> _subscription;
  Completer<void>? _waiter;
  Object? _error;
  StackTrace? _stackTrace;
  bool _done = false;

  Future<Uint8List> readExact(int length, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_buffer.length < length) {
      await _waitForData(deadline);
    }
    final bytes = Uint8List.fromList(_buffer.sublist(0, length));
    _buffer.removeRange(0, length);
    return bytes;
  }

  Future<Uint8List> readUntilHeaderEnd(Duration timeout) {
    return _readUntilSequence(const [13, 10, 13, 10], timeout);
  }

  /// 暂停订阅，保留流的可监听状态（供 SecureSocket.secure 接管）
  void pause() {
    _subscription.pause();
  }

  Future<void> cancel() async {
    await _subscription.cancel();
  }

  Future<Uint8List> _readUntilSequence(List<int> delimiter, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final index = _indexOf(delimiter);
      if (index >= 0) {
        final end = index + delimiter.length;
        final bytes = Uint8List.fromList(_buffer.sublist(0, end));
        _buffer.removeRange(0, end);
        return bytes;
      }
      await _waitForData(deadline);
    }
  }

  Future<void> _waitForData(DateTime deadline) async {
    if (_error != null) {
      Error.throwWithStackTrace(_error!, _stackTrace ?? StackTrace.current);
    }
    if (_done) {
      throw HttpException(S.current.proxy_connectionClosed);
    }

    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException(S.current.proxy_responseTimeout);
    }

    final waiter = _waiter ??= Completer<void>();
    await waiter.future.timeout(remaining);
  }

  int _indexOf(List<int> delimiter) {
    if (_buffer.length < delimiter.length) {
      return -1;
    }
    for (var i = 0; i <= _buffer.length - delimiter.length; i++) {
      var matched = true;
      for (var j = 0; j < delimiter.length; j++) {
        if (_buffer[i + j] != delimiter[j]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return i;
      }
    }
    return -1;
  }

  void _notifyWaiter() {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
    _waiter = null;
  }
}
