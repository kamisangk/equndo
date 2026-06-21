import 'dart:convert';

import 'package:dio/dio.dart';

import '../network/discourse_dio.dart';
import 'equn_discuz_models.dart';
import 'equn_discuz_parser.dart';
import 'equn_discuz_session.dart';

class EqunDiscuzService {
  static const String baseUrl = 'https://equn.com/forum/';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  EqunDiscuzService({Dio? dio})
    : _dio =
          dio ??
          DiscourseDio.create(
            baseUrl: baseUrl,
            defaultHeaders: {
              'Accept': 'application/json, text/html, */*; q=0.01',
              'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
              'User-Agent': _userAgent,
            },
            enableCfChallenge: false,
            enableRetry: false,
            enableNetworkLog: false,
            maxConcurrent: null,
          );

  final Dio _dio;

  Future<List<EqunTopicSummary>> fetchGuideTopics(
    EqunGuideFilter filter, {
    int page = 1,
  }) async {
    final response = await _dio.get<String>(
      'forum.php',
      queryParameters: {
        'mod': 'guide',
        'view': filter.view,
        if (page > 1) 'page': page,
      },
      options: Options(
        responseType: ResponseType.plain,
        extra: const {'skipAppHeaders': true},
      ),
    );
    return EqunDiscuzParser.parseGuideTopics(response.data ?? '');
  }

  Future<List<EqunForumGroup>> fetchForumGroups() async {
    final response = await _dio.get<dynamic>(
      'api/mobile/index.php',
      queryParameters: {'version': 4, 'module': 'forumindex'},
    );
    return EqunDiscuzParser.parseForumGroups(_asJsonMap(response.data));
  }

  Future<EqunForumTopicPage> fetchForumTopics(
    int fid, {
    int page = 1,
    String? orderBy,
  }) async {
    final response = await _dio.get<dynamic>(
      'api/mobile/index.php',
      queryParameters: {
        'version': 4,
        'module': 'forumdisplay',
        'fid': fid,
        'page': page,
        if (orderBy != null) 'orderby': orderBy,
      },
    );
    return EqunDiscuzParser.parseForumTopicPage(_asJsonMap(response.data));
  }

  Future<EqunUserTopicPage> fetchMyTopics({
    int page = 1,
    String? username,
  }) async {
    final response = await _dio.get<String>(
      'home.php',
      queryParameters: {
        'mod': 'space',
        'do': 'thread',
        'view': 'me',
        'type': 'thread',
        'from': 'space',
        'page': page < 1 ? 1 : page,
      },
      options: Options(
        responseType: ResponseType.plain,
        extra: const {'skipAppHeaders': true},
      ),
    );
    return EqunDiscuzParser.parseSpaceThreadTopicPage(
      response.data ?? '',
      currentUsername: username,
      page: page < 1 ? 1 : page,
    );
  }

  Future<EqunUserTopicPage> fetchFavoriteTopics({int page = 1}) async {
    final response = await _dio.get<String>(
      'home.php',
      queryParameters: {
        'mod': 'space',
        'do': 'favorite',
        'view': 'me',
        'type': 'thread',
        'page': page < 1 ? 1 : page,
      },
      options: Options(
        responseType: ResponseType.plain,
        extra: const {'skipAppHeaders': true},
      ),
    );
    return EqunDiscuzParser.parseFavoriteTopicPage(
      response.data ?? '',
      page: page < 1 ? 1 : page,
    );
  }

  Future<EqunThreadDetail> fetchThreadDetail(int tid, {int page = 1}) async {
    final response = await _dio.get<dynamic>(
      'api/mobile/index.php',
      queryParameters: {
        'version': 4,
        'module': 'viewthread',
        'tid': tid,
        'page': page,
      },
    );
    return EqunDiscuzParser.parseThreadDetail(_asJsonMap(response.data));
  }

  Future<EqunDiscuzProfile?> fetchCurrentProfile() async {
    final response = await _dio.get<dynamic>(
      'api/mobile/index.php',
      queryParameters: {'version': 4, 'module': 'forumindex'},
    );
    final profile = EqunDiscuzParser.parseCurrentProfile(
      _asJsonMap(response.data),
    );
    if (profile == null) return null;
    final detail = profile.uid == null
        ? null
        : await _fetchProfileDetail(profile.uid!);
    final merged = detail == null ? profile : profile.merge(detail);
    return EqunDiscuzProfile(
      username: merged.username,
      uid: merged.uid,
      nickname: merged.nickname,
      avatarUrl: merged.uid != null && merged.uid! > 0
          ? EqunDiscuzSession.discuzAvatarUrl(merged.uid!)
          : merged.avatarUrl,
      points: merged.points,
      basicScore: merged.basicScore,
      wikiPuzzle: merged.wikiPuzzle,
      competitionScore: merged.competitionScore,
      contribution: merged.contribution,
    );
  }

  Future<EqunDiscuzProfile?> _fetchProfileDetail(int uid) async {
    try {
      final response = await _dio.get<dynamic>(
        'api/mobile/index.php',
        queryParameters: {'version': 4, 'module': 'profile', 'uid': uid},
      );
      return EqunDiscuzParser.parseCurrentProfile(_asJsonMap(response.data));
    } catch (_) {
      return null;
    }
  }

  Future<EqunPostSubmitResult> createReply({
    required int tid,
    required String message,
    int? replyToPid,
  }) async {
    final formhash = await _fetchFormhash('sendreply', {
      'tid': tid,
      ...?(replyToPid == null ? null : {'pid': replyToPid}),
    });
    final queryParameters = <String, dynamic>{
      'version': 4,
      'module': 'sendreply',
      'tid': tid,
      'replysubmit': 'yes',
      ...?(replyToPid == null ? null : {'pid': replyToPid}),
    };
    final response = await _dio.post<dynamic>(
      'api/mobile/index.php',
      queryParameters: queryParameters,
      data: {
        'formhash': formhash,
        'message': message,
        ...?(replyToPid == null ? null : {'reppid': replyToPid}),
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: const {'skipCsrf': true},
      ),
    );
    return EqunDiscuzParser.parsePostSubmitResult(_asJsonMap(response.data));
  }

  Future<int> createThread({
    required int fid,
    required String subject,
    required String message,
  }) async {
    final formhash = await _fetchFormhash('newthread', {'fid': fid});
    final response = await _dio.post<dynamic>(
      'api/mobile/index.php',
      queryParameters: {
        'version': 4,
        'module': 'newthread',
        'fid': fid,
        'topicsubmit': 'yes',
      },
      data: {'formhash': formhash, 'subject': subject, 'message': message},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: const {'skipCsrf': true},
      ),
    );
    return EqunDiscuzParser.parsePostSubmitResult(
      _asJsonMap(response.data),
    ).tid;
  }

  Future<String> _fetchFormhash(
    String module,
    Map<String, dynamic> queryParameters,
  ) async {
    final response = await _dio.get<dynamic>(
      'api/mobile/index.php',
      queryParameters: {'version': 4, 'module': module, ...queryParameters},
    );
    final formhash = EqunDiscuzParser.parseFormhash(_asJsonMap(response.data));
    if (formhash == null || formhash.isEmpty) {
      throw const FormatException('无法获取 Discuz formhash');
    }
    return formhash;
  }

  Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return const {};
  }
}
