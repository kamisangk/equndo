import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/topic.dart';
import '../providers/equn_discuz_providers.dart';
import '../services/discuz/equn_discuz_models.dart';
import '../widgets/post/reply_sheet.dart';

class EqunThreadDetailPage extends ConsumerStatefulWidget {
  const EqunThreadDetailPage({
    super.key,
    required this.tid,
    this.initialTitle,
    this.scrollToPostNumber,
  });

  final int tid;
  final String? initialTitle;
  final int? scrollToPostNumber;

  @override
  ConsumerState<EqunThreadDetailPage> createState() =>
      _EqunThreadDetailPageState();
}

class _EqunThreadDetailPageState extends ConsumerState<EqunThreadDetailPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _targetPostKey = GlobalKey();
  int? _lastScrolledPostNumber;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(equnThreadDetailProvider(widget.tid));

    return Scaffold(
      appBar: AppBar(title: Text(widget.initialTitle ?? '主题 ${widget.tid}')),
      body: detail.when(
        data: (value) {
          _schedulePostScroll(value);
          return _DetailBody(
            detail: value,
            ref: ref,
            scrollController: _scrollController,
            targetPostNumber: widget.scrollToPostNumber,
            targetPostKey: _targetPostKey,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(error.toString(), textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  void _schedulePostScroll(EqunThreadDetail detail) {
    final target = widget.scrollToPostNumber;
    if (target == null || target == _lastScrolledPostNumber) return;

    final index = detail.posts.indexWhere((post) => post.position == target);
    if (index == -1) return;

    _lastScrolledPostNumber = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        final approximateOffset = (index * 220.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(approximateOffset);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final targetContext = _targetPostKey.currentContext;
        if (targetContext == null) return;
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      });
    });
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.ref,
    required this.scrollController,
    this.targetPostNumber,
    required this.targetPostKey,
  });

  final EqunThreadDetail detail;
  final WidgetRef ref;
  final ScrollController scrollController;
  final int? targetPostNumber;
  final GlobalKey targetPostKey;

  @override
  Widget build(BuildContext context) {
    if (detail.status == EqunThreadDetailStatus.permissionDenied) {
      return _PermissionDenied(detail: detail);
    }

    if (detail.posts.isEmpty) {
      return const Center(child: Text('没有可显示的帖子内容'));
    }

    return Stack(
      children: [
        ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: detail.posts.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _ThreadHeader(detail: detail);
            }
            final post = detail.posts[index - 1];
            return KeyedSubtree(
              key: post.position == targetPostNumber
                  ? targetPostKey
                  : ValueKey('equn-post-${post.pid}'),
              child: _PostCard(tid: detail.tid, post: post, ref: ref),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16 + MediaQuery.of(context).padding.bottom,
          child: FloatingActionButton(
            heroTag: 'equn-reply-topic-${detail.tid}',
            onPressed: () => _showEqunReplySheet(context, ref, detail.tid),
            child: const Icon(Icons.reply),
          ),
        ),
      ],
    );
  }
}

class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.detail});

  final EqunThreadDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                detail.title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                detail.permissionMessage ?? '权限不足或需要登录后查看',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _launchThreadUrl(detail.tid),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('在网页中打开'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _launchThreadUrl(int tid) async {
  final uri = Uri.parse('https://equn.com/forum/thread-$tid-1-1.html');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({required this.detail});

  final EqunThreadDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (detail.author != null && detail.author!.isNotEmpty) detail.author!,
      if (detail.replyCount > 0) '回复 ${detail.replyCount}',
      if (detail.viewCount > 0) '浏览 ${detail.viewCount}',
      if (detail.readPermission != null && detail.readPermission! > 0)
        '阅读权限 ${detail.readPermission}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            meta.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.tid, required this.post, required this.ref});

  final int tid;
  final EqunPost post;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text(
                    post.author.isEmpty
                        ? '?'
                        : post.author.characters.first.toUpperCase(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.author,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (post.dateline != null && post.dateline!.isNotEmpty)
                        Text(
                          post.dateline!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            HtmlWidget(
              post.message,
              textStyle: theme.textTheme.bodyMedium,
              onTapUrl: (url) => _launchUrl(url),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    _showEqunReplySheet(context, ref, tid, replyToPost: post),
                icon: const Icon(Icons.reply, size: 18),
                label: const Text('回复'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showEqunReplySheet(
  BuildContext context,
  WidgetRef ref,
  int tid, {
  EqunPost? replyToPost,
}) async {
  final result = await showReplySheet(
    context: context,
    topicId: tid,
    replyToPost: replyToPost == null ? null : _postFromEqunPost(replyToPost),
    initialContent: replyToPost == null
        ? null
        : '[quote]\n${replyToPost.message.replaceAll(RegExp(r'<[^>]+>'), '').trim()}\n[/quote]\n\n',
    useEqunComposer: true,
  );
  if (result != null) {
    final refreshed = ref.refresh(equnThreadDetailProvider(tid).future);
    await refreshed;
  }
}

Post _postFromEqunPost(EqunPost post) {
  final now = DateTime.now();
  return Post(
    id: post.pid,
    username: post.author,
    avatarTemplate: post.avatarUrl ?? '',
    cooked: post.message,
    postNumber: post.position,
    postType: 1,
    updatedAt: now,
    createdAt: now,
    likeCount: 0,
    replyCount: 0,
    userId: post.authorId,
  );
}

Future<bool> _launchUrl(String url) async {
  final uri = Uri.parse(url.replaceAll('&amp;', '&'));
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
