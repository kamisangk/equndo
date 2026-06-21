import '../l10n/s.dart';

/// 书签提醒的快捷选项
enum BookmarkReminderOption {
  twoHours,    // 2小时后
  tomorrow,    // 明天
  threeDays,   // 3天后
  nextWeek,    // 下周
  custom,      // 自定义
}

/// 书签自动删除偏好
enum BookmarkAutoDeletePreference {
  never(0),
  whenReminderSent(1),
  onOwnerReply(2),
  clearReminder(3);

  final int value;
  const BookmarkAutoDeletePreference(this.value);
}

/// BookmarkReminderOption 的扩展方法
extension BookmarkReminderOptionExt on BookmarkReminderOption {
  String get label {
    switch (this) {
      case BookmarkReminderOption.twoHours:
        return S.current.bookmark_reminderTwoHours;
      case BookmarkReminderOption.tomorrow:
        return S.current.bookmark_reminderTomorrow;
      case BookmarkReminderOption.threeDays:
        return S.current.bookmark_reminderThreeDays;
      case BookmarkReminderOption.nextWeek:
        return S.current.bookmark_reminderNextWeek;
      case BookmarkReminderOption.custom:
        return S.current.bookmark_reminderCustom;
    }
  }

  /// 根据选项计算提醒时间
  DateTime? toReminderAt() {
    final now = DateTime.now();
    switch (this) {
      case BookmarkReminderOption.twoHours:
        return now.add(const Duration(hours: 2));
      case BookmarkReminderOption.tomorrow:
        // 明天早上8点
        final tomorrow = DateTime(now.year, now.month, now.day + 1, 8, 0);
        return tomorrow;
      case BookmarkReminderOption.threeDays:
        return DateTime(now.year, now.month, now.day + 3, 8, 0);
      case BookmarkReminderOption.nextWeek:
        // 下周一早上8点
        final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
        final nextMonday = daysUntilMonday == 0 ? 7 : daysUntilMonday;
        return DateTime(now.year, now.month, now.day + nextMonday, 8, 0);
      case BookmarkReminderOption.custom:
        return null;
    }
  }
}
