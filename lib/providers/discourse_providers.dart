/// Discourse Providers
/// 
/// 这个文件重新导出所有 Discourse 相关的 providers 和模型
/// 保持向后兼容，其他文件可以继续使用 `import 'discourse_providers.dart'`
library;

// 核心 providers (服务、认证、当前用户)
export 'core_providers.dart';

// 话题列表相关
export 'topic_list/topic_list_provider.dart';
export 'topic_list/filter_provider.dart';
export 'topic_list/sort_provider.dart';
export 'topic_list/tab_state_provider.dart';

// 话题详情相关
export 'topic_detail_provider.dart';

// 分类和标签相关
export 'category_provider.dart';

// 用户内容相关 (浏览历史、书签、我的话题)
export 'user_content_providers.dart';

// 搜索相关
export 'search_provider.dart';

// 表情相关
export 'emoji_provider.dart';

// 表情包市场相关
export 'sticker_provider.dart';

// 会话未读状态相关
export 'topic_session_provider.dart';

// 搜索设置相关
export 'search_settings_provider.dart';
