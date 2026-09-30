import '../../models/models.dart';
import '../supabase_client.dart';

/// Streaks, XP, badges, leaderboard, and study sessions — the gamification
/// layer.
///
/// Reads only, plus two RPCs. Nothing here writes XP, activity, or a badge
/// directly: `0008_rewards.sql` revokes the client's INSERT/UPDATE on
/// `activity_log`, `streaks`, `user_badges`, and `study_sessions`, so the
/// reward RPCs are the only path in.
class GamificationRepository {
  const GamificationRepository();

  Future<Streak> getStreak() async {
    final row = await db
        .from('streaks')
        .select()
        .eq('user_id', requireUserId)
        .maybeSingle();
    return row == null
        ? const Streak()
        : Streak.fromMap(row);
  }

  /// Last 60 days of activity for the heatmap and weekly bars.
  Future<List<ActivityDay>> getRecentActivity({int days = 60}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days - 1));
    final rows = await db
        .from('activity_log')
        .select()
        .gte('activity_date', _dateOnly(cutoff))
        .order('activity_date', ascending: true);
    return rows.map(ActivityDay.fromMap).toList();
  }

  /// The default 10-badge catalog fallback.
  static const defaultBadges = <AchievementBadge>[
    AchievementBadge(
      id: 'badge-first_step',
      key: 'first_step',
      name: 'First Step',
      iconKey: 'flag',
      colorKey: 'sky',
      description: 'Complete your first study task.',
    ),
    AchievementBadge(
      id: 'badge-week_warrior',
      key: 'week_warrior',
      name: 'Week Warrior',
      iconKey: 'local_fire_department',
      colorKey: 'amber',
      description: 'Maintain a 7-day streak.',
    ),
    AchievementBadge(
      id: 'badge-quiz_ace',
      key: 'quiz_ace',
      name: 'Quiz Ace',
      iconKey: 'quiz',
      colorKey: 'violet',
      description: 'Score 100% on any quiz.',
    ),
    AchievementBadge(
      id: 'badge-card_master',
      key: 'card_master',
      name: 'Card Master',
      iconKey: 'style',
      colorKey: 'emerald',
      description: 'Review 100 flashcards.',
    ),
    AchievementBadge(
      id: 'badge-night_owl',
      key: 'night_owl',
      name: 'Night Owl',
      iconKey: 'nightlight',
      colorKey: 'indigo',
      description: 'Study after 10 PM.',
    ),
    AchievementBadge(
      id: 'badge-early_bird',
      key: 'early_bird',
      name: 'Early Bird',
      iconKey: 'wb_sunny',
      colorKey: 'orange',
      description: 'Study before 7 AM.',
    ),
    AchievementBadge(
      id: 'badge-focused_mind',
      key: 'focused_mind',
      name: 'Focused Mind',
      iconKey: 'self_improvement',
      colorKey: 'teal',
      description: 'Finish 10 Pomodoro sessions.',
    ),
    AchievementBadge(
      id: 'badge-roadmap_ready',
      key: 'roadmap_ready',
      name: 'Roadmap Ready',
      iconKey: 'map',
      colorKey: 'rose',
      description: 'Generate your first AI roadmap.',
    ),
    AchievementBadge(
      id: 'badge-curious_learner',
      key: 'curious_learner',
      name: 'Curious Learner',
      iconKey: 'chat',
      colorKey: 'cyan',
      description: 'Ask the AI tutor 25 questions.',
    ),
    AchievementBadge(
      id: 'badge-goal_crusher',
      key: 'goal_crusher',
      name: 'Goal Crusher',
      iconKey: 'emoji_events',
      colorKey: 'gold',
      description: 'Reach 100% on a goal.',
    ),
  ];

  /// The badge catalog, each with whether the caller has it. For "my badges",
  /// filter [unlocked] client-side.
  ///
  /// PostgREST embeds are left outer joins by default.
  Future<List<AchievementBadge>> getBadges({bool onlyUnlocked = false}) async {
    List<AchievementBadge> all = [];
    try {
      final rows = await db
          .from('badges')
          .select('*, user_badges(*)')
          .order('key', ascending: true);
      all = [
        for (final r in rows)
          AchievementBadge.fromMap(r),
      ];
    } catch (_) {
      // Supabase table or relation query failed; fallback will populate.
    }

    if (all.isEmpty) {
      // Check user_badges table for current user if available
      final unlockedMap = <String, (bool, DateTime?)>{};
      try {
        final uid = currentUserId;
        if (uid != null) {
          final rows = await db
              .from('user_badges')
              .select('badge_id, unlocked, unlocked_at, badges(key)')
              .eq('user_id', uid);
          for (final row in rows as List) {
            final key = row['badges']?['key'] as String?;
            if (key != null) {
              final unl = (row['unlocked'] as bool?) ?? false;
              final at = row['unlocked_at'] == null
                  ? null
                  : DateTime.parse(row['unlocked_at'] as String);
              unlockedMap[key] = (unl, at);
            }
          }
        }
      } catch (_) {}

      all = [
        for (final b in defaultBadges)
          AchievementBadge(
            id: b.id,
            key: b.key,
            name: b.name,
            iconKey: b.iconKey,
            colorKey: b.colorKey,
            description: b.description,
            unlocked: unlockedMap[b.key]?.$1 ?? b.unlocked,
            unlockedAt: unlockedMap[b.key]?.$2 ?? b.unlockedAt,
          ),
      ];
    }

    return onlyUnlocked ? all.where((b) => b.unlocked).toList() : all;
  }

  /// Re-checks every badge condition against the database and unlocks whatever
  /// is genuinely earned, returning the keys unlocked *by this call* — the cue
  /// for an "unlocked!" toast.
  ///
  /// Replaces the old `unlock_badge(key)` RPC, which took the client's word for
  /// which badge to grant. The reward RPCs run the same check server-side, so
  /// this is only needed for conditions no reward touches (roadmap generated,
  /// questions asked, goal finished).
  Future<List<String>> evaluateBadges() async {
    final result = await db.rpc('evaluate_badges');
    return (result as List?)?.cast<String>() ?? const [];
  }

  /// Classmates ordered by XP. `is_me` comes from the RPC; rank is assigned
  /// client-side from the returned order.
  Future<List<LeaderboardEntry>> getLeaderboard({int limit = 20}) async {
    final result =
        await db.rpc('get_class_leaderboard', params: {'limit_count': limit});
    final rows = (result as List).cast<Map<String, dynamic>>();
    return rows.indexed
        .map((e) => LeaderboardEntry.fromMap(e.$2, rank: e.$1 + 1))
        .toList();
  }

  /// XP balance and the rewards catalog with what the caller holds.
  Future<RewardWallet> getRewardWallet() async {
    final res = await db.rpc('get_reward_wallet');
    return RewardWallet.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// Spends XP on a reward. The server checks the balance and the holding
  /// cap, and returns the updated wallet.
  Future<RewardWallet> redeemReward(String key) async {
    final res = await db.rpc('redeem_reward', params: {'p_key': key});
    return RewardWallet.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// Completed Pomodoro sessions, newest first.
  Future<List<StudySession>> getStudySessions({int limit = 50}) async {
    final rows = await db
        .from('study_sessions')
        .select('*, subjects(name)')
        .eq('user_id', requireUserId)
        .order('started_at', ascending: false)
        .limit(limit);
    return rows.map(StudySession.fromMap).toList();
  }

  /// Persists one finished Pomodoro block.
  ///
  /// `record_focus_session` validates the length, rejects a subject that isn't
  /// the caller's, caps the day's logged focus, then derives the XP from the
  /// minutes — so the client reports what it did, not what it earned. The
  /// returned row has no embedded subject name; re-read the list if you need it.
  Future<StudySession> recordSession({
    String? subjectId,
    int? lengthMin,
    int? focusedMin,
  }) async {
    final row = await db.rpc('record_focus_session', params: {
      'p_subject': subjectId,
      'p_length_min': lengthMin ?? 25,
      'p_focused_min': focusedMin,
    });
    return StudySession.fromMap(
      row is List
          ? row.first as Map<String, dynamic>
          : row as Map<String, dynamic>,
    );
  }

  static String _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().split('T').first;
}
