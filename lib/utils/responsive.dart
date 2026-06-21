import 'package:flutter/widgets.dart';
import 'layout_lock.dart';

/// 响应式布局断点
class Breakpoints {
  Breakpoints._();

  /// 手机最大宽度
  static const double mobile = 600;

  /// 平板最大宽度
  static const double tablet = 1200;

  /// 内容最大宽度（用于限制帖子等内容的宽度）
  static const double maxContentWidth = 800;
}

/// 设备类型枚举
enum DeviceType { mobile, tablet, desktop }

/// 响应式布局工具类
class Responsive {
  Responsive._();

  static DeviceType? _lastDeviceType;

  /// 根据屏幕宽度获取设备类型
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    DeviceType computed;
    if (width < Breakpoints.mobile) {
      computed = DeviceType.mobile;
    } else if (width < Breakpoints.tablet) {
      computed = DeviceType.tablet;
    } else {
      computed = DeviceType.desktop;
    }

    if (LayoutLock.locked && _lastDeviceType != null) {
      return _lastDeviceType!;
    }
    _lastDeviceType = computed;
    return computed;
  }

  /// 是否为手机
  static bool isMobile(BuildContext context) {
    return getDeviceType(context) == DeviceType.mobile;
  }

  /// 是否为平板
  static bool isTablet(BuildContext context) {
    return getDeviceType(context) == DeviceType.tablet;
  }

  /// 是否为桌面
  static bool isDesktop(BuildContext context) {
    return getDeviceType(context) == DeviceType.desktop;
  }

  /// 是否显示侧边导航（平板及以上）
  static bool showNavigationRail(BuildContext context) {
    return !isMobile(context);
  }

  /// 是否显示底部导航（仅手机）
  static bool showBottomNavigation(BuildContext context) {
    return isMobile(context);
  }
}

/// 响应式布局 Builder Widget
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= Breakpoints.tablet) {
          return desktop ?? tablet ?? mobile;
        } else if (constraints.maxWidth >= Breakpoints.mobile) {
          return tablet ?? mobile;
        }
        return mobile;
      },
    );
  }
}
