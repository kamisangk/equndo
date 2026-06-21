import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile_stats_config.dart';
import 'theme_provider.dart'; // sharedPreferencesProvider

const String _configKey = 'profile_stats_config';

/// 统计卡片配置 Provider
class ProfileStatsConfigNotifier extends Notifier<ProfileStatsConfig> {
  Timer? _saveTimer;
  @override
  ProfileStatsConfig build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final jsonStr = prefs.getString(_configKey);
    if (jsonStr != null) {
      try {
        return ProfileStatsConfig.fromJsonString(jsonStr);
      } catch (_) {
        // 配置损坏，使用默认值
      }
    }
    return const ProfileStatsConfig();
  }

  void update(ProfileStatsConfig config) {
    state = config;
    _save(config);
  }

  void setLayoutMode(StatsLayoutMode mode) {
    update(state.copyWith(layoutMode: mode));
  }

  void setColumnsPerRow(int columns) {
    update(state.copyWith(columnsPerRow: columns));
  }

  void setDataSource(StatsDataSource source) {
    final nextSource = profileStatsVisibleDataSources.contains(source)
        ? source
        : StatsDataSource.equn;
    // 切换数据源时，自动移除不兼容的统计项
    final compatible = state.enabledStats
        .where((s) => isStatCompatible(s, nextSource))
        .toList();
    update(
      state.copyWith(
        dataSource: nextSource,
        enabledStats: compatible.isEmpty ? defaultEqunProfileStats : compatible,
      ),
    );
  }

  void setEnabledStats(List<ProfileStatType> stats) {
    update(
      state.copyWith(
        enabledStats: stats
            .where((stat) => isStatCompatible(stat, state.dataSource))
            .toList(),
      ),
    );
  }

  void addStat(ProfileStatType stat) {
    if (isStatCompatible(stat, state.dataSource) &&
        !state.enabledStats.contains(stat)) {
      update(state.copyWith(enabledStats: [...state.enabledStats, stat]));
    }
  }

  void removeStat(ProfileStatType stat) {
    update(
      state.copyWith(
        enabledStats: state.enabledStats.where((s) => s != stat).toList(),
      ),
    );
  }

  void reorderStats(int oldIndex, int newIndex) {
    final stats = List<ProfileStatType>.from(state.enabledStats);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = stats.removeAt(oldIndex);
    stats.insert(newIndex, item);
    update(state.copyWith(enabledStats: stats));
  }

  /// 防抖保存（300ms 内多次操作只写一次磁盘）
  void _save(ProfileStatsConfig config) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      final prefs = ref.read(sharedPreferencesProvider);
      prefs.setString(_configKey, config.toJsonString());
    });
  }
}

final profileStatsConfigProvider =
    NotifierProvider<ProfileStatsConfigNotifier, ProfileStatsConfig>(
      ProfileStatsConfigNotifier.new,
    );
