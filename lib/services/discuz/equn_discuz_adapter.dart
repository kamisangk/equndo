import '../../models/category.dart';
import '../../models/topic.dart';
import '../../providers/topic_list/filter_provider.dart';
import '../../utils/time_utils.dart';
import 'equn_discuz_models.dart';

class EqunDiscuzAdapter {
  static const List<String> _categoryColors = [
    '2563EB',
    '059669',
    'DC2626',
    '7C3AED',
    'EA580C',
    '0891B2',
    '4F46E5',
    '65A30D',
  ];

  static Topic guideTopicToTopic(EqunTopicSummary topic) {
    return _topicFromSummary(topic);
  }

  static Topic forumTopicToTopic(EqunTopicSummary topic, EqunForum forum) {
    return _topicFromSummary(
      topic,
      fallbackForumId: forum.fid,
      fallbackForumName: forum.name,
    );
  }

  static TopicListResponse guideTopicsToResponse(
    List<EqunTopicSummary> topics, {
    bool hasMore = true,
  }) {
    return TopicListResponse(
      topics: topics.map(guideTopicToTopic).toList(),
      moreTopicsUrl: hasMore ? 'equn-guide-more' : null,
    );
  }

  static TopicListResponse forumTopicsToResponse(
    EqunForumTopicPage page, {
    bool hasMore = true,
  }) {
    return TopicListResponse(
      topics: page.topics
          .map((topic) => forumTopicToTopic(topic, page.forum))
          .toList(),
      moreTopicsUrl: hasMore ? 'equn-forum-more' : null,
    );
  }

  static TopicListResponse userTopicsToResponse(EqunUserTopicPage page) {
    return TopicListResponse(
      topics: page.topics.map(guideTopicToTopic).toList(),
      moreTopicsUrl: page.hasMore ? 'equn-user-more' : null,
    );
  }

  static List<Category> forumGroupsToCategories(List<EqunForumGroup> groups) {
    final categories = <Category>[];
    var colorIndex = 0;

    for (final group in groups) {
      categories.add(
        Category(
          id: group.fid,
          name: group.name,
          color: _colorForIndex(colorIndex++),
          textColor: 'FFFFFF',
          slug: 'forum-${group.fid}',
          icon: 'folder',
        ),
      );

      for (final forum in group.forums) {
        categories.add(
          Category(
            id: forum.fid,
            name: forum.name,
            color: _colorForIndex(colorIndex++),
            textColor: 'FFFFFF',
            slug: 'forum-${forum.fid}',
            description: forum.description,
            parentCategoryId: group.fid,
            uploadedLogo: forum.iconUrl,
            icon: forum.iconUrl == null || forum.iconUrl!.isEmpty
                ? 'comments'
                : null,
            permission: 1,
          ),
        );
      }
    }

    return categories;
  }

  static EqunGuideFilter guideFilterForTopicFilter(TopicListFilter filter) {
    switch (filter) {
      case TopicListFilter.latestThreads:
        return EqunGuideFilter.latestThreads;
      case TopicListFilter.latest:
      case TopicListFilter.newTopics:
      case TopicListFilter.unread:
      case TopicListFilter.unseen:
      case TopicListFilter.top:
      case TopicListFilter.hot:
        return EqunGuideFilter.latestReplies;
    }
  }

  static Topic _topicFromSummary(
    EqunTopicSummary topic, {
    int? fallbackForumId,
    String? fallbackForumName,
  }) {
    final forumId = topic.forumId ?? fallbackForumId ?? 0;
    final author = topic.author.isNotEmpty ? topic.author : 'unknown';
    final lastPoster = topic.lastPoster?.isNotEmpty == true
        ? topic.lastPoster
        : author;

    return Topic(
      id: topic.tid,
      title: topic.title,
      slug: 'thread-${topic.tid}',
      postsCount: topic.replyCount + 1,
      replyCount: topic.replyCount,
      views: topic.viewCount,
      likeCount: 0,
      excerpt: _buildExcerpt(topic, fallbackForumName),
      createdAt: _parseEqunDate(topic.createdText),
      lastPostedAt:
          _parseEqunDate(topic.lastPostText) ??
          _parseEqunDate(topic.createdText),
      lastPosterUsername: lastPoster,
      categoryId: forumId.toString(),
      pinned: topic.pinned,
      tags: [
        if (topic.digest) const Tag(name: '精华'),
        if (topic.readPermissionText != null)
          Tag(name: topic.readPermissionText!),
      ],
      posters: [
        TopicPoster(
          userId: _stableUserId(author),
          description: 'Original Poster',
          extras: '',
          user: TopicUser(
            id: _stableUserId(author),
            username: author,
            avatarTemplate: '',
          ),
        ),
        if (lastPoster != null && lastPoster != author)
          TopicPoster(
            userId: _stableUserId(lastPoster),
            description: 'Most Recent Poster',
            extras: 'latest',
            user: TopicUser(
              id: _stableUserId(lastPoster),
              username: lastPoster,
              avatarTemplate: '',
            ),
          ),
      ],
      highestPostNumber: topic.replyCount + 1,
    );
  }

  static String? _buildExcerpt(
    EqunTopicSummary topic,
    String? fallbackForumName,
  ) {
    final parts = [
      topic.forumName?.isNotEmpty == true ? topic.forumName : fallbackForumName,
      topic.author.isNotEmpty ? '作者 ${topic.author}' : null,
      topic.lastPoster?.isNotEmpty == true ? '最后回复 ${topic.lastPoster}' : null,
      topic.lastPostText,
      topic.readPermissionText,
    ].whereType<String>().where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static DateTime? _parseEqunDate(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final cleaned = text.replaceAll(RegExp(r'发表于|最后回复|查看详情'), '').trim();

    final now = DateTime.now();
    if (cleaned.contains('昨天')) {
      final time = _parseHourMinute(cleaned);
      return DateTime(now.year, now.month, now.day - 1, time.$1, time.$2);
    }
    if (cleaned.contains('前天')) {
      final time = _parseHourMinute(cleaned);
      return DateTime(now.year, now.month, now.day - 2, time.$1, time.$2);
    }
    if (cleaned.contains('小时前')) {
      final hours = _firstInt(cleaned) ?? 0;
      return now.subtract(Duration(hours: hours));
    }
    if (cleaned.contains('分钟前')) {
      final minutes = _firstInt(cleaned) ?? 0;
      return now.subtract(Duration(minutes: minutes));
    }

    final match = RegExp(
      r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?',
    ).firstMatch(cleaned);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.tryParse(match.group(4) ?? '') ?? 0,
        int.tryParse(match.group(5) ?? '') ?? 0,
      );
    }

    final shortMatch = RegExp(
      r'(\d{1,2})[-/](\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?',
    ).firstMatch(cleaned);
    if (shortMatch != null) {
      return DateTime(
        now.year,
        int.parse(shortMatch.group(1)!),
        int.parse(shortMatch.group(2)!),
        int.tryParse(shortMatch.group(3) ?? '') ?? 0,
        int.tryParse(shortMatch.group(4) ?? '') ?? 0,
      );
    }

    return TimeUtils.parseUtcTime(cleaned);
  }

  static (int, int) _parseHourMinute(String text) {
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return (0, 0);
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  static int? _firstInt(String text) {
    final match = RegExp(r'\d+').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static int _stableUserId(String username) {
    var hash = 0;
    for (final codeUnit in username.codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return hash == 0 ? 1 : hash;
  }

  static String _colorForIndex(int index) {
    return _categoryColors[index % _categoryColors.length];
  }
}
