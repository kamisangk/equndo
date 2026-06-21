import 'dart:convert';

/// 统计项类型
enum ProfileStatType {
  // Summary API 字段
  daysVisited,
  postsReadCount,
  likesReceived,
  likesGiven,
  topicCount,
  postCount,
  timeRead,
  recentTimeRead,
  bookmarkCount,
  topicsEntered,
  // connect.linux.do 独有字段
  topicsRepliedTo,
  likesReceivedDays,
  likesReceivedUsers,
  // Equn 论坛积分字段
  points,
  basicScore,
  wikiPuzzle,
  competitionScore,
  contribution,
}

/// 布局模式
enum StatsLayoutMode { grid, scroll }

/// 数据源
enum StatsDataSource {
  summary, // 全量（Summary API）
  connect, // 信任等级周期（connect.linux.do）
  equn, // Equn 论坛积分
}

const List<StatsDataSource> profileStatsVisibleDataSources = [
  StatsDataSource.equn,
];

const List<ProfileStatType> defaultEqunProfileStats = [
  ProfileStatType.points,
  ProfileStatType.basicScore,
  ProfileStatType.wikiPuzzle,
  ProfileStatType.competitionScore,
  ProfileStatType.contribution,
];

/// 各数据源支持的统计项
const Map<StatsDataSource, Set<ProfileStatType>> supportedStatsPerSource = {
  StatsDataSource.summary: {
    ProfileStatType.daysVisited,
    ProfileStatType.postsReadCount,
    ProfileStatType.likesReceived,
    ProfileStatType.likesGiven,
    ProfileStatType.topicCount,
    ProfileStatType.postCount,
    ProfileStatType.timeRead,
    ProfileStatType.recentTimeRead,
    ProfileStatType.bookmarkCount,
    ProfileStatType.topicsEntered,
  },
  StatsDataSource.connect: {
    ProfileStatType.daysVisited,
    ProfileStatType.postsReadCount,
    ProfileStatType.likesReceived,
    ProfileStatType.likesGiven,
    ProfileStatType.topicsEntered,
    ProfileStatType.topicsRepliedTo,
    ProfileStatType.likesReceivedDays,
    ProfileStatType.likesReceivedUsers,
  },
  StatsDataSource.equn: {
    ProfileStatType.points,
    ProfileStatType.basicScore,
    ProfileStatType.wikiPuzzle,
    ProfileStatType.competitionScore,
    ProfileStatType.contribution,
  },
};

/// 判断某统计项是否兼容指定数据源
bool isStatCompatible(ProfileStatType stat, StatsDataSource source) {
  return supportedStatsPerSource[source]?.contains(stat) ?? false;
}

/// 统计卡片配置
class ProfileStatsConfig {
  final List<ProfileStatType> enabledStats;
  final StatsLayoutMode layoutMode;
  final int columnsPerRow; // 网格模式 2/3/4
  final StatsDataSource dataSource;

  const ProfileStatsConfig({
    this.enabledStats = defaultEqunProfileStats,
    this.layoutMode = StatsLayoutMode.grid,
    this.columnsPerRow = 4,
    this.dataSource = StatsDataSource.equn,
  });

  ProfileStatsConfig copyWith({
    List<ProfileStatType>? enabledStats,
    StatsLayoutMode? layoutMode,
    int? columnsPerRow,
    StatsDataSource? dataSource,
  }) {
    return ProfileStatsConfig(
      enabledStats: enabledStats ?? this.enabledStats,
      layoutMode: layoutMode ?? this.layoutMode,
      columnsPerRow: columnsPerRow ?? this.columnsPerRow,
      dataSource: dataSource ?? this.dataSource,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabledStats': enabledStats.map((e) => e.name).toList(),
    'layoutMode': layoutMode.name,
    'columnsPerRow': columnsPerRow,
    'dataSource': dataSource.name,
  };

  factory ProfileStatsConfig.fromJson(Map<String, dynamic> json) {
    final source = StatsDataSource.values.firstWhere(
      (v) => v.name == json['dataSource'],
      orElse: () => StatsDataSource.equn,
    );
    final dataSource = profileStatsVisibleDataSources.contains(source)
        ? source
        : StatsDataSource.equn;
    final rawStats = (json['enabledStats'] as List<dynamic>?)
        ?.map(
          (e) => ProfileStatType.values.firstWhere(
            (v) => v.name == e,
            orElse: () => ProfileStatType.daysVisited,
          ),
        )
        .toList();
    final compatibleStats = rawStats
        ?.where((stat) => isStatCompatible(stat, dataSource))
        .toList();

    return ProfileStatsConfig(
      enabledStats: rawStats == null
          ? const ProfileStatsConfig().enabledStats
          : compatibleStats!.isNotEmpty || rawStats.isEmpty
          ? compatibleStats
          : const ProfileStatsConfig().enabledStats,
      layoutMode: StatsLayoutMode.values.firstWhere(
        (v) => v.name == json['layoutMode'],
        orElse: () => StatsLayoutMode.grid,
      ),
      columnsPerRow: json['columnsPerRow'] as int? ?? 4,
      dataSource: dataSource,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ProfileStatsConfig.fromJsonString(String jsonStr) {
    return ProfileStatsConfig.fromJson(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
  }
}
