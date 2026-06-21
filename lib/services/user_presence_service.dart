/// App-side equivalent of Discourse's user-present check.
///
/// Discourse only sends `Discourse-Present` when the page is visible and the
/// user has interacted with it recently. Keep this service narrow: it tracks
/// foreground state plus the last user input timestamp, and request
/// interceptors can read [isPresent] synchronously.
class UserPresenceService {
  UserPresenceService._internal();

  static final UserPresenceService _instance = UserPresenceService._internal();
  factory UserPresenceService() => _instance;

  static const Duration userUnseenTime = Duration(seconds: 60);
  static const Duration _activityDebounce = Duration(seconds: 1);

  bool _isForeground = true;
  DateTime _lastUserActivityAt = DateTime.now();

  bool get isPresent => _isPresentAt(DateTime.now());

  void setForeground(bool isForeground, {bool countAsActivity = false}) {
    _isForeground = isForeground;
    if (isForeground && countAsActivity) {
      markUserActivity();
    }
  }

  void markUserActivity() {
    if (!_isForeground) return;

    final now = DateTime.now();
    if (_isPresentAt(now) &&
        now.difference(_lastUserActivityAt) < _activityDebounce) {
      return;
    }
    _lastUserActivityAt = now;
  }

  bool _isPresentAt(DateTime now) {
    if (!_isForeground) return false;
    return now.difference(_lastUserActivityAt) < userUnseenTime;
  }
}
