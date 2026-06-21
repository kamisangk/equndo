import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../providers/equn_discuz_providers.dart';
import '../services/discuz/equn_discuz_models.dart';
import '../utils/responsive.dart';
import 'equn_thread_detail_page.dart';

final _selectedForumIdProvider = StateProvider<int?>((ref) => null);
final _selectedForumNameProvider = StateProvider<String?>((ref) => null);

class EqunTopicsPage extends ConsumerWidget {
  const EqunTopicsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(equnGuideFilterProvider);
    final selectedForumId = ref.watch(_selectedForumIdProvider);
    final selectedForumName = ref.watch(_selectedForumNameProvider);
    final topics = ref.watch(equnGuideTopicsProvider);
    final groups = ref.watch(equnForumGroupsProvider);
    final forumTopics = selectedForumId == null
        ? null
        : ref.watch(equnForumTopicsProvider(selectedForumId));
    final showSideForums = !Responsive.isMobile(context);

    final content = Column(
      children: [
        _EqunHeader(
          filter: filter,
          selectedForumName: selectedForumName,
          onFilterChanged: (value) {
            ref.read(_selectedForumIdProvider.notifier).state = null;
            ref.read(_selectedForumNameProvider.notifier).state = null;
            ref.read(equnGuideFilterProvider.notifier).state = value;
          },
          onBackToGuide: selectedForumId == null
              ? null
              : () {
                  ref.read(_selectedForumIdProvider.notifier).state = null;
                  ref.read(_selectedForumNameProvider.notifier).state = null;
                },
        ),
        Expanded(
          child: _TopicContent(
            topics: topics,
            forumTopics: forumTopics,
            selectedForumName: selectedForumName,
          ),
        ),
        if (!showSideForums)
          SizedBox(
            height: 220,
            child: _ForumGroupsAsync(
              groups: groups,
              onForumSelected: (forum) {
                ref.read(_selectedForumIdProvider.notifier).state = forum.fid;
                ref.read(_selectedForumNameProvider.notifier).state =
                    forum.name;
              },
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('中国分布式计算论坛')),
      body: SafeArea(
        child: showSideForums
            ? Row(
                children: [
                  Expanded(child: content),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 300,
                    child: _ForumGroupsAsync(
                      groups: groups,
                      onForumSelected: (forum) {
                        ref.read(_selectedForumIdProvider.notifier).state =
                            forum.fid;
                        ref.read(_selectedForumNameProvider.notifier).state =
                            forum.name;
                      },
                    ),
                  ),
                ],
              )
            : content,
      ),
    );
  }
}

class _EqunHeader extends StatelessWidget {
  const _EqunHeader({
    required this.filter,
    required this.onFilterChanged,
    this.selectedForumName,
    this.onBackToGuide,
  });

  final EqunGuideFilter filter;
  final String? selectedForumName;
  final ValueChanged<EqunGuideFilter> onFilterChanged;
  final VoidCallback? onBackToGuide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<EqunGuideFilter>(
                    segments: [
                      for (final item in EqunGuideFilter.values)
                        ButtonSegment(value: item, label: Text(item.label)),
                    ],
                    selected: {filter},
                    onSelectionChanged: (value) {
                      onFilterChanged(value.single);
                    },
                  ),
                ),
              ],
            ),
            if (selectedForumName != null && onBackToGuide != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      selectedForumName!,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onBackToGuide,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('返回最新'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopicContent extends StatelessWidget {
  const _TopicContent({
    required this.topics,
    required this.forumTopics,
    required this.selectedForumName,
  });

  final AsyncValue<List<EqunTopicSummary>> topics;
  final AsyncValue<EqunForumTopicPage>? forumTopics;
  final String? selectedForumName;

  @override
  Widget build(BuildContext context) {
    final forumTopics = this.forumTopics;
    if (forumTopics != null) {
      return forumTopics.when(
        data: (page) => _TopicList(
          items: page.topics,
          emptyText: '${selectedForumName ?? page.forum.name}暂无主题',
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(message: error.toString()),
      );
    }

    return topics.when(
      data: (items) => _TopicList(items: items, emptyText: '没有相关主题'),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(message: error.toString()),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList({required this.items, required this.emptyText});

  final List<EqunTopicSummary> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyText));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return _TopicTile(topic: item);
      },
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic});

  final EqunTopicSummary topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (topic.forumName != null && topic.forumName!.isNotEmpty)
        topic.forumName!,
      topic.author,
      if (topic.lastPoster != null && topic.lastPoster!.isNotEmpty)
        '最后回复 ${topic.lastPoster}',
      if (topic.lastPostText != null && topic.lastPostText!.isNotEmpty)
        topic.lastPostText!,
      if (topic.readPermissionText != null) topic.readPermissionText!,
    ];

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        title: Text(topic.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            meta.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: _TopicStats(
          replyCount: topic.replyCount,
          viewCount: topic.viewCount,
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EqunThreadDetailPage(
                tid: topic.tid,
                initialTitle: topic.title,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopicStats extends StatelessWidget {
  const _TopicStats({required this.replyCount, required this.viewCount});

  final int replyCount;
  final int viewCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$replyCount',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '$viewCount',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ForumGroupsAsync extends StatelessWidget {
  const _ForumGroupsAsync({
    required this.groups,
    required this.onForumSelected,
  });

  final AsyncValue<List<EqunForumGroup>> groups;
  final ValueChanged<EqunForum> onForumSelected;

  @override
  Widget build(BuildContext context) {
    return groups.when(
      data: (items) =>
          _ForumGroups(groups: items, onForumSelected: onForumSelected),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(message: error.toString()),
    );
  }
}

class _ForumGroups extends StatelessWidget {
  const _ForumGroups({required this.groups, required this.onForumSelected});

  final List<EqunForumGroup> groups;
  final ValueChanged<EqunForum> onForumSelected;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Center(child: Text('暂无板块'));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final group in groups)
          ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              for (final forum in group.forums)
                ListTile(
                  dense: true,
                  title: Text(
                    forum.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('主题 ${forum.threads} · 帖子 ${forum.posts}'),
                  onTap: () => onForumSelected(forum),
                ),
            ],
          ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
