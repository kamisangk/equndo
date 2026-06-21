class TagGroup {
  final int id;
  final String name;
  final List<String> tagNames;
  final bool onePerTopic;

  TagGroup({
    required this.id,
    required this.name,
    required this.tagNames,
    this.onePerTopic = false,
  });

  factory TagGroup.fromJson(Map<String, dynamic> json) {
    return TagGroup(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      tagNames: (json['tag_names'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      onePerTopic: json['one_per_topic'] as bool? ?? false,
    );
  }
}

class TagGroupResponse {
  final List<TagGroup> tagGroups;

  TagGroupResponse({required this.tagGroups});

  factory TagGroupResponse.fromJson(Map<String, dynamic> json) {
    return TagGroupResponse(
      tagGroups: (json['tag_groups'] as List<dynamic>?)
          ?.map((e) => TagGroup.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}
