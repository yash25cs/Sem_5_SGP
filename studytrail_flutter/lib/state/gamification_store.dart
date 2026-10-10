import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Achievements screen: streak, week dots, badge grid, and the
/// leaderboard.
class GamificationStore extends AsyncStore {
  GamificationStore({GamificationRepository? game, ProfileRepository? profiles})
      : _game = game ?? const GamificationRepository(),
        _profiles = profiles ?? const ProfileRepository();

  final GamificationRepository _game;
  final ProfileRepository _profiles;

  Profile? _profile;
  Streak _streak = const Streak();
  List<AchievementBadge> _badges = const [];
  List<LeaderboardEntry> _leaderboard = const [];
  List<ActivityDay> _recent = const [];
  List<String> _newlyUnlocked = const [];

  Profile? get profile => _profile;
  Streak get streak => _streak;
  List<AchievementBadge> get badges => _badges;
  List<AchievementBadge> get unlockedBadges =>
      _badges.where((b) => b.unlocked).toList();
  List<LeaderboardEntry> get leaderboard => _leaderboard;

  /// Badge keys this load unlocked for the first time — empty on every visit
  /// after the one that earned them.
  List<String> get newlyUnlocked => _newlyUnlocked;

  int get unlockedCount => unlockedBadges.length;

  /// Locked badges closest to unlocking first, for "Next up". Only ones with
  /// progress to show.
  List<AchievementBadge> get nextUp => [
        for (final b in _badges)
          if (!b.unlocked && b.goal != null) b,
      ]..sort((a, b) => b.fraction.compareTo(a.fraction));

  /// Earned first (newest first), then the rest by how close they are — the
  /// grid order.
  List<AchievementBadge> get badgesInOrder {
    final earned = unlockedBadges
      ..sort((a, b) => (b.unlockedAt ?? DateTime(0))
          .compareTo(a.unlockedAt ?? DateTime(0)));
    final locked = [
      for (final b in _badges)
        if (!b.unlocked) b,
    ]..sort((a, b) => b.fraction.compareTo(a.fraction));
    return [...earned, ...locked];
  }

  /// True/false per day for the current week, Monday-first — the row of dots
  /// under the streak counter.
  List<bool> get weekDots {
    final today = DateTime.now();
    final monday = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - 1));
    final active = {
      for (final d in _recent)
        if (d.isActive) DateTime(d.date.year, d.date.month, d.date.day),
    };
    return List.generate(
      7,
      (i) => active.contains(monday.add(Duration(days: i))),
    );
  }

  /// The caller's own row, if the leaderboard came back.
  LeaderboardEntry? get myRank =>
      _leaderboard.where((e) => e.isMe).firstOrNull;

  RewardWallet? _wallet;
  RewardWallet? get wallet => _wallet;

  /// Loaded separately from [load]: only the Rewards screen needs it.
  Future<void> loadWallet() async {
    try {
      _wallet = await _game.getRewardWallet();
      clearError();
      notifyListeners();
    } catch (e) {
      setError(e);
    }
  }

  /// Returns true when the purchase went through; [error] says why not.
  Future<bool> redeem(String key) => runMutation(() async {
        _wallet = await _game.redeemReward(key);
      });

  /// Two rounds instead of six. Each read used to wait for the one before it,
  /// and at ~300 ms a round trip to the Sydney database that was 1.8 s
  /// before Rewards, Leaderboard or Achievements showed anything. Only the
  /// badge list has to wait — for [GamificationRepository.evaluateBadges], which
  /// can unlock new ones. Each read still falls back on its own failure.
  Future<void> load() => runLoad(() async {
        final unlocked = _orElse(_game.evaluateBadges(), const <String>[]);
        final results = await Future.wait<Object?>([
          unlocked,
          // Badges after the evaluation, so a badge it just unlocked shows.
          unlocked.then(
              (_) => _orElse(_game.getBadges(), const <AchievementBadge>[])),
          _orElse<Profile?>(_profiles.getMyProfile(), _profile),
          _orElse(_game.getStreak(), const Streak()),
          _orElse(_game.getRecentActivity(days: 14), const <ActivityDay>[]),
          _orElse(_game.getLeaderboard(), const <LeaderboardEntry>[]),
          // Progress needs no waiting on the evaluation: it is computed from
          // the same rows, not from what was unlocked.
          _orElse(_game.getBadgeProgress(),
              const <String, (int, int, String?)>{}),
        ]);
        _newlyUnlocked = results[0] as List<String>;
        final badges = results[1] as List<AchievementBadge>;
        final progress = results[6] as Map<String, (int, int, String?)>;
        _badges = [
          for (final b in
              badges.isEmpty ? GamificationRepository.defaultBadges : badges)
            if (progress[b.key] case (final done, final goal, final unit))
              b.withProgress(done, goal, unit)
            else
              b,
        ];
        _profile = results[2] as Profile?;
        _streak = results[3] as Streak;
        _recent = results[4] as List<ActivityDay>;
        _leaderboard = results[5] as List<LeaderboardEntry>;
      });

  /// [future], or [fallback] if it fails — one failed read shouldn't blank
  /// the others.
  static Future<T> _orElse<T>(Future<T> future, T fallback) =>
      future.catchError((Object _) => fallback);
}
