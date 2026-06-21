part of 'discourse_service.dart';

/// 投票相关
mixin _VotingMixin on _DiscourseServiceBase {
  /// 投票
  Future<Poll?> votePoll({
    required int postId,
    required String pollName,
    required List<String> options,
  }) async {
    try {
      final data = {
        'post_id': postId,
        'poll_name': pollName,
      };

      for (int i = 0; i < options.length; i++) {
        data['options[]'] = options[i];
      }

      final response = await _dio.put(
        '/polls/vote',
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      if (response.data is Map && response.data['poll'] != null) {
        return Poll.fromJson(response.data['poll'] as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 撤销投票
  Future<Poll?> removeVote({
    required int postId,
    required String pollName,
  }) async {
    try {
      final response = await _dio.delete(
        '/polls/vote',
        data: {
          'post_id': postId,
          'poll_name': pollName,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      if (response.data is Map && response.data['poll'] != null) {
        return Poll.fromJson(response.data['poll'] as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 话题投票
  Future<VoteResponse> voteTopicVote(int topicId) async {
    try {
      final response = await _dio.post(
        '/voting/vote',
        data: {'topic_id': topicId},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return VoteResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 取消话题投票
  Future<VoteResponse> unvoteTopicVote(int topicId) async {
    try {
      final response = await _dio.post(
        '/voting/unvote',
        data: {'topic_id': topicId},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return VoteResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 获取话题投票用户列表
  Future<List<VotedUser>> getTopicVoteWho(int topicId) async {
    try {
      final response = await _dio.get(
        '/voting/who',
        queryParameters: {'topic_id': topicId},
      );
      if (response.data is List) {
        return (response.data as List)
            .map((e) => VotedUser.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[DiscourseService] getTopicVoteWho failed: $e');
      return [];
    }
  }
}
