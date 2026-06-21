import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'equn_discuz_session.dart';
import 'equn_discuz_models.dart';

class EqunDiscuzParser {
  static const String baseUrl = 'https://equn.com/forum/';

  static List<EqunTopicSummary> parseGuideTopics(String html) {
    final document = html_parser.parse(html);
    final rows = document.querySelectorAll(
      '#threadlist tbody[id^="normalthread_"]',
    );
    return rows.map((tbody) {
      final id = tbody.id;
      final tid =
          _firstInt(id) ??
          _firstInt(
            tbody.querySelector('a[href*="thread-"]')?.attributes['href'],
          );
      if (tid == null) {
        throw const FormatException('无法解析主题 id');
      }
      final titleLink = tbody.querySelector('a.xst');
      final title = _clean(titleLink?.text ?? '');
      final titleCellText = _clean(tbody.querySelector('th')?.text ?? '');
      final byCells = tbody.querySelectorAll('td.by');
      final forumLink = byCells.isNotEmpty
          ? byCells[0].querySelector('a[href*="forum-"]')
          : null;
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
        readPermissionText: readPermission == null
            ? null
            : '阅读权限 $readPermission',
        url: _absolute(titleLink?.attributes['href'] ?? 'thread-$tid-1-1.html'),
      );
    }).toList();
  }

  static List<EqunForumGroup> parseForumGroups(Map<String, dynamic> json) {
    final variables = _variables(json);
    final forumList = variables['forumlist'] as List<dynamic>? ?? const [];
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
            forums: ids
                .map((id) => forumsById[id])
                .whereType<EqunForum>()
                .toList(),
          );
        })
        .toList();
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

  static EqunUserTopicPage parseSpaceThreadTopicPage(
    String html, {
    String? currentUsername,
    int page = 1,
  }) {
    final document = html_parser.parse(html);
    final topics = <EqunTopicSummary>[];

    for (final row in document.querySelectorAll('.tl table tr')) {
      if (row.classes.contains('th')) continue;
      final titleLink = _firstElement(
        row.querySelectorAll('th a[href]'),
        (element) => _topicIdFromHref(element.attributes['href']) != null,
      );
      if (titleLink == null) continue;
      final tid = _topicIdFromHref(titleLink.attributes['href']);
      if (tid == null) continue;

      final forumLink = _firstElement(
        row.querySelectorAll('a[href]'),
        (element) => _forumIdFromHref(element.attributes['href']) != null,
      );
      final numCell = row.querySelector('td.num');
      final byCells = row.querySelectorAll('td.by');
      final lastPostCell = byCells.isEmpty ? null : byCells.last;
      final lastPoster = _clean(
        lastPostCell?.querySelector('cite a')?.text ?? '',
      );
      final lastPostText = _clean(
        lastPostCell?.querySelector('em')?.text ?? '',
      );
      final readPermission = _readPermission(row.text);

      topics.add(
        EqunTopicSummary(
          tid: tid,
          title: _clean(titleLink.text),
          forumId: _forumIdFromHref(forumLink?.attributes['href']),
          forumName: _clean(forumLink?.text ?? ''),
          author: _clean(currentUsername ?? ''),
          replyCount: _parseCompactInt(numCell?.querySelector('a')?.text),
          viewCount: _parseCompactInt(numCell?.querySelector('em')?.text),
          lastPoster: lastPoster,
          lastPostText: lastPostText,
          readPermission: readPermission,
          readPermissionText: readPermission == null
              ? null
              : '阅读权限 $readPermission',
          url: _absolute(titleLink.attributes['href'] ?? ''),
          pinned: row.innerHtml.contains('pin_'),
          digest: row.innerHtml.contains('digest_'),
        ),
      );
    }

    return EqunUserTopicPage(
      topics: topics,
      page: page,
      hasMore: _hasNextPage(document),
    );
  }

  static EqunUserTopicPage parseFavoriteTopicPage(String html, {int page = 1}) {
    final document = html_parser.parse(html);
    final topics = <EqunTopicSummary>[];

    for (final item in document.querySelectorAll('#favorite_ul li')) {
      final titleLink = _firstElement(
        item.querySelectorAll('a[href]'),
        (element) =>
            !element.classes.contains('y') &&
            _topicIdFromHref(element.attributes['href']) != null,
      );
      final tid =
          _topicIdFromHref(titleLink?.attributes['href']) ??
          _parseInt(item.querySelector('input[vid]')?.attributes['vid']);
      if (titleLink == null || tid == null) continue;

      final description = _clean(
        item.querySelector('.quote blockquote')?.text ?? '',
      );
      final createdText = _clean(item.querySelector('.xg1')?.text ?? '');
      topics.add(
        EqunTopicSummary(
          tid: tid,
          title: _clean(titleLink.text),
          author: '',
          replyCount: 0,
          viewCount: 0,
          createdText: createdText,
          lastPostText: description.isEmpty ? createdText : description,
          url: _absolute(titleLink.attributes['href'] ?? ''),
        ),
      );
    }

    return EqunUserTopicPage(
      topics: topics,
      page: page,
      hasMore: _hasNextPage(document),
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
      status: permissionDenied
          ? EqunThreadDetailStatus.permissionDenied
          : EqunThreadDetailStatus.ok,
      permissionMessage: permissionDenied ? '权限不足或需要登录后查看' : null,
      posts: posts,
    );
  }

  static EqunDiscuzProfile? parseCurrentProfile(Map<String, dynamic> json) {
    final variables = _variables(json);
    final space = variables['space'] as Map<String, dynamic>?;
    final uid = _parseInt(space?['uid']) ?? _parseInt(variables['member_uid']);
    final username = _clean(
      space?['username']?.toString() ??
          variables['member_username']?.toString() ??
          '',
    );
    if (uid == null || uid <= 0 || username.isEmpty) return null;
    return EqunDiscuzProfile(
      username: username,
      uid: uid,
      nickname: username,
      avatarUrl: EqunDiscuzSession.discuzAvatarUrl(uid),
      points: _memberScore(variables, 'credits', 'member_credits'),
      basicScore: _memberScore(variables, 'extcredits1'),
      wikiPuzzle: _memberScore(variables, 'extcredits2'),
      competitionScore: _memberScore(variables, 'extcredits3'),
      contribution: _memberScore(variables, 'extcredits7', 'extcredits4'),
    );
  }

  static String? parseFormhash(Map<String, dynamic> json) {
    final value = _variables(json)['formhash']?.toString();
    return value == null || value.trim().isEmpty ? null : value.trim();
  }

  static EqunPostSubmitResult parsePostSubmitResult(Map<String, dynamic> json) {
    final variables = _variables(json);
    final message = json['Message'] as Map<String, dynamic>?;
    final messageVal = message?['messageval']?.toString();
    final tid = _parseInt(variables['tid']) ?? _firstInt(messageVal);
    if (tid == null || tid <= 0) {
      final messageText = message?['messagestr']?.toString() ?? messageVal;
      throw FormatException(messageText ?? '无法解析 Discuz 发帖结果');
    }
    return EqunPostSubmitResult(
      tid: tid,
      pid: _parseInt(variables['pid']),
      message: messageVal,
    );
  }

  static Map<String, dynamic> _variables(Map<String, dynamic> json) {
    return json['Variables'] as Map<String, dynamic>? ?? const {};
  }

  static int _memberScore(
    Map<String, dynamic> variables,
    String key, [
    String? fallbackKey,
  ]) {
    int? valueFrom(Map<String, dynamic>? source) {
      if (source == null) return null;
      return _parseInt(source[key]) ??
          (fallbackKey == null ? null : _parseInt(source[fallbackKey]));
    }

    final space = variables['space'];
    if (space is Map<String, dynamic>) {
      final value = valueFrom(space);
      if (value != null) return value;
    }

    final member = variables['member'];
    if (member is Map<String, dynamic>) {
      final value = valueFrom(member);
      if (value != null) return value;
    }

    return valueFrom(variables) ?? 0;
  }

  static EqunForum _forumFromJson(Map<String, dynamic> json) {
    return EqunForum(
      fid: _parseInt(json['fid']) ?? 0,
      name: _clean(json['name']?.toString() ?? ''),
      threads:
          _parseInt(json['threads']) ?? _parseInt(json['threadcount']) ?? 0,
      posts: _parseInt(json['posts']) ?? 0,
      todayPosts: _parseInt(json['todayposts']) ?? 0,
      iconUrl: json['icon']?.toString(),
      description: json['description']?.toString(),
      parentFid: _parseInt(json['fup']),
    );
  }

  static EqunTopicSummary _topicFromForumJson(
    Map<String, dynamic> json, {
    required EqunForum defaultForum,
  }) {
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
      readPermissionText: readPermission == null || readPermission == 0
          ? null
          : '阅读权限 $readPermission',
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
      position: _parseInt(json['position']) ?? _parseInt(json['number']) ?? 0,
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

  static Element? _firstElement(
    Iterable<Element> elements,
    bool Function(Element element) test,
  ) {
    for (final element in elements) {
      if (test(element)) return element;
    }
    return null;
  }

  static int? _topicIdFromHref(String? href) {
    if (href == null) return null;
    final decoded = href.replaceAll('&amp;', '&');
    final match = RegExp(
      r'(?:[?&]tid=|[?&]ptid=|thread-)(\d+)',
    ).firstMatch(decoded);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static int? _forumIdFromHref(String? href) {
    if (href == null) return null;
    final decoded = href.replaceAll('&amp;', '&');
    final match = RegExp(r'(?:[?&]fid=|forum-)(\d+)').firstMatch(decoded);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static bool _hasNextPage(Document document) {
    if (document.querySelector('.pg a.nxt') != null) return true;
    return document
        .querySelectorAll('a[href*="page="]')
        .any((element) => element.classes.contains('nxt'));
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
    return value
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
