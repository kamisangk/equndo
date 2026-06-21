import 'topic_keyword_filter.dart';

typedef LoadMoreAction = Future<void> Function();
typedef BoolReader = bool Function();
typedef CountReader = int Function();
typedef AutoLoadMoreDecider = bool Function(LoadMoreAttempt attempt);
typedef CooldownDecider = bool Function(LoadMoreAttempt attempt);

class LoadMoreAttempt {
  const LoadMoreAttempt({
    required this.before,
    required this.after,
    required this.attempts,
    required this.hasMore,
  });

  final int before;
  final int after;
  final int attempts;
  final bool hasMore;

  int get delta => after - before;
}

/// Coordinates near-bottom pagination triggers.
///
/// It keeps scroll listeners thin while centralizing three guardrails:
/// no concurrent load-more runs, optional bounded auto-continuation, and a
/// cooldown while a list remains stuck near the bottom.
class LoadMoreCoordinator {
  LoadMoreCoordinator({this.triggerDistance = 200, this.releaseDistance = 200});

  final double triggerDistance;
  final double releaseDistance;

  bool _isRunning = false;
  bool _isCoolingDown = false;

  bool get isRunning => _isRunning;
  bool get isCoolingDown => _isCoolingDown;

  bool shouldTriggerForDistance(double distanceToEnd) {
    if (distanceToEnd >= releaseDistance) {
      _isCoolingDown = false;
      return false;
    }
    if (_isCoolingDown) return false;
    return distanceToEnd < triggerDistance;
  }

  void resetCooldown() {
    _isCoolingDown = false;
  }

  Future<void> loadMore({
    required LoadMoreAction loadMore,
    required BoolReader hasMore,
    required BoolReader isActive,
    CountReader? progressCount,
    AutoLoadMoreDecider? shouldAutoLoadMore,
    CooldownDecider? shouldCooldown,
  }) async {
    if (_isRunning || _isCoolingDown || !hasMore()) return;

    _isRunning = true;
    try {
      if (shouldAutoLoadMore == null) {
        final before = progressCount?.call();
        await loadMore();
        if (!isActive()) return;
        final after = progressCount?.call();
        if (before != null && after != null) {
          final attempt = LoadMoreAttempt(
            before: before,
            after: after,
            attempts: 0,
            hasMore: hasMore(),
          );
          final cooldown =
              shouldCooldown?.call(attempt) ??
              (attempt.hasMore && attempt.delta <= 0);
          if (cooldown) {
            _isCoolingDown = true;
          }
        }
        return;
      }

      final count = progressCount;
      if (count == null) {
        await loadMore();
        return;
      }

      var attempts = 0;
      while (true) {
        final before = count();
        await loadMore();
        if (!isActive()) return;
        final after = count();
        final attempt = LoadMoreAttempt(
          before: before,
          after: after,
          attempts: attempts,
          hasMore: hasMore(),
        );

        if (!shouldAutoLoadMore(attempt)) {
          if (shouldCooldown?.call(attempt) ?? false) {
            _isCoolingDown = true;
          }
          break;
        }
        attempts++;
      }
    } finally {
      _isRunning = false;
    }
  }
}

class TopicLoadMoreCoordinator extends LoadMoreCoordinator {
  TopicLoadMoreCoordinator({super.triggerDistance, super.releaseDistance});

  Future<void> loadTopicPage({
    required LoadMoreAction loadMore,
    required BoolReader hasMore,
    required BoolReader isActive,
    required CountReader itemCount,
    CountReader? visibleItemCount,
    required bool hasKeywordFilter,
  }) {
    if (!hasKeywordFilter) {
      return super.loadMore(
        loadMore: loadMore,
        hasMore: hasMore,
        isActive: isActive,
        progressCount: itemCount,
      );
    }

    return super.loadMore(
      loadMore: loadMore,
      hasMore: hasMore,
      isActive: isActive,
      progressCount: visibleItemCount ?? itemCount,
      shouldAutoLoadMore: (attempt) => TopicKeywordFilter.shouldAutoLoadMore(
        visibleBefore: attempt.before,
        visibleAfter: attempt.after,
        hasMore: attempt.hasMore,
        attempts: attempt.attempts,
      ),
      shouldCooldown: (attempt) =>
          attempt.hasMore &&
          attempt.attempts >= TopicKeywordFilter.autoLoadMaxAttempts,
    );
  }
}
