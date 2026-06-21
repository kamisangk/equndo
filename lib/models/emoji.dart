class Emoji {
  final String name;
  final String url;
  final String group;
  final List<String> searchAliases;

  Emoji({
    required this.name,
    required this.url,
    required this.group,
    this.searchAliases = const [],
  });

  factory Emoji.fromJson(Map<String, dynamic> json) {
    return Emoji(
      name: json['name'] as String,
      url: json['url'] as String,
      group: json['group'] as String,
      searchAliases: (json['search_aliases'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}
