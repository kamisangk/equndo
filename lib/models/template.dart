/// Discourse 模板模型
class Template {
  final int id;
  final String title;
  final String slug;
  final String content;
  final List<String> tags;
  final int usages;

  const Template({
    required this.id,
    required this.title,
    required this.slug,
    required this.content,
    required this.tags,
    required this.usages,
  });

  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      content: json['content'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      usages: json['usages'] as int? ?? 0,
    );
  }
}
