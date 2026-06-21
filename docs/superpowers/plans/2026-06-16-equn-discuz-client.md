# equn Discuz Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first usable equn Discuz browsing client for `https://equn.com/forum/`, with latest-reply/latest-thread home lists, forum groups, forum topic lists, and read-only thread details.

**Architecture:** Add a Discuz-specific service boundary beside the existing Discourse service. The first stage keeps old Discourse files in place for build stability, but the main browsing path uses new Equn Discuz models, parsers, providers, and pages.

**Tech Stack:** Flutter, Riverpod, Dio, `package:html`, flutter_test.

---

## File Structure

- Create `lib/services/discuz/equn_discuz_models.dart`
  - Discuz-specific value objects: guide filter, topic summary, forum group, forum, post, thread detail, permission status.
- Create `lib/services/discuz/equn_discuz_parser.dart`
  - Pure parsing functions for guide HTML and Discuz mobile API JSON.
- Create `lib/services/discuz/equn_discuz_service.dart`
  - Dio-backed service for `https://equn.com/forum/`, delegating parsing to `EqunDiscuzParser`.
- Create `lib/providers/equn_discuz_providers.dart`
  - Riverpod providers for guide filter, guide topics, forum groups, forum topics, and thread detail.
- Create `lib/pages/equn_topics_page.dart`
  - New read-only home page for equn latest lists and forum side/bottom selection.
- Create `lib/pages/equn_thread_detail_page.dart`
  - New read-only thread detail page using Discuz detail provider.
- Modify `lib/pages/topics_screen.dart`
  - Use `EqunTopicsPage` / `EqunThreadDetailPage` instead of Discourse `TopicsPage` / `TopicDetailPage` for the home browsing path.
- Modify `lib/navigation/nav_entry_registry.dart`
  - Hide Discourse-only bottom-nav entries in the first stage.
- Modify `lib/constants.dart`
  - Set app forum base URL to `https://equn.com/forum` only where still needed by shared link helpers.
- Test `test/services/discuz/equn_discuz_parser_test.dart`
  - Parser unit tests with local fixtures.
- Test `test/providers/equn_discuz_providers_test.dart`
  - Provider tests using fake service overrides.
- Test `test/pages/equn_topics_page_test.dart`
  - Widget tests for home filter labels and permission state routing.

## Task 1: Discuz Models And Parser Tests

**Files:**
- Create: `test/services/discuz/equn_discuz_parser_test.dart`
- Create: `lib/services/discuz/equn_discuz_models.dart`
- Create: `lib/services/discuz/equn_discuz_parser.dart`

- [ ] **Step 1: Write failing parser tests**

Create `test/services/discuz/equn_discuz_parser_test.dart` with:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discuz/equn_discuz_models.dart';
import 'package:fluxdo/services/discuz/equn_discuz_parser.dart';

void main() {
  group('EqunDiscuzParser', () {
    test('parses guide latest replies html rows', () {
      const html = '''
<div id="threadlist">
  <table><tbody id="normalthread_49405">
    <tr>
      <td class="icn"><a href="thread-49405-1-1.html"></a></td>
      <th class="common">
        <a href="thread-49405-1-1.html" target="_blank" class="xst">The BOINC Pentathlon 2026</a>
      </th>
      <td class="by"><a href="forum-513-1.html">项目竞赛活动区</a></td>
      <td class="by"><cite><a href="home.php?mod=space&amp;uid=246">freestman</a></cite><em><span>2026-5-13</span></em></td>
      <td class="num"><a href="thread-49405-1-1.html" class="xi2">7</a><em>150</em></td>
      <td class="by"><cite><a href="home.php?mod=space&amp;username=zflowers">zflowers</a></cite><em><a href="forum.php?mod=redirect&amp;tid=49405&amp;goto=lastpost#lastpost">2026-6-8 21:50</a></em></td>
    </tr>
  </tbody></table>
</div>
''';

      final topics = EqunDiscuzParser.parseGuideTopics(html);

      expect(topics, hasLength(1));
      expect(topics.single.tid, 49405);
      expect(topics.single.title, 'The BOINC Pentathlon 2026');
      expect(topics.single.forumId, 513);
      expect(topics.single.forumName, '项目竞赛活动区');
      expect(topics.single.author, 'freestman');
      expect(topics.single.replyCount, 7);
      expect(topics.single.viewCount, 150);
      expect(topics.single.lastPoster, 'zflowers');
      expect(topics.single.lastPostText, '2026-6-8 21:50');
      expect(topics.single.url, 'https://equn.com/forum/thread-49405-1-1.html');
    });

    test('keeps read permission text from guide title cell', () {
      const html = '''
<div id="threadlist">
  <table><tbody id="normalthread_49424">
    <tr>
      <td class="icn"><a href="thread-49424-1-1.html"></a></td>
      <th class="common">
        <a href="thread-49424-1-1.html" class="xst">考虑退出机制</a> - [阅读权限 <span class="xw1">35</span>]
      </th>
      <td class="by"><a href="forum-61-1.html">站务区</a></td>
      <td class="by"><cite><a>Gavin.H</a></cite><em><span>前天&nbsp;19:03</span></em></td>
      <td class="num"><a class="xi2">0</a><em>0</em></td>
      <td class="by"><cite><a>Gavin.H</a></cite><em><a>前天&nbsp;19:03</a></em></td>
    </tr>
  </tbody></table>
</div>
''';

      final topics = EqunDiscuzParser.parseGuideTopics(html);

      expect(topics.single.readPermissionText, '阅读权限 35');
    });

    test('parses forumindex groups and forums json', () {
      final json = jsonDecode('''
{
  "Variables": {
    "catlist": [
      {"fid": "509", "name": "综合板块", "forums": ["510", "41"]}
    ],
    "forumlist": [
      {"fid": "510", "name": "分布式计算项目新闻发布区", "threads": "226", "posts": "4442", "todayposts": "0", "icon": "https://equn.com/forum/data/news.gif"},
      {"fid": "41", "name": "分布式计算综合讨论区", "threads": "907", "posts": "9553", "todayposts": "0"}
    ]
  }
}
''') as Map<String, dynamic>;

      final groups = EqunDiscuzParser.parseForumGroups(json);

      expect(groups, hasLength(1));
      expect(groups.single.fid, 509);
      expect(groups.single.name, '综合板块');
      expect(groups.single.forums.map((forum) => forum.fid), [510, 41]);
      expect(groups.single.forums.first.iconUrl, 'https://equn.com/forum/data/news.gif');
    });

    test('parses forumdisplay topic list json', () {
      final json = jsonDecode('''
{
  "Variables": {
    "forum": {"fid": "61", "name": "站务区"},
    "forum_threadlist": [
      {
        "tid": "49422",
        "fid": "61",
        "readperm": "30",
        "author": "duligavin",
        "authorid": "11501",
        "subject": "找回密码邮件报错",
        "dateline": "2026-5-30",
        "lastpost": "2026-6-1 09:29",
        "lastposter": "Gavin.H",
        "views": "7",
        "replies": "2",
        "displayorder": "0",
        "digest": "0",
        "attachment": "0"
      }
    ],
    "page": "1",
    "tpp": "20"
  }
}
''') as Map<String, dynamic>;

      final page = EqunDiscuzParser.parseForumTopicPage(json);

      expect(page.forum.fid, 61);
      expect(page.forum.name, '站务区');
      expect(page.topics.single.tid, 49422);
      expect(page.topics.single.title, '找回密码邮件报错');
      expect(page.topics.single.readPermission, 30);
      expect(page.topics.single.replyCount, 2);
      expect(page.page, 1);
      expect(page.pageSize, 20);
    });

    test('parses viewthread permission denied response', () {
      final json = jsonDecode('''
{
  "Variables": {
    "thread": {"tid": "49424", "fid": "61", "subject": "考虑退出机制", "readperm": "35"},
    "postlist": []
  },
  "Message": {
    "messageval": "thread_nopermission//1",
    "messagestr": "mobile:thread_nopermission"
  }
}
''') as Map<String, dynamic>;

      final detail = EqunDiscuzParser.parseThreadDetail(json);

      expect(detail.status, EqunThreadDetailStatus.permissionDenied);
      expect(detail.tid, 49424);
      expect(detail.title, '考虑退出机制');
      expect(detail.permissionMessage, contains('权限不足'));
      expect(detail.posts, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
flutter test test/services/discuz/equn_discuz_parser_test.dart
```

Expected: FAIL because `package:fluxdo/services/discuz/equn_discuz_models.dart` and parser classes do not exist.

- [ ] **Step 3: Add minimal Discuz models**

Create `lib/services/discuz/equn_discuz_models.dart`:

```dart
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

enum EqunThreadDetailStatus {
  ok,
  permissionDenied,
}

class EqunPost {
  final int pid;
  final String author;
  final int? authorId;
  final String message;
  final String? avatarUrl;
  final String? dateline;

  const EqunPost({
    required this.pid,
    required this.author,
    required this.message,
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
```

- [ ] **Step 4: Add minimal parser implementation**

Create `lib/services/discuz/equn_discuz_parser.dart`:

```dart
import 'package:html/parser.dart' as html_parser;

import 'equn_discuz_models.dart';

class EqunDiscuzParser {
  static const String baseUrl = 'https://equn.com/forum/';

  static List<EqunTopicSummary> parseGuideTopics(String html) {
    final document = html_parser.parse(html);
    final rows = document.querySelectorAll('#threadlist tbody[id^="normalthread_"]');
    return rows.map((tbody) {
      final id = tbody.id;
      final tid = _firstInt(id) ?? _firstInt(tbody.querySelector('a[href*="thread-"]')?.attributes['href']);
      if (tid == null) {
        throw const FormatException('无法解析主题 id');
      }
      final titleLink = tbody.querySelector('a.xst');
      final title = _clean(titleLink?.text ?? '');
      final titleCellText = _clean(tbody.querySelector('th')?.text ?? '');
      final byCells = tbody.querySelectorAll('td.by');
      final forumLink = byCells.isNotEmpty ? byCells[0].querySelector('a[href*="forum-"]') : null;
      final authorCell = byCells.length > 1 ? byCells[1] : null;
      final lastPostCell = byCells.length > 2 ? byCells[2] : null;
      final numCell = tbody.querySelector('td.num');
      final numAnchor = numCell?.querySelector('a');
      final numEm = numCell?.querySelector('em');
      final readPermission = _readPermission(titleCellText);

      return EqunTopicSummary(
        tid: tid,
        title: title,
        forumId: _firstInt(forumLink?.attributes['href']),
        forumName: _clean(forumLink?.text ?? ''),
        author: _clean(authorCell?.querySelector('cite a')?.text ?? ''),
        createdText: _clean(authorCell?.querySelector('em')?.text ?? ''),
        replyCount: _parseCompactInt(numAnchor?.text),
        viewCount: _parseCompactInt(numEm?.text),
        lastPoster: _clean(lastPostCell?.querySelector('cite a')?.text ?? ''),
        lastPostText: _clean(lastPostCell?.querySelector('em')?.text ?? ''),
        readPermission: readPermission,
        readPermissionText: readPermission == null ? null : '阅读权限 $readPermission',
        url: _absolute(titleLink?.attributes['href'] ?? 'thread-$tid-1-1.html'),
      );
    }).toList();
  }

  static List<EqunForumGroup> parseForumGroups(Map<String, dynamic> json) {
    final variables = _variables(json);
    final forumList = (variables['forumlist'] as List<dynamic>? ?? const []);
    final forumsById = <int, EqunForum>{};
    for (final item in forumList) {
      if (item is! Map<String, dynamic>) continue;
      final forum = _forumFromJson(item);
      forumsById[forum.fid] = forum;
    }

    return (variables['catlist'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
      final ids = (item['forums'] as List<dynamic>? ?? const [])
          .map((id) => _parseInt(id))
          .whereType<int>()
          .toList();
      return EqunForumGroup(
        fid: _parseInt(item['fid']) ?? 0,
        name: _clean(item['name']?.toString() ?? ''),
        forums: ids.map((id) => forumsById[id]).whereType<EqunForum>().toList(),
      );
    }).toList();
  }

  static EqunForumTopicPage parseForumTopicPage(Map<String, dynamic> json) {
    final variables = _variables(json);
    final forumJson = variables['forum'] as Map<String, dynamic>? ?? const {};
    final forum = _forumFromJson(forumJson);
    final topics = (variables['forum_threadlist'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) => _topicFromForumJson(item, defaultForum: forum))
        .toList();
    return EqunForumTopicPage(
      forum: forum,
      topics: topics,
      page: _parseInt(variables['page']) ?? 1,
      pageSize: _parseInt(variables['tpp']) ?? topics.length,
    );
  }

  static EqunThreadDetail parseThreadDetail(Map<String, dynamic> json) {
    final variables = _variables(json);
    final thread = variables['thread'] as Map<String, dynamic>? ?? const {};
    final message = json['Message'] as Map<String, dynamic>?;
    final messageVal = message?['messageval']?.toString() ?? '';
    final permissionDenied = messageVal.startsWith('thread_nopermission');
    final posts = (variables['postlist'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_postFromJson)
        .toList();

    return EqunThreadDetail(
      tid: _parseInt(thread['tid']) ?? 0,
      fid: _parseInt(thread['fid']),
      title: _clean(thread['subject']?.toString() ?? ''),
      author: _clean(thread['author']?.toString() ?? ''),
      replyCount: _parseInt(thread['replies']) ?? 0,
      viewCount: _parseInt(thread['views']) ?? 0,
      readPermission: _parseInt(thread['readperm']),
      status: permissionDenied ? EqunThreadDetailStatus.permissionDenied : EqunThreadDetailStatus.ok,
      permissionMessage: permissionDenied ? '权限不足或需要登录后查看' : null,
      posts: posts,
    );
  }

  static Map<String, dynamic> _variables(Map<String, dynamic> json) {
    return json['Variables'] as Map<String, dynamic>? ?? const {};
  }

  static EqunForum _forumFromJson(Map<String, dynamic> json) {
    return EqunForum(
      fid: _parseInt(json['fid']) ?? 0,
      name: _clean(json['name']?.toString() ?? ''),
      threads: _parseInt(json['threads']) ?? _parseInt(json['threadcount']) ?? 0,
      posts: _parseInt(json['posts']) ?? 0,
      todayPosts: _parseInt(json['todayposts']) ?? 0,
      iconUrl: json['icon']?.toString(),
      description: json['description']?.toString(),
      parentFid: _parseInt(json['fup']),
    );
  }

  static EqunTopicSummary _topicFromForumJson(Map<String, dynamic> json, {required EqunForum defaultForum}) {
    final tid = _parseInt(json['tid']) ?? 0;
    final readPermission = _parseInt(json['readperm']);
    return EqunTopicSummary(
      tid: tid,
      forumId: _parseInt(json['fid']) ?? defaultForum.fid,
      forumName: defaultForum.name,
      title: _clean(json['subject']?.toString() ?? ''),
      author: _clean(json['author']?.toString() ?? ''),
      createdText: _clean(json['dateline']?.toString() ?? ''),
      replyCount: _parseInt(json['replies']) ?? 0,
      viewCount: _parseInt(json['views']) ?? 0,
      lastPoster: _clean(json['lastposter']?.toString() ?? ''),
      lastPostText: _clean(json['lastpost']?.toString() ?? ''),
      readPermission: readPermission,
      readPermissionText: readPermission == null || readPermission == 0 ? null : '阅读权限 $readPermission',
      url: _absolute('thread-$tid-1-1.html'),
      pinned: (_parseInt(json['displayorder']) ?? 0) > 0,
      digest: (_parseInt(json['digest']) ?? 0) > 0,
    );
  }

  static EqunPost _postFromJson(Map<String, dynamic> json) {
    return EqunPost(
      pid: _parseInt(json['pid']) ?? 0,
      author: _clean(json['author']?.toString() ?? ''),
      authorId: _parseInt(json['authorid']),
      message: json['message']?.toString() ?? '',
      avatarUrl: json['avatar']?.toString(),
      dateline: json['dateline']?.toString(),
    );
  }

  static int? _readPermission(String text) {
    final match = RegExp(r'阅读权限\s*(\d+)').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static int? _firstInt(String? text) {
    if (text == null) return null;
    final match = RegExp(r'\d+').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  static int _parseCompactInt(String? value) {
    final text = _clean(value ?? '');
    if (text.isEmpty) return 0;
    final exact = int.tryParse(text);
    if (exact != null) return exact;
    final match = RegExp(r'(\d+)万').firstMatch(text);
    if (match != null) return int.parse(match.group(1)!) * 10000;
    return 0;
  }

  static String _absolute(String href) {
    return Uri.parse(baseUrl).resolve(href.replaceAll('&amp;', '&')).toString();
  }

  static String _clean(String value) {
    return value.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
```

- [ ] **Step 5: Run parser tests to verify GREEN**

Run:

```bash
flutter test test/services/discuz/equn_discuz_parser_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit parser foundation**

```bash
git add lib/services/discuz test/services/discuz/equn_discuz_parser_test.dart
git commit -m "feat: add equn discuz parser"
```

## Task 2: Equn Discuz Service

**Files:**
- Create: `lib/services/discuz/equn_discuz_service.dart`
- Test: `test/services/discuz/equn_discuz_service_test.dart`

- [ ] **Step 1: Write failing service tests with fake adapter**

Create `test/services/discuz/equn_discuz_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discuz/equn_discuz_models.dart';
import 'package:fluxdo/services/discuz/equn_discuz_service.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }
}

void main() {
  test('fetchGuideTopics requests latest replies guide view by default', () async {
    final adapter = FakeAdapter((options) {
      expect(options.path, '/forum.php');
      expect(options.queryParameters['mod'], 'guide');
      expect(options.queryParameters['view'], 'new');
      return ResponseBody.fromString('<div id="threadlist"></div>', 200, headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      });
    });
    final service = EqunDiscuzService(dio: Dio(BaseOptions(baseUrl: EqunDiscuzService.baseUrl))..httpClientAdapter = adapter);

    final topics = await service.fetchGuideTopics(EqunGuideFilter.latestReplies);

    expect(topics, isEmpty);
  });

  test('fetchGuideTopics requests latest thread guide view', () async {
    final adapter = FakeAdapter((options) {
      expect(options.queryParameters['view'], 'newthread');
      return ResponseBody.fromString('<div id="threadlist"></div>', 200);
    });
    final service = EqunDiscuzService(dio: Dio(BaseOptions(baseUrl: EqunDiscuzService.baseUrl))..httpClientAdapter = adapter);

    await service.fetchGuideTopics(EqunGuideFilter.latestThreads);
  });

  test('fetchForumGroups parses mobile forumindex response', () async {
    final adapter = FakeAdapter((options) {
      expect(options.path, '/api/mobile/index.php');
      expect(options.queryParameters['module'], 'forumindex');
      return ResponseBody.fromString(jsonEncode({
        'Variables': {
          'catlist': [
            {'fid': '6', 'name': '站务板块', 'forums': ['61']},
          ],
          'forumlist': [
            {'fid': '61', 'name': '站务区', 'threads': '847', 'posts': '10902'},
          ],
        },
      }), 200, headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      });
    });
    final service = EqunDiscuzService(dio: Dio(BaseOptions(baseUrl: EqunDiscuzService.baseUrl))..httpClientAdapter = adapter);

    final groups = await service.fetchForumGroups();

    expect(groups.single.name, '站务板块');
    expect(groups.single.forums.single.name, '站务区');
  });

  test('fetchThreadDetail parses permission denied detail response', () async {
    final adapter = FakeAdapter((options) {
      expect(options.queryParameters['module'], 'viewthread');
      expect(options.queryParameters['tid'], 49424);
      return ResponseBody.fromString(jsonEncode({
        'Variables': {
          'thread': {'tid': '49424', 'fid': '61', 'subject': '考虑退出机制', 'readperm': '35'},
          'postlist': [],
        },
        'Message': {'messageval': 'thread_nopermission//1'},
      }), 200);
    });
    final service = EqunDiscuzService(dio: Dio(BaseOptions(baseUrl: EqunDiscuzService.baseUrl))..httpClientAdapter = adapter);

    final detail = await service.fetchThreadDetail(49424);

    expect(detail.status, EqunThreadDetailStatus.permissionDenied);
  });
}
```

- [ ] **Step 2: Run service tests to verify RED**

Run:

```bash
flutter test test/services/discuz/equn_discuz_service_test.dart
```

Expected: FAIL because `EqunDiscuzService` does not exist.

- [ ] **Step 3: Implement EqunDiscuzService**

Create `lib/services/discuz/equn_discuz_service.dart`:

```dart
import 'package:dio/dio.dart';

import '../../constants.dart';
import 'equn_discuz_models.dart';
import 'equn_discuz_parser.dart';

class EqunDiscuzService {
  static const String baseUrl = 'https://equn.com/forum/';

  EqunDiscuzService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                headers: {
                  'Accept': 'application/json, text/html, */*; q=0.01',
                  'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
                  'User-Agent': AppConstants.userAgent,
                },
              ),
            );

  final Dio _dio;

  Future<List<EqunTopicSummary>> fetchGuideTopics(EqunGuideFilter filter, {int page = 1}) async {
    final response = await _dio.get<String>(
      '/forum.php',
      queryParameters: {
        'mod': 'guide',
        'view': filter.view,
        if (page > 1) 'page': page,
      },
      options: Options(responseType: ResponseType.plain),
    );
    return EqunDiscuzParser.parseGuideTopics(response.data ?? '');
  }

  Future<List<EqunForumGroup>> fetchForumGroups() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/mobile/index.php',
      queryParameters: {
        'version': 4,
        'module': 'forumindex',
      },
    );
    return EqunDiscuzParser.parseForumGroups(response.data ?? const {});
  }

  Future<EqunForumTopicPage> fetchForumTopics(int fid, {int page = 1}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/mobile/index.php',
      queryParameters: {
        'version': 4,
        'module': 'forumdisplay',
        'fid': fid,
        'page': page,
      },
    );
    return EqunDiscuzParser.parseForumTopicPage(response.data ?? const {});
  }

  Future<EqunThreadDetail> fetchThreadDetail(int tid, {int page = 1}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/mobile/index.php',
      queryParameters: {
        'version': 4,
        'module': 'viewthread',
        'tid': tid,
        'page': page,
      },
    );
    return EqunDiscuzParser.parseThreadDetail(response.data ?? const {});
  }
}
```

- [ ] **Step 4: Run service tests to verify GREEN**

Run:

```bash
flutter test test/services/discuz/equn_discuz_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit service**

```bash
git add lib/services/discuz/equn_discuz_service.dart test/services/discuz/equn_discuz_service_test.dart
git commit -m "feat: add equn discuz service"
```

## Task 3: Equn Discuz Providers

**Files:**
- Create: `lib/providers/equn_discuz_providers.dart`
- Test: `test/providers/equn_discuz_providers_test.dart`

- [ ] **Step 1: Write failing provider tests**

Create `test/providers/equn_discuz_providers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/equn_discuz_providers.dart';
import 'package:fluxdo/services/discuz/equn_discuz_models.dart';
import 'package:fluxdo/services/discuz/equn_discuz_service.dart';

class FakeEqunDiscuzService extends EqunDiscuzService {
  EqunGuideFilter? requestedFilter;
  int? requestedForumId;
  int? requestedThreadId;

  FakeEqunDiscuzService() : super();

  @override
  Future<List<EqunTopicSummary>> fetchGuideTopics(EqunGuideFilter filter, {int page = 1}) async {
    requestedFilter = filter;
    return [
      EqunTopicSummary(
        tid: 1,
        title: filter.label,
        author: 'author',
        replyCount: 0,
        viewCount: 0,
        url: 'https://equn.com/forum/thread-1-1-1.html',
      ),
    ];
  }

  @override
  Future<List<EqunForumGroup>> fetchForumGroups() async {
    return [
      const EqunForumGroup(
        fid: 6,
        name: '站务板块',
        forums: [EqunForum(fid: 61, name: '站务区')],
      ),
    ];
  }

  @override
  Future<EqunForumTopicPage> fetchForumTopics(int fid, {int page = 1}) async {
    requestedForumId = fid;
    return EqunForumTopicPage(
      forum: EqunForum(fid: fid, name: '站务区'),
      topics: [
        EqunTopicSummary(
          tid: 49422,
          title: '找回密码邮件报错',
          author: 'duligavin',
          replyCount: 2,
          viewCount: 7,
          url: 'https://equn.com/forum/thread-49422-1-1.html',
        ),
      ],
      page: page,
      pageSize: 20,
    );
  }

  @override
  Future<EqunThreadDetail> fetchThreadDetail(int tid, {int page = 1}) async {
    requestedThreadId = tid;
    return EqunThreadDetail(
      tid: tid,
      title: '考虑退出机制',
      status: EqunThreadDetailStatus.permissionDenied,
      permissionMessage: '权限不足或需要登录后查看',
      posts: const [],
    );
  }
}

void main() {
  test('guide filter defaults to latest replies', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(equnGuideFilterProvider), EqunGuideFilter.latestReplies);
  });

  test('guide topics provider uses selected filter', () async {
    final fake = FakeEqunDiscuzService();
    final container = ProviderContainer(overrides: [
      equnDiscuzServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    container.read(equnGuideFilterProvider.notifier).state = EqunGuideFilter.latestThreads;
    final topics = await container.read(equnGuideTopicsProvider.future);

    expect(fake.requestedFilter, EqunGuideFilter.latestThreads);
    expect(topics.single.title, '最新发表');
  });

  test('forum topics provider requests fid', () async {
    final fake = FakeEqunDiscuzService();
    final container = ProviderContainer(overrides: [
      equnDiscuzServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final page = await container.read(equnForumTopicsProvider(61).future);

    expect(fake.requestedForumId, 61);
    expect(page.topics.single.tid, 49422);
  });

  test('thread detail provider requests tid', () async {
    final fake = FakeEqunDiscuzService();
    final container = ProviderContainer(overrides: [
      equnDiscuzServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final detail = await container.read(equnThreadDetailProvider(49424).future);

    expect(fake.requestedThreadId, 49424);
    expect(detail.status, EqunThreadDetailStatus.permissionDenied);
  });
}
```

- [ ] **Step 2: Run provider tests to verify RED**

Run:

```bash
flutter test test/providers/equn_discuz_providers_test.dart
```

Expected: FAIL because providers do not exist.

- [ ] **Step 3: Implement providers**

Create `lib/providers/equn_discuz_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/discuz/equn_discuz_models.dart';
import '../services/discuz/equn_discuz_service.dart';

final equnDiscuzServiceProvider = Provider<EqunDiscuzService>((ref) {
  return EqunDiscuzService();
});

final equnGuideFilterProvider = StateProvider<EqunGuideFilter>((ref) {
  return EqunGuideFilter.latestReplies;
});

final equnGuideTopicsProvider = FutureProvider<List<EqunTopicSummary>>((ref) async {
  final service = ref.watch(equnDiscuzServiceProvider);
  final filter = ref.watch(equnGuideFilterProvider);
  return service.fetchGuideTopics(filter);
});

final equnForumGroupsProvider = FutureProvider<List<EqunForumGroup>>((ref) async {
  final service = ref.watch(equnDiscuzServiceProvider);
  return service.fetchForumGroups();
});

final equnForumTopicsProvider = FutureProvider.family<EqunForumTopicPage, int>((ref, fid) async {
  final service = ref.watch(equnDiscuzServiceProvider);
  return service.fetchForumTopics(fid);
});

final equnThreadDetailProvider = FutureProvider.family<EqunThreadDetail, int>((ref, tid) async {
  final service = ref.watch(equnDiscuzServiceProvider);
  return service.fetchThreadDetail(tid);
});
```

- [ ] **Step 4: Run provider tests to verify GREEN**

Run:

```bash
flutter test test/providers/equn_discuz_providers_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit providers**

```bash
git add lib/providers/equn_discuz_providers.dart test/providers/equn_discuz_providers_test.dart
git commit -m "feat: add equn discuz providers"
```

## Task 4: Read-Only Equn Home Page

**Files:**
- Create: `lib/pages/equn_topics_page.dart`
- Test: `test/pages/equn_topics_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

Create `test/pages/equn_topics_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/equn_topics_page.dart';
import 'package:fluxdo/providers/equn_discuz_providers.dart';
import 'package:fluxdo/services/discuz/equn_discuz_models.dart';
import 'package:fluxdo/services/discuz/equn_discuz_service.dart';

class FakeEqunDiscuzService extends EqunDiscuzService {
  FakeEqunDiscuzService() : super();

  @override
  Future<List<EqunTopicSummary>> fetchGuideTopics(EqunGuideFilter filter, {int page = 1}) async {
    return [
      EqunTopicSummary(
        tid: filter == EqunGuideFilter.latestReplies ? 49405 : 49424,
        title: filter == EqunGuideFilter.latestReplies ? 'The BOINC Pentathlon 2026' : '考虑退出机制',
        author: 'freestman',
        forumId: 513,
        forumName: '项目竞赛活动区',
        replyCount: 7,
        viewCount: 150,
        lastPoster: 'zflowers',
        lastPostText: '2026-6-8 21:50',
        url: 'https://equn.com/forum/thread-49405-1-1.html',
      ),
    ];
  }

  @override
  Future<List<EqunForumGroup>> fetchForumGroups() async {
    return [
      const EqunForumGroup(
        fid: 509,
        name: '综合板块',
        forums: [
          EqunForum(fid: 513, name: '项目竞赛活动区', threads: 612, posts: 22868),
        ],
      ),
    ];
  }
}

void main() {
  testWidgets('shows only latest replies and latest threads filter buttons', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equnDiscuzServiceProvider.overrideWithValue(FakeEqunDiscuzService()),
        ],
        child: const MaterialApp(home: EqunTopicsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最新回复'), findsOneWidget);
    expect(find.text('最新发表'), findsOneWidget);
    expect(find.text('The BOINC Pentathlon 2026'), findsOneWidget);
    expect(find.text('新话题'), findsNothing);
    expect(find.text('未读'), findsNothing);
  });

  testWidgets('switches to latest threads filter', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equnDiscuzServiceProvider.overrideWithValue(FakeEqunDiscuzService()),
        ],
        child: const MaterialApp(home: EqunTopicsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('最新发表'));
    await tester.pumpAndSettle();

    expect(find.text('考虑退出机制'), findsOneWidget);
  });

  testWidgets('shows equn forum group and forum entries', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equnDiscuzServiceProvider.overrideWithValue(FakeEqunDiscuzService()),
        ],
        child: const MaterialApp(home: EqunTopicsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('综合板块'), findsOneWidget);
    expect(find.text('项目竞赛活动区'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run widget tests to verify RED**

Run:

```bash
flutter test test/pages/equn_topics_page_test.dart
```

Expected: FAIL because `EqunTopicsPage` does not exist.

- [ ] **Step 3: Implement simple read-only EqunTopicsPage**

Create `lib/pages/equn_topics_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/equn_discuz_providers.dart';
import '../services/discuz/equn_discuz_models.dart';
import 'equn_thread_detail_page.dart';

class EqunTopicsPage extends ConsumerWidget {
  const EqunTopicsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(equnGuideFilterProvider);
    final topics = ref.watch(equnGuideTopicsProvider);
    final groups = ref.watch(equnForumGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('中国分布式计算论坛'),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<EqunGuideFilter>(
                    segments: EqunGuideFilter.values
                        .map((item) => ButtonSegment(value: item, label: Text(item.label)))
                        .toList(),
                    selected: {filter},
                    onSelectionChanged: (value) {
                      ref.read(equnGuideFilterProvider.notifier).state = value.single;
                    },
                  ),
                ),
                Expanded(
                  child: topics.when(
                    data: (items) => _TopicList(items: items),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _ErrorState(message: error.toString()),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 280,
            child: groups.when(
              data: (items) => _ForumGroups(groups: items),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(message: error.toString()),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList({required this.items});

  final List<EqunTopicSummary> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('没有相关主题'));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(item.title),
          subtitle: Text([
            if (item.forumName != null && item.forumName!.isNotEmpty) item.forumName!,
            item.author,
            if (item.lastPostText != null && item.lastPostText!.isNotEmpty) '最后发表 ${item.lastPostText}',
            if (item.readPermissionText != null) item.readPermissionText!,
          ].join(' · ')),
          trailing: Text('${item.replyCount}/${item.viewCount}'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EqunThreadDetailPage(tid: item.tid, initialTitle: item.title),
              ),
            );
          },
        );
      },
    );
  }
}

class _ForumGroups extends StatelessWidget {
  const _ForumGroups({required this.groups});

  final List<EqunForumGroup> groups;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final group in groups)
          ExpansionTile(
            initiallyExpanded: true,
            title: Text(group.name),
            children: [
              for (final forum in group.forums)
                ListTile(
                  dense: true,
                  title: Text(forum.name),
                  subtitle: Text('主题 ${forum.threads} · 帖子 ${forum.posts}'),
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
```

- [ ] **Step 4: Add placeholder EqunThreadDetailPage for compilation**

Create `lib/pages/equn_thread_detail_page.dart`:

```dart
import 'package:flutter/material.dart';

class EqunThreadDetailPage extends StatelessWidget {
  const EqunThreadDetailPage({
    super.key,
    required this.tid,
    this.initialTitle,
  });

  final int tid;
  final String? initialTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(initialTitle ?? '主题 $tid')),
      body: const SizedBox.shrink(),
    );
  }
}
```

- [ ] **Step 5: Run widget tests to verify GREEN**

Run:

```bash
flutter test test/pages/equn_topics_page_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit home page**

```bash
git add lib/pages/equn_topics_page.dart lib/pages/equn_thread_detail_page.dart test/pages/equn_topics_page_test.dart
git commit -m "feat: add equn topics page"
```

## Task 5: Forum Topic Selection

**Files:**
- Modify: `lib/pages/equn_topics_page.dart`
- Test: `test/pages/equn_topics_page_test.dart`

- [ ] **Step 1: Extend widget test for selecting a forum**

Insert this test inside the existing `main()` function in `test/pages/equn_topics_page_test.dart`:

```dart
testWidgets('selecting a forum shows that forum topic list', (tester) async {
  final fake = _ForumTopicFakeService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        equnDiscuzServiceProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: EqunTopicsPage()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('站务区'));
  await tester.pumpAndSettle();

  expect(fake.requestedForumId, 61);
  expect(find.text('找回密码邮件报错'), findsOneWidget);
});
```

Add this fake service class at the top level of `test/pages/equn_topics_page_test.dart`, after `main()` or before it:

```dart
class _ForumTopicFakeService extends FakeEqunDiscuzService {
  int? requestedForumId;

  @override
  Future<List<EqunForumGroup>> fetchForumGroups() async {
    return [
      const EqunForumGroup(
        fid: 6,
        name: '站务板块',
        forums: [EqunForum(fid: 61, name: '站务区', threads: 847, posts: 10902)],
      ),
    ];
  }

  @override
  Future<EqunForumTopicPage> fetchForumTopics(int fid, {int page = 1}) async {
    requestedForumId = fid;
    return EqunForumTopicPage(
      forum: const EqunForum(fid: 61, name: '站务区'),
      topics: [
        EqunTopicSummary(
          tid: 49422,
          title: '找回密码邮件报错',
          author: 'duligavin',
          replyCount: 2,
          viewCount: 7,
          url: 'https://equn.com/forum/thread-49422-1-1.html',
        ),
      ],
      page: 1,
      pageSize: 20,
    );
  }
}
```

- [ ] **Step 2: Run page tests to verify RED**

Run:

```bash
flutter test test/pages/equn_topics_page_test.dart
```

Expected: FAIL because tapping a forum does not change the main list yet.

- [ ] **Step 3: Add selected forum state and display forum topics**

Modify `lib/pages/equn_topics_page.dart`:

```dart
final _selectedForumIdProvider = StateProvider<int?>((ref) => null);
final _selectedForumNameProvider = StateProvider<String?>((ref) => null);
```

In `EqunTopicsPage.build`, read:

```dart
final selectedForumId = ref.watch(_selectedForumIdProvider);
final selectedForumName = ref.watch(_selectedForumNameProvider);
final forumTopics = selectedForumId == null ? null : ref.watch(equnForumTopicsProvider(selectedForumId));
```

Replace the main `Expanded` data branch with logic:

```dart
Expanded(
  child: selectedForumId == null
      ? topics.when(
          data: (items) => _TopicList(items: items),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(message: error.toString()),
        )
      : forumTopics!.when(
          data: (page) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(selectedForumName ?? page.forum.name, style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(
                      onPressed: () {
                        ref.read(_selectedForumIdProvider.notifier).state = null;
                        ref.read(_selectedForumNameProvider.notifier).state = null;
                      },
                      child: const Text('返回最新'),
                    ),
                  ],
                ),
              ),
              Expanded(child: _TopicList(items: page.topics)),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(message: error.toString()),
        ),
)
```

Pass `onForumSelected` into `_ForumGroups`:

```dart
_ForumGroups(
  groups: items,
  onForumSelected: (forum) {
    ref.read(_selectedForumIdProvider.notifier).state = forum.fid;
    ref.read(_selectedForumNameProvider.notifier).state = forum.name;
  },
)
```

Update `_ForumGroups` constructor and ListTile:

```dart
class _ForumGroups extends StatelessWidget {
  const _ForumGroups({required this.groups, required this.onForumSelected});

  final List<EqunForumGroup> groups;
  final ValueChanged<EqunForum> onForumSelected;
```

```dart
onTap: () => onForumSelected(forum),
```

- [ ] **Step 4: Run page tests to verify GREEN**

Run:

```bash
flutter test test/pages/equn_topics_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit forum selection**

```bash
git add lib/pages/equn_topics_page.dart test/pages/equn_topics_page_test.dart
git commit -m "feat: show equn forum topic lists"
```

## Task 6: Read-Only Thread Detail

**Files:**
- Modify: `lib/pages/equn_thread_detail_page.dart`
- Test: `test/pages/equn_thread_detail_page_test.dart`

- [ ] **Step 1: Write failing detail page tests**

Create `test/pages/equn_thread_detail_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/equn_thread_detail_page.dart';
import 'package:fluxdo/providers/equn_discuz_providers.dart';
import 'package:fluxdo/services/discuz/equn_discuz_models.dart';
import 'package:fluxdo/services/discuz/equn_discuz_service.dart';

class FakeDetailService extends EqunDiscuzService {
  FakeDetailService(this.detail) : super();

  final EqunThreadDetail detail;

  @override
  Future<EqunThreadDetail> fetchThreadDetail(int tid, {int page = 1}) async {
    return detail;
  }
}

void main() {
  testWidgets('shows permission denied message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equnDiscuzServiceProvider.overrideWithValue(
            FakeDetailService(
              const EqunThreadDetail(
                tid: 49424,
                title: '考虑退出机制',
                status: EqunThreadDetailStatus.permissionDenied,
                permissionMessage: '权限不足或需要登录后查看',
                posts: [],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: EqunThreadDetailPage(tid: 49424)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('考虑退出机制'), findsOneWidget);
    expect(find.text('权限不足或需要登录后查看'), findsOneWidget);
    expect(find.text('在网页中打开'), findsOneWidget);
  });

  testWidgets('renders post messages for accessible thread', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equnDiscuzServiceProvider.overrideWithValue(
            FakeDetailService(
              const EqunThreadDetail(
                tid: 49396,
                title: '建立了一个宣传用的新站',
                status: EqunThreadDetailStatus.ok,
                posts: [
                  EqunPost(pid: 600722, author: 'lemonade5566', message: 'Ibercivis 和 WUProp@Home 如果是平台的话'),
                ],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: EqunThreadDetailPage(tid: 49396)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('建立了一个宣传用的新站'), findsOneWidget);
    expect(find.text('lemonade5566'), findsOneWidget);
    expect(find.textContaining('Ibercivis'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run detail tests to verify RED**

Run:

```bash
flutter test test/pages/equn_thread_detail_page_test.dart
```

Expected: FAIL because `EqunThreadDetailPage` is still a placeholder.

- [ ] **Step 3: Implement detail page**

Replace `lib/pages/equn_thread_detail_page.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/equn_discuz_providers.dart';
import '../services/discuz/equn_discuz_models.dart';
import '../utils/link_launcher.dart';

class EqunThreadDetailPage extends ConsumerWidget {
  const EqunThreadDetailPage({
    super.key,
    required this.tid,
    this.initialTitle,
  });

  final int tid;
  final String? initialTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(equnThreadDetailProvider(tid));
    return Scaffold(
      appBar: AppBar(title: Text(initialTitle ?? '主题 $tid')),
      body: detail.when(
        data: (value) => _DetailBody(detail: value),
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
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final EqunThreadDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.status == EqunThreadDetailStatus.permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(detail.title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(detail.permissionMessage ?? '权限不足或需要登录后查看', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => launchExternalLink(context, 'https://equn.com/forum/thread-${detail.tid}-1-1.html'),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('在网页中打开'),
              ),
            ],
          ),
        ),
      );
    }

    if (detail.posts.isEmpty) {
      return const Center(child: Text('没有可显示的帖子内容'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: detail.posts.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Text(detail.title, style: Theme.of(context).textTheme.headlineSmall);
        }
        final post = detail.posts[index - 1];
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.author, style: Theme.of(context).textTheme.titleSmall),
                if (post.dateline != null && post.dateline!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(post.dateline!, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 10),
                SelectableText(post.message),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Verify link launcher signature**

Confirm `lib/utils/link_launcher.dart` exports `launchExternalLink(BuildContext context, String url)`. The button callback must keep opening:

```dart
'https://equn.com/forum/thread-$tid-1-1.html'
```

- [ ] **Step 5: Run detail tests to verify GREEN**

Run:

```bash
flutter test test/pages/equn_thread_detail_page_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit detail page**

```bash
git add lib/pages/equn_thread_detail_page.dart test/pages/equn_thread_detail_page_test.dart
git commit -m "feat: add equn thread detail page"
```

## Task 7: Wire Home Navigation And Hide Discourse Entries

**Files:**
- Modify: `lib/pages/topics_screen.dart`
- Modify: `lib/navigation/nav_entry_registry.dart`
- Modify: `lib/constants.dart`
- Test: `test/navigation/nav_entry_registry_test.dart`

- [ ] **Step 1: Write failing navigation registry test**

Create `test/navigation/nav_entry_registry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/navigation/nav_entry_registry.dart';
import 'package:fluxdo/navigation/nav_entry.dart';

void main() {
  test('only home and profile remain default bottom nav entries in equn mode', () {
    final defaults = NavEntryRegistry.defaultBottomNavIds();

    expect(defaults, contains(NavEntryIds.home));
    expect(defaults, contains(NavEntryIds.profile));
    expect(defaults, isNot(contains(NavEntryIds.bookmarks)));
    expect(defaults, isNot(contains(NavEntryIds.messages)));
    expect(defaults, isNot(contains(NavEntryIds.notifications)));
  });
}
```

- [ ] **Step 2: Run navigation test to verify RED**

Run:

```bash
flutter test test/navigation/nav_entry_registry_test.dart
```

Expected: FAIL because Discourse-only entries are still available in the registry.

- [ ] **Step 3: Replace TopicsScreen main widgets**

Modify `lib/pages/topics_screen.dart` conservatively:

- Add imports:

```dart
import 'equn_topics_page.dart';
```

- In `MasterDetailLayout`, replace:

```dart
master: _wrapPaneTap(ActivePane.master, const TopicsPage()),
```

with:

```dart
master: _wrapPaneTap(ActivePane.master, const EqunTopicsPage()),
```

- Replace the `detail:` branch with `null` for the first stage:

```dart
detail: null,
```

- Set `masterFloatingActionButton` to `null`:

```dart
masterFloatingActionButton: null,
```

This avoids create-topic, drafts, and Discourse detail-pane behavior during the first stage. After the edit, remove these unused imports from `lib/pages/topics_screen.dart`: `providers/discourse_providers.dart`, `providers/selected_topic_provider.dart`, `topic_detail_page/topic_detail_page.dart`, `create_topic_page.dart`, and `drafts_page.dart`.

- [ ] **Step 4: Hide Discourse-only nav entries from registry**

Modify `lib/navigation/nav_entry_registry.dart`:

- Keep `home` and `profile`.
- Remove the entries for bookmarks, drafts, messages, and notifications from `buildAll()`.
- Remove history from `buildAll()` for this first stage, because the current browsing history entry depends on the old logged-in Discourse browsing model.

The resulting `buildAll()` should return:

```dart
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
    customIconBuilder: (ctx, ref) => _profileIcon(ctx, ref, selected: false),
    customSelectedIconBuilder: (ctx, ref) => _profileIcon(ctx, ref, selected: true),
  ),
];
```

- [ ] **Step 5: Change shared base URL constant**

Modify `lib/constants.dart`:

```dart
/// equn.com Discuz 论坛域名
static const String baseUrl = 'https://equn.com/forum';
```

- [ ] **Step 6: Run navigation test to verify GREEN**

Run:

```bash
flutter test test/navigation/nav_entry_registry_test.dart
```

Expected: PASS.

- [ ] **Step 7: Run focused Equn test suite**

Run:

```bash
flutter test test/services/discuz test/providers/equn_discuz_providers_test.dart test/pages/equn_topics_page_test.dart test/pages/equn_thread_detail_page_test.dart test/navigation/nav_entry_registry_test.dart
```

Expected: PASS.

- [ ] **Step 8: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: no analyzer errors after removing the unused imports introduced by this task.

- [ ] **Step 9: Commit navigation wiring**

```bash
git add lib/pages/topics_screen.dart lib/navigation/nav_entry_registry.dart lib/constants.dart test/navigation/nav_entry_registry_test.dart
git commit -m "feat: route home to equn discuz client"
```

## Task 8: Final Verification

**Files:**
- No planned code files.

- [ ] **Step 1: Run all tests**

Run:

```bash
flutter test
```

Expected: PASS.

- [ ] **Step 2: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: no new analyzer errors from the Equn Discuz changes.

- [ ] **Step 3: Run app smoke test on Linux**

Run:

```bash
flutter run -d linux
```

Expected:

- App launches.
- Home page title is “中国分布式计算论坛”.
- “最新回复” is selected by default.
- “最新发表” can be selected.
- Forum group list loads from equn.
- Opening a permission-denied topic shows a permission message.

- [ ] **Step 4: Confirm no verification docs commit is needed**

Run:

```bash
git status --short
```

Expected: no uncommitted documentation changes from verification.

## Self-Review

- Spec coverage:
  - Latest replies and latest threads are covered by Tasks 1, 2, 3, and 4.
  - Forum groups and forum topic lists are covered by Tasks 1, 2, 3, 4, and 5.
  - Thread detail and permission denied state are covered by Tasks 1, 2, 3, and 6.
  - Discourse route cutover and hiding Discourse-only entries are covered by Task 7.
  - Verification is covered by Task 8.
- Placeholder scan:
  - No placeholder markers or generic handling steps are present.
- Type consistency:
  - Provider and model names are consistent across tasks: `EqunGuideFilter`, `EqunTopicSummary`, `EqunForumGroup`, `EqunForumTopicPage`, `EqunThreadDetail`, and `EqunDiscuzService`.
