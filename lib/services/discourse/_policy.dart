part of 'discourse_service.dart';

/// Policy（discourse-policy 插件）相关 API
///
/// 对应 Discourse 源码 `plugins/discourse-policy/app/controllers/policy_controller.rb`
/// 暴露的四个端点：accept / unaccept / accepted / not-accepted。
mixin _PolicyMixin on _DiscourseServiceBase {
  /// 接受政策
  Future<void> acceptPolicy({required int postId}) async {
    try {
      await _dio.put(
        '/policy/accept',
        data: {'post_id': postId},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 撤销接受
  Future<void> revokePolicy({required int postId}) async {
    try {
      await _dio.put(
        '/policy/unaccept',
        data: {'post_id': postId},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 分页拉取已接受用户
  Future<List<PolicyUser>> loadPolicyAccepted({
    required int postId,
    int offset = 0,
  }) async {
    return _loadPolicyUsers('/policy/accepted', postId: postId, offset: offset);
  }

  /// 分页拉取未接受用户
  Future<List<PolicyUser>> loadPolicyNotAccepted({
    required int postId,
    int offset = 0,
  }) async {
    return _loadPolicyUsers(
      '/policy/not-accepted',
      postId: postId,
      offset: offset,
    );
  }

  Future<List<PolicyUser>> _loadPolicyUsers(
    String path, {
    required int postId,
    required int offset,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: {
          'post_id': postId,
          'offset': offset,
        },
      );
      final users = (response.data is Map)
          ? response.data['users'] as List<dynamic>?
          : null;
      if (users == null) return [];
      return users
          .whereType<Map<String, dynamic>>()
          .map(PolicyUser.fromJson)
          .toList();
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }
}
