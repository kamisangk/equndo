import '../../models/user.dart';

class EqunDiscuzProfile {
  final String username;
  final int? uid;
  final String? nickname;
  final String? avatarUrl;
  final int points;
  final int basicScore;
  final int wikiPuzzle;
  final int competitionScore;
  final int contribution;

  const EqunDiscuzProfile({
    required this.username,
    this.uid,
    this.nickname,
    this.avatarUrl,
    this.points = 0,
    this.basicScore = 0,
    this.wikiPuzzle = 0,
    this.competitionScore = 0,
    this.contribution = 0,
  });

  factory EqunDiscuzProfile.fromJson(Map<String, dynamic> json) {
    final rawUid = json['uid'];
    final uid = rawUid is int ? rawUid : int.tryParse(rawUid?.toString() ?? '');
    return EqunDiscuzProfile(
      username: json['username']?.toString() ?? '',
      uid: uid,
      nickname: _nonBlank(json['nickname']?.toString()),
      avatarUrl:
          _nonBlank(json['avatar_url']?.toString()) ??
          (uid != null && uid > 0
              ? EqunDiscuzSession.discuzAvatarUrl(uid)
              : null),
      points: _parseInt(json['points']),
      basicScore: _parseInt(json['basic_score']),
      wikiPuzzle: _parseInt(json['wiki_puzzle']),
      competitionScore: _parseInt(json['competition_score']),
      contribution: _parseInt(json['contribution']),
    );
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    if (uid != null) 'uid': uid,
    if (nickname != null && nickname!.trim().isNotEmpty)
      'nickname': nickname!.trim(),
    if (avatarUrl != null && avatarUrl!.trim().isNotEmpty)
      'avatar_url': avatarUrl!.trim(),
    'points': points,
    'basic_score': basicScore,
    'wiki_puzzle': wikiPuzzle,
    'competition_score': competitionScore,
    'contribution': contribution,
  };

  EqunDiscuzProfile merge(EqunDiscuzProfile other) {
    return EqunDiscuzProfile(
      username: other.username.trim().isNotEmpty ? other.username : username,
      uid: other.uid ?? uid,
      nickname: _nonBlank(other.nickname) ?? nickname,
      avatarUrl: _nonBlank(other.avatarUrl) ?? avatarUrl,
      points: other.points != 0 ? other.points : points,
      basicScore: other.basicScore != 0 ? other.basicScore : basicScore,
      wikiPuzzle: other.wikiPuzzle != 0 ? other.wikiPuzzle : wikiPuzzle,
      competitionScore: other.competitionScore != 0
          ? other.competitionScore
          : competitionScore,
      contribution: other.contribution != 0 ? other.contribution : contribution,
    );
  }

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static int _parseInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }
}

class EqunDiscuzSession {
  EqunDiscuzSession._();

  static const String authCookieName = 'mp49_2132_auth';

  static bool hasAuthenticatedSession({
    required String? authCookieValue,
    required String? username,
  }) {
    return authCookieValue?.trim().isNotEmpty == true &&
        username?.trim().isNotEmpty == true;
  }

  static User buildFallbackUser(
    String username, {
    int? uid,
    String? nickname,
    String? avatarUrl,
  }) {
    final normalized = username.trim();
    return User(
      id: uid != null && uid > 0 ? uid : _stablePositiveId(normalized),
      username: normalized,
      name: _nonBlank(nickname) ?? normalized,
      avatarTemplate:
          _nonBlank(avatarUrl) ??
          (uid != null && uid > 0 ? discuzAvatarUrl(uid) : null),
      trustLevel: 0,
    );
  }

  static User buildFallbackUserFromProfile(EqunDiscuzProfile profile) {
    return buildFallbackUser(
      profile.username,
      uid: profile.uid,
      nickname: profile.nickname,
      avatarUrl: profile.avatarUrl,
    );
  }

  static String discuzAvatarUrl(int uid) {
    return 'https://equn.com/forum/uc_server/avatar.php?uid=$uid&size=middle';
  }

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static int _stablePositiveId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
