import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Achievements screen: streak, week dots, badge grid, and the
/// class leaderboard.
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

  Future<void> load() => runLoad(() async {
        try {
          _newlyUnlocked = await _game.evaluateBadges();
        } catch (_) {
          _newlyUnlocked = const [];
        }

        try {
          _profile = await _profiles.getMyProfile();
        } catch (_) {}

        try {
          _streak = await _game.getStreak();
        } catch (_) {
          _streak = const Streak();
        }

        try {
          _badges = await _game.getBadges();
        } catch (_) {
          _badges = GamificationRepository.defaultBadges;
        }
        if (_badges.isEmpty) {
          _badges = GamificationRepository.defaultBadges;
        }

        try {
          _recent = await _game.getRecentActivity(days: 14);
        } catch (_) {
          _recent = const [];
        }

        try {
          _leaderboard = await _game.getLeaderboard();
        } catch (_) {
          _leaderboard = const [];
        }
      });
}
