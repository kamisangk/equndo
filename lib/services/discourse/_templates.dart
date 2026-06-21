part of 'discourse_service.dart';

/// 模板相关 API
mixin _TemplatesMixin on _DiscourseServiceBase {
  /// 获取模板列表
  Future<List<Template>> getTemplates() async {
    try {
      final response = await _dio.get('/discourse_templates');
      final data = response.data;
      if (data is Map<String, dynamic> && data['templates'] is List) {
        return (data['templates'] as List)
            .map((e) => Template.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      // 兼容直接返回数组的情况
      if (data is List) {
        return data
            .map((e) => Template.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 记录模板使用
  Future<void> useTemplate(int templateId) async {
    try {
      await _dio.post('/discourse_templates/$templateId/use');
    } on DioException catch (_) {
      // 使用记录失败不影响主流程，静默忽略
    }
  }
}
