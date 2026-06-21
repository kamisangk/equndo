import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../models/user.dart';
import '../pages/profile_page.dart';
import '../pages/topics_screen.dart';
import '../providers/discourse_providers.dart';
import '../widgets/common/smart_avatar.dart';
import 'nav_action_bus.dart';
import 'nav_entry.dart';

/// 注册所有可选底栏入口
///
/// 用户在底栏布局编辑器里从这些里挑选显示哪些、顺序如何。
/// 增加新入口时在 [buildAll] 里追加一条即可。
class NavEntryRegistry {
  NavEntryRegistry._();

  /// 构建完整候选列表
  static List<NavEntry> buildAll() {
    return [
      NavEntry(
        id: NavEntryIds.home,
        kind: NavEntryKind.page,
        iconData: Icons.home_outlined,
        selectedIconData: Icons.home,
        label: (ctx) => ctx.l10n.nav_home,
        pageBuilder: (ctx, isActive) => TopicsScreen(isActive: isActive),
        locked: true,
        defaultInBottomNav: true,
      ),
      NavEntry(
        id: NavEntryIds.profile,
        kind: NavEntryKind.page,
        iconData: Icons.person_outline,
        selectedIconData: Icons.person,
        label: (ctx) => ctx.l10n.nav_mine,
        pageBuilder: (ctx, isActive) => ProfilePage(isActive: isActive),
        locked: true,
        defaultInBottomNav: true,
        // 已登录时用用户头像替代默认图标
        customIconBuilder: (ctx, ref) =>
            _profileIcon(ctx, ref, selected: false),
        customSelectedIconBuilder: (ctx, ref) =>
            _profileIcon(ctx, ref, selected: true),
      ),
    ];
  }

  /// 按 id 查找 entry
  static NavEntry? byId(String id) {
    for (final e in buildAll()) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 根据用户登录状态过滤可用 entry
  static bool isAvailable(NavEntry entry, User? user) {
    if (!entry.requiresLogin) return true;
    return user != null;
  }

  /// 默认底栏 id 列表
  static List<String> defaultBottomNavIds() {
    return buildAll()
        .where((e) => e.defaultInBottomNav)
        .map((e) => e.id)
        .toList();
  }

  /// 必须包含的 locked id 列表
  static List<String> lockedIds() {
    return buildAll().where((e) => e.locked).map((e) => e.id).toList();
  }
}

Widget _profileIcon(
  BuildContext context,
  WidgetRef ref, {
  required bool selected,
}) {
  final user = ref.watch(currentUserProvider).value;
  final avatarUrl = user?.getAvatarUrl();
  final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
  if (hasAvatar) {
    return SmartAvatar(
      imageUrl: avatarUrl,
      radius: 12,
      fallbackText: user?.username,
    );
  }
  return Icon(selected ? Icons.person : Icons.person_outline);
}
