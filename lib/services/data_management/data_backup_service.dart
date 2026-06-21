import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/s.dart';

/// 数据备份导出/导入服务
class DataBackupService {
  /// 需要备份的 key 前缀
  static const _backupKeyPrefixes = [
    'pref_', // 偏好设置
    'theme_', // 主题设置
    'doh_', // DOH 网络设置
    'http_proxy_', // 代理设置
    'topic_sort_', // 话题排序
    'search_', // 搜索设置
  ];

  /// 需要备份的完整 key
  static const _backupExactKeys = [
    'seed_color',
    'use_dynamic_color',
    'read_later_items',
    'pinned_category_ids',
  ];

  /// 判断 key 是否应该被备份
  static bool _shouldBackup(String key) {
    // 再检查前缀匹配
    for (final prefix in _backupKeyPrefixes) {
      if (key.startsWith(prefix)) return true;
    }
    return _backupExactKeys.contains(key);
  }

  /// 导出数据为 Map
  static Future<Map<String, dynamic>> exportData(
    SharedPreferences prefs,
  ) async {
    final pkg = await PackageInfo.fromPlatform();
    final data = <String, Map<String, dynamic>>{};

    for (final key in prefs.getKeys()) {
      if (!_shouldBackup(key)) continue;

      final value = prefs.get(key);
      if (value == null) continue;

      String type;
      dynamic serializedValue;

      if (value is bool) {
        type = 'bool';
        serializedValue = value;
      } else if (value is int) {
        type = 'int';
        serializedValue = value;
      } else if (value is double) {
        type = 'double';
        serializedValue = value;
      } else if (value is String) {
        type = 'String';
        serializedValue = value;
      } else if (value is List<String>) {
        type = 'StringList';
        serializedValue = value;
      } else {
        continue;
      }

      data[key] = {'type': type, 'value': serializedValue};
    }

    return {
      'version': 1,
      'appVersion': pkg.version,
      'exportTime': DateTime.now().toIso8601String(),
      'data': data,
    };
  }

  /// 将导出数据写入临时文件，返回文件路径
  static Future<String> exportToFile(SharedPreferences prefs) async {
    final exportData = await DataBackupService.exportData(prefs);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(exportData);

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${tempDir.path}/fluxdo_backup_$timestamp.json');
    await file.writeAsString(jsonStr);

    return file.path;
  }

  /// 从 Map 导入数据
  static Future<void> importData(
    SharedPreferences prefs,
    Map<String, dynamic> backup,
  ) async {
    final data = backup['data'] as Map<String, dynamic>?;
    if (data == null) throw FormatException(S.current.backup_missingDataField);

    for (final entry in data.entries) {
      final key = entry.key;
      final item = entry.value as Map<String, dynamic>;
      final type = item['type'] as String;
      final value = item['value'];

      switch (type) {
        case 'bool':
          await prefs.setBool(key, value as bool);
        case 'int':
          await prefs.setInt(key, value as int);
        case 'double':
          await prefs.setDouble(key, (value as num).toDouble());
        case 'String':
          await prefs.setString(key, value as String);
        case 'StringList':
          await prefs.setStringList(
            key,
            (value as List<dynamic>).cast<String>(),
          );
      }
    }
  }

  /// 从文件路径读取并解析备份数据
  static Future<Map<String, dynamic>> parseBackupFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    // 基本校验
    if (json['version'] == null || json['data'] == null) {
      throw FormatException(S.current.backup_invalidFormat);
    }

    return json;
  }
}
