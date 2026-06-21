import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Android 前台服务 TaskHandler
///
/// 运行在独立 Isolate，但前台服务的存在保持了进程存活，
/// 主 Isolate 的 MessageBusService 长轮询不会被系统杀死。
/// 因此 TaskHandler 本身不执行轮询逻辑。
@pragma('vm:entry-point')
class NotificationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 空操作 — 主 Isolate 的 MessageBus 已在运行
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 空操作
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // 清理
  }
}

/// 前台服务启动回调（顶层函数）
@pragma('vm:entry-point')
void startNotificationTaskHandler() {
  FlutterForegroundTask.setTaskHandler(NotificationTaskHandler());
}
