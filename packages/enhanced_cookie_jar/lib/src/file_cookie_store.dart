import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as path;

import 'canonical_cookie.dart';

class FileCookieStore {
  FileCookieStore(this.directoryPath);

  final String directoryPath;

  /// 上次已知的磁盘文件内容（读取或写入成功时更新）。
  /// 内容未变时跳过磁盘写——Discourse 几乎每个响应都刷新 session cookie，
  /// 但 session cookie 不持久化，持久集合多数时候并没有变化。
  String? _lastKnownContent;

  String get _filePath => path.join(directoryPath, 'cookies.v1.json');

  /// 临时文件带实例唯一后缀：同进程多个 isolate（如 iOS 后台轮询任务）
  /// 各自持有 store 实例并发写盘时，不会交错写坏同一个临时文件；
  /// rename 的原子性保证正式文件始终是完整 JSON。
  late final String _tmpPath = '$_filePath.'
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${identityHashCode(this).toRadixString(36)}.tmp';

  Future<List<CanonicalCookie>> readAll() async {
    final file = io.File(_filePath);
    if (!await file.exists()) return const [];
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) return const [];
      final jsonValue = jsonDecode(text);
      if (jsonValue is! List) return const [];
      final cookies = <CanonicalCookie>[];
      for (final entry in jsonValue.whereType<Map>()) {
        try {
          cookies.add(CanonicalCookie.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          // 跳过单个解析失败的 cookie，不影响其余
        }
      }
      _lastKnownContent = text;
      return cookies;
    } catch (_) {
      // 文件损坏（JSON 截断等），返回空列表而非崩溃
      return const [];
    }
  }

  /// 原子写入：先写临时文件，再 rename 替换，避免写入中断导致文件损坏
  Future<void> writeAll(List<CanonicalCookie> cookies) async {
    final payload = cookies.map((e) => e.toJson()).toList(growable: false);
    final content = jsonEncode(payload);
    if (content == _lastKnownContent) return;

    final dir = io.Directory(directoryPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final tmpFile = io.File(_tmpPath);
    await tmpFile.writeAsString(content, flush: true);
    await tmpFile.rename(_filePath);
    _lastKnownContent = content;
  }

  Future<void> deleteAll() async {
    _lastKnownContent = null;
    final file = io.File(_filePath);
    if (await file.exists()) {
      await file.delete();
    }
    // 清理本实例及历史实例可能残留的临时文件
    final dir = io.Directory(directoryPath);
    if (!await dir.exists()) return;
    final prefix = '${path.basename(_filePath)}.';
    await for (final entity in dir.list()) {
      if (entity is! io.File) continue;
      final name = path.basename(entity.path);
      if (name.startsWith(prefix) && name.endsWith('.tmp')) {
        try {
          await entity.delete();
        } catch (_) {
          // 残留 tmp 文件无害，删除失败可忽略
        }
      }
    }
  }
}
