import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../discourse_cache_manager.dart';

/// 缓存大小计算服务
class CacheSizeService {
  /// flutter_cache_manager 的缓存 key 列表
  static const _cacheKeys = [
    DiscourseCacheManager.key,
    EmojiCacheManager.key,
    ExternalImageCacheManager.key,
    StickerCacheManager.key,
  ];

  /// 计算图片缓存大小（遍历三个 CacheManager 的磁盘目录）
  ///
  /// flutter_cache_manager 将缓存存储在 `getTemporaryDirectory()/{key}` 下
  static Future<int> getImageCacheSize() async {
    final tempDir = await getTemporaryDirectory();
    int totalSize = 0;
    for (final key in _cacheKeys) {
      totalSize += await _getDirectorySize(Directory('${tempDir.path}/$key'));
    }
    return totalSize;
  }

  /// 计算 Cookie 缓存大小（.cookies 目录）
  static Future<int> getCookieCacheSize() async {
    final docDir = await getApplicationDocumentsDirectory();
    return _getDirectorySize(Directory('${docDir.path}/.cookies'));
  }

  /// 递归计算目录大小
  static Future<int> _getDirectorySize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// 删除图片缓存目录
  ///
  /// emptyCache() 只清除了 CacheManager 追踪的条目，
  /// 磁盘上的文件可能残留，需要直接删除整个目录来彻底清理。
  static Future<void> deleteImageCacheDirs() async {
    final tempDir = await getTemporaryDirectory();
    for (final key in _cacheKeys) {
      final dir = Directory('${tempDir.path}/$key');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }

  /// 格式化字节为可读字符串
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
