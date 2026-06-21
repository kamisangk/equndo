/// 全屏/特殊状态下冻结动态布局切换
class LayoutLock {
  LayoutLock._();

  static int _lockCount = 0;
  static bool? _lastCanShowBothPanes;

  static bool get locked => _lockCount > 0;

  static void acquire() {
    _lockCount += 1;
  }

  static void release() {
    if (_lockCount > 0) {
      _lockCount -= 1;
    }
  }

  /// 在锁定期间返回上一次的布局判定结果，避免布局结构切换
  static bool resolveCanShowBoth({required bool computed}) {
    if (locked && _lastCanShowBothPanes != null) {
      return _lastCanShowBothPanes!;
    }
    _lastCanShowBothPanes = computed;
    return computed;
  }
}
