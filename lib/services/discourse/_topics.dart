part of 'discourse_service.dart';

/// 话题相关
mixin _TopicsMixin on _DiscourseServiceBase {
  /// 按 topic_ids 获取话题（对齐网页版 loadBefore 请求）
  /// 请求 /latest.json?topic_ids=1,2,3 返回指定话题的最新数据
  Future<TopicListResponse> getTopicsByIds(List<int> topicIds) async {
    if (topicIds.isEmpty) {
      return TopicListResponse(topics: [], moreTopicsUrl: null);
    }
    final response = await _dio.get(
      '/latest.json',
      queryParameters: {'topic_ids': topicIds.join(',')},
    );
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getLatestTopics({
    int page = 0,
    String? order,
    bool? ascending,
  }) async {
    if (page == 0 && order == null) {
      final preloaded = PreloadedDataService();
      final preloadedList = await preloaded.getInitialTopicList();
      if (preloadedList != null) {
        return preloadedList;
      }
    }

    final queryParams = <String, dynamic>{};
    if (page > 0) queryParams['page'] = page;
    if (order != null) queryParams['order'] = order;
    if (ascending != null) queryParams['ascending'] = ascending.toString();

    final response = await _dio.get(
      '/latest.json',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  /// 获取话题列表（支持分类和标签筛选）
  Future<TopicListResponse> getFilteredTopics({
    required String filter,
    int? categoryId,
    String? categorySlug,
    String? parentCategorySlug,
    List<String>? tags,
    String? period,
    int page = 0,
    String? order,
    bool? ascending,
    String? subset,
  }) async {
    String path;
    final queryParams = <String, dynamic>{};

    if (page > 0) {
      queryParams['page'] = page;
    }

    if (period != null) {
      queryParams['period'] = period;
    }

    if (order != null) {
      queryParams['order'] = order;
    }

    if (ascending != null) {
      queryParams['ascending'] = ascending.toString();
    }

    if (subset != null) {
      queryParams['subset'] = subset;
    }

    if (categoryId != null && categorySlug != null) {
      // 分类路径，标签通过 tags[] 查询参数传递
      if (parentCategorySlug != null) {
        path =
            '/c/$parentCategorySlug/$categorySlug/$categoryId/l/$filter.json';
      } else {
        path = '/c/$categorySlug/$categoryId/l/$filter.json';
      }
      if (tags != null && tags.isNotEmpty) {
        queryParams['tags[]'] = tags;
      }
    } else if (tags != null && tags.isNotEmpty) {
      // 纯标签筛选：单标签用路径，多标签用第一个标签路径 + 其余标签查询参数
      path = '/tag/${tags.first}/l/$filter.json';
      if (tags.length > 1) {
        queryParams['tags[]'] = tags.skip(1).toList();
        queryParams['match_all_tags'] = 'true';
      }
    } else {
      path = '/$filter.json';
    }

    final response = await _dio.get(
      path,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getNewTopics({
    int page = 0,
    String? order,
    bool? ascending,
    String? subset,
  }) async {
    final queryParams = <String, dynamic>{};
    if (page > 0) queryParams['page'] = page;
    if (order != null) queryParams['order'] = order;
    if (ascending != null) queryParams['ascending'] = ascending.toString();
    if (subset != null) queryParams['subset'] = subset;

    final response = await _dio.get(
      '/new.json',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getUnreadTopics({
    int page = 0,
    String? order,
    bool? ascending,
  }) async {
    final queryParams = <String, dynamic>{};
    if (page > 0) queryParams['page'] = page;
    if (order != null) queryParams['order'] = order;
    if (ascending != null) queryParams['ascending'] = ascending.toString();

    final response = await _dio.get(
      '/unread.json',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getUnseenTopics({
    int page = 0,
    String? order,
    bool? ascending,
  }) async {
    final queryParams = <String, dynamic>{};
    if (page > 0) queryParams['page'] = page;
    if (order != null) queryParams['order'] = order;
    if (ascending != null) queryParams['ascending'] = ascending.toString();

    final response = await _dio.get(
      '/unseen.json',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getHotTopics({
    int page = 0,
    String? order,
    bool? ascending,
  }) async {
    final queryParams = <String, dynamic>{};
    if (page > 0) queryParams['page'] = page;
    if (order != null) queryParams['order'] = order;
    if (ascending != null) queryParams['ascending'] = ascending.toString();

    final response = await _dio.get(
      '/hot.json',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  /// 获取话题详情
  Future<TopicDetail> getTopicDetail(
    int id, {
    int? postNumber,
    bool trackVisit = false,
    String? filter,
    String? usernameFilters,
    bool filterTopLevelReplies = false,
  }) async {
    final path = postNumber != null ? '/t/$id/$postNumber.json' : '/t/$id.json';
    final queryParams = <String, dynamic>{};
    if (trackVisit) {
      queryParams['track_visit'] = true;
    }
    if (filter != null) {
      queryParams['filter'] = filter;
    }
    if (usernameFilters != null) {
      queryParams['username_filters'] = usernameFilters;
    }
    if (filterTopLevelReplies) {
      queryParams['filter_top_level_replies'] = true;
    }
    final options = trackVisit
        ? Options(
            headers: {
              'Discourse-Track-View': '1',
              'Discourse-Track-View-Topic-Id': '$id',
            },
          )
        : null;
    final response = await _dio.get(
      path,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
      options: options,
    );
    return TopicDetail.fromJson(response.data);
  }

  /// 通过 slug 获取话题详情（返回真实的 topic ID）
  Future<TopicDetail> getTopicDetailBySlug(
    String slug, {
    int? postNumber,
    bool trackVisit = false,
  }) async {
    final path = postNumber != null
        ? '/t/$slug/$postNumber.json'
        : '/t/$slug.json';
    final queryParams = <String, dynamic>{};
    if (trackVisit) {
      queryParams['track_visit'] = true;
    }
    // 通过 slug 获取时无法提前知道 topic_id，仅设置 Track-View 头
    final options = trackVisit
        ? Options(headers: {'Discourse-Track-View': '1'})
        : null;
    final response = await _dio.get(
      path,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
      options: options,
    );
    return TopicDetail.fromJson(response.data);
  }

  /// 批量获取帖子内容
  Future<PostStream> getPosts(int topicId, List<int> postIds) async {
    final response = await _dio.get(
      '/t/$topicId/posts.json',
      queryParameters: {'post_ids[]': postIds},
    );
    final data = response.data as Map<String, dynamic>;
    final streamJson = data.containsKey('post_stream')
        ? data['post_stream'] as Map<String, dynamic>
        : data;
    final postStream = PostStream.fromJson(streamJson);
    // 注入 topic 级别的 badges 数据
    PostStream.injectBadges(
      postStream.posts,
      data,
      streamJson['posts'] as List<dynamic>?,
    );
    return postStream;
  }

  /// 按帖子编号获取帖子
  Future<PostStream> getPostsByNumber(
    int topicId, {
    required int postNumber,
    required bool asc,
  }) async {
    final response = await _dio.get(
      '/t/$topicId/posts.json',
      queryParameters: {'post_number': postNumber, 'asc': asc},
    );
    final data = response.data as Map<String, dynamic>;
    final streamJson = data.containsKey('post_stream')
        ? data['post_stream'] as Map<String, dynamic>
        : data;
    final postStream = PostStream.fromJson(streamJson);
    // 注入 topic 级别的 badges 数据
    PostStream.injectBadges(
      postStream.posts,
      data,
      streamJson['posts'] as List<dynamic>?,
    );
    return postStream;
  }

  Future<TopicListResponse> getTopTopics() async {
    final response = await _dio.get('/top.json');
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getCategoryTopics(String categorySlug) async {
    final response = await _dio.get('/c/$categorySlug.json');
    return TopicListResponse.fromJson(response.data);
  }

  /// 创建话题
  Future<int> createTopic({
    required String title,
    required String raw,
    required int categoryId,
    List<String>? tags,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'raw': raw,
      'category': categoryId,
      'archetype': 'regular',
    };

    if (tags != null && tags.isNotEmpty) {
      data['tags[]'] = tags;
    }

    final response = await _dio.post(
      '/posts.json',
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    final respData = response.data;

    // 帖子进入审核队列
    if (respData is Map && respData['action'] == 'enqueued') {
      throw PostEnqueuedException(
        pendingCount: respData['pending_count'] as int? ?? 0,
      );
    }

    if (respData is Map &&
        respData.containsKey('post') &&
        respData['post']['topic_id'] != null) {
      return respData['post']['topic_id'] as int;
    }

    if (respData is Map && respData['topic_id'] != null) {
      return respData['topic_id'] as int;
    }

    if (respData is Map && respData['success'] == false) {
      final errors = respData['errors'];
      final msg = errors is List ? errors.join('\n') : errors?.toString();
      throw Exception(msg ?? S.current.error_createTopicFailed);
    }

    throw Exception(S.current.error_unknownResponseFormat);
  }

  /// 忽略新话题/新回复
  Future<void> dismissNewTopics({
    int? categoryId,
    bool dismissTopics = true,
    bool dismissPosts = false,
  }) async {
    final data = <String, dynamic>{
      'dismiss_topics': dismissTopics,
      'dismiss_posts': dismissPosts,
    };
    if (categoryId != null) {
      data['category_id'] = categoryId;
    }
    await _dio.put(
      '/topics/reset-new.json',
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  /// 忽略未读话题
  Future<void> dismissUnreadTopics({int? categoryId}) async {
    final data = <String, dynamic>{
      'filter': 'unread',
      'operation': {'type': 'dismiss_posts'},
    };
    if (categoryId != null) {
      data['category_id'] = categoryId;
    }
    await _dio.put('/topics/bulk.json', data: data);
  }

  /// 设置话题订阅级别
  Future<void> setTopicNotificationLevel(
    int topicId,
    TopicNotificationLevel level,
  ) async {
    await _dio.post(
      '/t/$topicId/notifications',
      data: {'notification_level': level.value},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  /// 更新话题元数据
  Future<void> updateTopic({
    required int topicId,
    String? title,
    int? categoryId,
    List<String>? tags,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (categoryId != null) data['category_id'] = categoryId;
      if (tags != null) data['tags[]'] = tags;

      await _dio.put(
        '/t/-/$topicId.json',
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 获取话题主贴的 HTML 内容（轻量请求，只解析第一楼）
  Future<String?> getTopicFirstPostCooked(int topicId) async {
    final response = await _dio.get('/t/$topicId/1.json');
    final data = response.data as Map<String, dynamic>;
    final postStream = data['post_stream'] as Map<String, dynamic>?;
    final posts = postStream?['posts'] as List<dynamic>?;
    if (posts == null || posts.isEmpty) return null;
    final firstPost = posts.first as Map<String, dynamic>;
    return firstPost['cooked'] as String?;
  }
}
