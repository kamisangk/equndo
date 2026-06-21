/// `POST /solution/shared_issue` 的响应
///
/// 来自 discourse-solved 插件: 同一接口 toggle "俺也一样" 状态。
class SharedIssueResponse {
  final int count;
  final bool userCreatedSharedIssue;

  const SharedIssueResponse({
    required this.count,
    required this.userCreatedSharedIssue,
  });

  factory SharedIssueResponse.fromJson(Map<String, dynamic> json) {
    return SharedIssueResponse(
      count: json['count'] as int? ?? 0,
      userCreatedSharedIssue: json['user_created_shared_issue'] as bool? ?? false,
    );
  }
}
