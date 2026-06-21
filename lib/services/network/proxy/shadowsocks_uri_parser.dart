import 'dart:convert';

import '../../../l10n/s.dart';
import 'proxy_settings_service.dart';

class ShadowsocksUriConfig {
  const ShadowsocksUriConfig({
    required this.host,
    required this.port,
    required this.cipher,
    required this.password,
    this.remarks,
  });

  final String host;
  final int port;
  final String cipher;
  final String password;
  final String? remarks;
}

class _DecodedShadowsocksBody {
  const _DecodedShadowsocksBody({
    required this.cipher,
    required this.password,
    required this.host,
    required this.port,
  });

  final String cipher;
  final String password;
  final String host;
  final int port;
}

class _ParsedHostPort {
  const _ParsedHostPort({
    required this.host,
    required this.port,
  });

  final String host;
  final int port;
}

class ShadowsocksUriParser {
  const ShadowsocksUriParser._();

  static ShadowsocksUriConfig parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      throw FormatException(S.current.proxy_ssLinkEmpty);
    }
    if (!raw.toLowerCase().startsWith('ss://')) {
      throw FormatException(S.current.proxy_ssOnlySsProtocol);
    }

    final payload = raw.substring(5);
    final hashIndex = payload.indexOf('#');
    final body = hashIndex >= 0 ? payload.substring(0, hashIndex) : payload;
    final remarks = hashIndex >= 0
        ? Uri.decodeComponent(payload.substring(hashIndex + 1))
        : null;

    final decoded = _parseBody(body);
    final cipher =
        ProxySettingsService.normalizeShadowsocksCipher(decoded.cipher);
    if (cipher.isEmpty) {
      throw FormatException(
        S.current.proxy_ssUnsupportedCipher(ProxySettingsService.supportedShadowsocksCiphers.join(' / ')),
      );
    }

    return ShadowsocksUriConfig(
      host: decoded.host,
      port: decoded.port,
      cipher: cipher,
      password: decoded.password,
      remarks: remarks,
    );
  }

  static _DecodedShadowsocksBody _parseBody(String body) {
    final cleaned = body.trim();
    if (cleaned.isEmpty) {
      throw FormatException(S.current.proxy_ssLinkContentEmpty);
    }

    if (!cleaned.contains('@')) {
      return _parseBody(_decodeBase64Payload(cleaned));
    }

    final atIndex = cleaned.lastIndexOf('@');
    final userInfoPart = cleaned.substring(0, atIndex);
    final hostPart = cleaned.substring(atIndex + 1).split('?').first;

    final userInfo = userInfoPart.contains(':')
        ? Uri.decodeComponent(userInfoPart)
        : _decodeBase64Payload(userInfoPart);

    final separatorIndex = userInfo.indexOf(':');
    if (separatorIndex <= 0) {
      throw FormatException(S.current.proxy_ssCannotParseCipher);
    }

    final hostPort = _parseHostPort(hostPart);
    return _DecodedShadowsocksBody(
      cipher: userInfo.substring(0, separatorIndex),
      password: userInfo.substring(separatorIndex + 1),
      host: hostPort.host,
      port: hostPort.port,
    );
  }

  static String _decodeBase64Payload(String input) {
    final normalized = input.trim();
    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(normalized)));
    } catch (_) {
      try {
        return utf8.decode(base64.decode(base64.normalize(normalized)));
      } catch (_) {
        throw FormatException(S.current.proxy_ssBase64DecodeFailed);
      }
    }
  }

  static _ParsedHostPort _parseHostPort(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      throw FormatException(S.current.proxy_ssMissingAddress);
    }

    if (value.startsWith('[')) {
      final closing = value.indexOf(']');
      if (closing <= 0 ||
          closing + 2 > value.length ||
          value[closing + 1] != ':') {
        throw FormatException(S.current.proxy_ssInvalidIpv6);
      }
      final port = int.tryParse(value.substring(closing + 2));
      if (port == null || port <= 0 || port > 65535) {
        throw FormatException(S.current.proxy_ssInvalidPort);
      }
      return _ParsedHostPort(host: value.substring(1, closing), port: port);
    }

    final colon = value.lastIndexOf(':');
    if (colon <= 0 || colon == value.length - 1) {
      throw FormatException(S.current.proxy_ssMissingPort);
    }
    final port = int.tryParse(value.substring(colon + 1));
    if (port == null || port <= 0 || port > 65535) {
      throw FormatException(S.current.proxy_ssInvalidPort);
    }
    return _ParsedHostPort(host: value.substring(0, colon), port: port);
  }
}
