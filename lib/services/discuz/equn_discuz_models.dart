enum EqunGuideFilter {
  latestReplies('new', '最新回复'),
  latestThreads('newthread', '最新发表');

  const EqunGuideFilter(this.view, this.label);

  final String view;
  final String label;
}

class EqunTopicSummary {
  final int tid;
  final int? forumId;
  final String? forumName;
  final String title;
  final String author;
  final int replyCount;
  final int viewCount;
  final String? lastPoster;
  final String? lastPostText;
  final String? createdText;
  final int? readPermission;
  final String? readPermissionText;
  final String url;
  final bool pinned;
  final bool digest;

  const EqunTopicSummary({
    required this.tid,
    required this.title,
    required this.author,
    required this.replyCount,
    required this.viewCount,
    required this.url,
    this.forumId,
    this.forumName,
    this.lastPoster,
    this.lastPostText,
    this.createdText,
    this.readPermission,
    this.readPermissionText,
    this.pinned = false,
    this.digest = false,
  });
}

class EqunForum {
  final int fid;
  final String name;
  final int threads;
  final int posts;
  final int todayPosts;
  final String? iconUrl;
  final String? description;
  final int? parentFid;

  const EqunForum({
    required this.fid,
    required this.name,
    this.threads = 0,
    this.posts = 0,
    this.todayPosts = 0,
    this.iconUrl,
    this.description,
    this.parentFid,
  });
}

class EqunForumGroup {
  final int fid;
  final String name;
  final List<EqunForum> forums;

  const EqunForumGroup({
    required this.fid,
    required this.name,
    required this.forums,
  });
}

class EqunForumTopicPage {
  final EqunForum forum;
  final List<EqunTopicSummary> topics;
  final int page;
  final int pageSize;

  const EqunForumTopicPage({
    required this.forum,
    required this.topics,
    required this.page,
    required this.pageSize,
  });
}

class EqunUserTopicPage {
  final List<EqunTopicSummary> topics;
  final int page;
  final bool hasMore;

  const EqunUserTopicPage({
    required this.topics,
    required this.page,
    required this.hasMore,
  });
}

enum EqunThreadDetailStatus { ok, permissionDenied }

class EqunPost {
  final int pid;
  final String author;
  final int? authorId;
  final int position;
  final String message;
  final String? avatarUrl;
  final String? dateline;

  const EqunPost({
    required this.pid,
    required this.author,
    required this.message,
    this.position = 0,
    this.authorId,
    this.avatarUrl,
    this.dateline,
  });
}

class EqunThreadDetail {
  final int tid;
  final int? fid;
  final String title;
  final String? author;
  final int replyCount;
  final int viewCount;
  final int? readPermission;
  final EqunThreadDetailStatus status;
  final String? permissionMessage;
  final List<EqunPost> posts;

  const EqunThreadDetail({
    required this.tid,
    required this.title,
    required this.status,
    required this.posts,
    this.fid,
    this.author,
    this.replyCount = 0,
    this.viewCount = 0,
    this.readPermission,
    this.permissionMessage,
  });
}

class EqunPostSubmitResult {
  final int tid;
  final int? pid;
  final String? message;

  const EqunPostSubmitResult({required this.tid, this.pid, this.message});
}
