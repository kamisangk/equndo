import 'package:catcher_2/catcher_2.dart';
import 'package:catcher_2/model/platform_type.dart';
import 'package:flutter/widgets.dart';

import 'log_writer.dart';

/// Catcher2 自定义 ReportHandler，将异常报告通过 LogWriter 写入 JSONL 文件
class JsonFileHandler extends ReportHandler {
  @override
  Future<bool> handle(Report report, BuildContext? context) async {
    try {
      final entry = _buildJsonEntry(report);
      LogWriter.instance.write(entry);
      // 未捕获异常可能伴随崩溃，立即落盘缓冲避免丢失现场
      await LogWriter.instance.flushNow();
      return true;
    } catch (e) {
      logger.warning('JsonFileHandler 写入失败: $e');
      return false;
    }
  }

  @override
  List<PlatformType> getSupportedPlatforms() => [
    PlatformType.android,
    PlatformType.iOS,
    PlatformType.macOS,
    PlatformType.linux,
    PlatformType.windows,
  ];

  /// 非空字符串返回原值，否则返回 null（避免写入空堆栈）
  static String? _nonEmpty(String? s) =>
      s != null && s.trim().isNotEmpty ? s : null;

  /// 构建 JSON 条目
  Map<String, dynamic> _buildJsonEntry(Report report) {
    final customParams = report.customParameters;
    return {
      'timestamp': report.dateTime.toIso8601String(),
      'level': 'error',
      'type': 'general',
      'message': customParams['message']?.toString() ??
          report.error?.toString() ??
          'Unknown error',
      if (customParams['tag'] != null) 'tag': customParams['tag'],
      'error': report.error?.toString() ?? 'Unknown error',
      'errorType': report.error?.runtimeType.toString() ?? 'Unknown',
      'stackTrace': _nonEmpty(report.stackTrace?.toString()),
    };
  }
}
