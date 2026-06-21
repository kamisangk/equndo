import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../services/discuz/equn_discuz_models.dart';
import '../services/discuz/equn_discuz_service.dart';

final equnDiscuzServiceProvider = Provider<EqunDiscuzService>((ref) {
  return EqunDiscuzService();
});

final equnGuideFilterProvider = StateProvider<EqunGuideFilter>((ref) {
  return EqunGuideFilter.latestReplies;
});

final equnGuideTopicsProvider = FutureProvider<List<EqunTopicSummary>>((
  ref,
) async {
  final service = ref.watch(equnDiscuzServiceProvider);
  final filter = ref.watch(equnGuideFilterProvider);
  return service.fetchGuideTopics(filter);
});

final equnForumGroupsProvider = FutureProvider<List<EqunForumGroup>>((
  ref,
) async {
  final service = ref.watch(equnDiscuzServiceProvider);
  return service.fetchForumGroups();
});

final equnForumTopicsProvider = FutureProvider.family<EqunForumTopicPage, int>((
  ref,
  fid,
) async {
  final service = ref.watch(equnDiscuzServiceProvider);
  return service.fetchForumTopics(fid);
});

final equnThreadDetailProvider = FutureProvider.family<EqunThreadDetail, int>((
  ref,
  tid,
) async {
  final service = ref.watch(equnDiscuzServiceProvider);
  return service.fetchThreadDetail(tid);
});
