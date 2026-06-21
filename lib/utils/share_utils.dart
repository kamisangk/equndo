import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../constants.dart';
import '../l10n/s.dart';
import '../services/toast_service.dart';
import 'platform_utils.dart';

/// 文件分享/保存结果。
///
/// [finalPath] 为用户最终保存位置（桌面端"另存为"的路径）；移动端通过系统
/// 分享面板时无法知道用户的目的地，[finalPath] 为 null 但 [shared] 为 true。
/// 用户取消时 [shared] 为 false 且 [finalPath] 为 null。
class ShareOutcome {
  const ShareOutcome({required this.shared, this.finalPath});

  final bool shared;
  final String? finalPath;
}

/// 分享链接工具类
class ShareUtils {
  /// 构建分享链接
  ///
  /// [path] 路径部分，如 `/t/topic/123` 或 `/u/username`
  /// [username] 当前用户名
  /// [anonymousShare] 是否匿名分享（不附带用户标识）
  static String buildShareUrl({
    required String path,
    String? username,
    required bool anonymousShare,
  }) {
    final base = '${AppConstants.baseUrl}$path';
    if (anonymousShare || username == null || username.isEmpty) {
      return base;
    }
    return '$base?u=$username';
  }

  /// 分享或保存文件
  ///
  /// 桌面端弹出"另存为"对话框，移动端使用系统分享面板。
  /// 返回 [ShareOutcome]：桌面端 `finalPath` 为用户选择的最终路径，
  /// 移动端为 null（系统分享面板不暴露目的地）。
  static Future<ShareOutcome> shareOrSaveFile(
    XFile file, {
    String? subject,
  }) async {
    if (PlatformUtils.isDesktop) {
      return _saveFileDialog(file);
    }
    await SharePlus.instance.share(
      ShareParams(files: [file], subject: subject),
    );
    return const ShareOutcome(shared: true);
  }

  /// 桌面端"另存为"对话框
  static Future<ShareOutcome> _saveFileDialog(XFile file) async {
    final fileName = p.basename(file.path);
    final ext = p.extension(fileName).replaceFirst('.', '');

    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: S.current.share_selectSaveLocation,
      fileName: fileName,
      type: ext.isNotEmpty ? FileType.custom : FileType.any,
      allowedExtensions: ext.isNotEmpty ? [ext] : null,
    );

    if (outputPath == null) {
      return const ShareOutcome(shared: false);
    }

    try {
      final sourceFile = File(file.path);
      await sourceFile.copy(outputPath);
      ToastService.show(S.current.share_fileSaved);
      return ShareOutcome(shared: true, finalPath: outputPath);
    } catch (e) {
      debugPrint('[ShareUtils] saveFile failed: $e');
      ToastService.showError(S.current.share_saveFailed);
      return const ShareOutcome(shared: false);
    }
  }
}
