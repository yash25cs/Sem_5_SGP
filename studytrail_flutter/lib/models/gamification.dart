/// A row of `streaks` — one per user.
class Streak {
  const Streak({
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastActiveDate,
  });

  final int currentStreak;
  final int bestStreak;
  final DateTime? lastActiveDate;

  factory Streak.fromMap(Map<String, dynamic> m) => Streak(
        currentStreak: (m['current_streak'] as num?)?.toInt() ?? 0,
        bestStreak: (m['best_streak'] as num?)?.toInt() ?? 0,
        lastActiveDate: m['last_active_date'] == null
            ? null
            : DateTime.parse(m['last_active_date'] as String),
      );
}

/// A row of `activity_log` — one per user per day. Powers the heatmap,
/// weekly bars, and the week dots on Achievements.
class ActivityDay {
  const ActivityDay({
    required this.date,
    this.minutesStudied = 0,
    this.tasksCompleted = 0,
    this.xpEarned = 0,
  });

  final DateTime date;
  final int minutesStudied;
  final int tasksCompleted;
  final int xpEarned;

  bool get isActive => minutesStudied > 0 || tasksCompleted > 0;

  /// 0–3 heatmap bucket, saturating at 90 minutes.
  int get intensity {
    if (minutesStudied <= 0) return 0;
    if (minutesStudied < 30) return 1;
    if (minutesStudied < 90) return 2;
    return 3;
  }

  factory ActivityDay.fromMap(Map<String, dynamic> m) => ActivityDay(
        date: DateTime.parse(m['activity_date'] as String),
        minutesStudied: (m['minutes_studied'] as num?)?.toInt() ?? 0,
        tasksCompleted: (m['tasks_completed'] as num?)?.toInt() ?? 0,
        xpEarned: (m['xp_earned'] as num?)?.toInt() ?? 0,
      );
}

/// A `badges` catalog row joined with the caller's `user_badges` state.
/// Named `AchievementBadge` to avoid colliding with Flutter's `Badge` widget.
class AchievementBadge {
  const AchievementBadge({
    required this.id,
    required this.key,
    required this.name,
    this.iconKey,
    this.colorKey,
    this.description,
    this.unlocked = false,
    this.unlockedAt,
    this.progress,
    this.goal,
    this.unit,
  });

  final String id;
  final String key;
  final String name;
  final String? iconKey;
  final String? colorKey;
  final String? description;
  final bool unlocked;
  final DateTime? unlockedAt;

  /// How far along the student is, out of [goal] (`get_badge_progress`,
  /// `0026_achievements_rewards.sql`). Null before that has loaded, or on a
  /// project without it.
  final int? progress;
  final int? goal;

  /// What's being counted ("days", "%", "quizzes"); null for a yes/no badge.
  final String? unit;

  /// 0–1 towards unlocking; 1 once earned, whatever the count says.
  double get fraction {
    if (unlocked) return 1;
    final g = goal, done = progress;
    if (g == null || done == null || g <= 0) return 0;
    return (done / g).clamp(0, 1).toDouble();
  }

  /// "5 / 7 days", "73% / 100%", or null for a yes/no badge.
  String? get progressLabel {
    final g = goal, done = progress;
    if (g == null || done == null || unit == null) return null;
    if (unit == '%') return '$done% / $g%';
    String n(int v) => v.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '${n(done)} / ${n(g)} $unit';
  }

  AchievementBadge withProgress(int progress, int goal, String? unit) =>
      AchievementBadge(
        id: id,
        key: key,
        name: name,
        iconKey: iconKey,
        colorKey: colorKey,
        description: description,
        unlocked: unlocked,
        unlockedAt: unlockedAt,
        progress: progress,
        goal: goal,
        unit: unit,
      );

  factory AchievementBadge.fromMap(Map<String, dynamic> m) {
    // `user_badges` arrives as a list because it's a to-many embed; empty
    // means the badge is still locked for this user.
    final raw = m['user_badges'];
    final mine = raw is List
        ? (raw.isEmpty ? null : raw.first as Map<String, dynamic>)
        : raw as Map<String, dynamic>?;

    return AchievementBadge(
      id: m['id'] as String,
      key: (m['key'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      iconKey: m['icon_key'] as String?,
      colorKey: m['color_key'] as String?,
      description: m['description'] as String?,
      unlocked: (mine?['unlocked'] as bool?) ?? false,
      unlockedAt: mine?['unlocked_at'] == null
          ? null
          : DateTime.parse(mine!['unlocked_at'] as String),
    );
  }
}

/// A row from the `get_class_leaderboard()` RPC — every student since 0029.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.fullName,
    this.avatarInitial,
    this.level = 1,
    this.xp = 0,
    this.totalXp = 0,
    this.goldenBorder = false,
    this.isMe = false,
    this.rank = 0,
  });

  final String userId;
  final String fullName;
  final String? avatarInitial;
  final int level;

  /// XP into the current level — resets on every level-up.
  final int xp;

  /// Every XP ever earned. What the leaderboard ranks and shows.
  final int totalXp;

  /// Bought with XP in the Rewards store.
  final bool goldenBorder;
  final bool isMe;

  /// 1-based position, assigned client-side from the RPC's ordering.
  final int rank;

  String get initial {
    final a = avatarInitial?.trim();
    if (a != null && a.isNotEmpty) return a[0].toUpperCase();
    final n = fullName.trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  factory LeaderboardEntry.fromMap(Map<String, dynamic> m, {int rank = 0}) =>
      LeaderboardEntry(
        userId: m['user_id'] as String,
        fullName: (m['full_name'] as String?) ?? 'Student',
        avatarInitial: m['avatar_initial'] as String?,
        level: (m['level'] as num?)?.toInt() ?? 1,
        xp: (m['xp'] as num?)?.toInt() ?? 0,
        // Older databases (before 0012) don't return total_xp.
        totalXp: (m['total_xp'] as num?)?.toInt() ??
            (m['xp'] as num?)?.toInt() ??
            0,
        goldenBorder: (m['golden_border'] as bool?) ?? false,
        isMe: (m['is_me'] as bool?) ?? false,
        // 0029 returns each row's real rank: the caller's own row can come
        // after the top list, far down.
        rank: (m['rank'] as num?)?.toInt() ?? rank,
      );
}

/// One item in the Rewards store, with how many the caller holds.
class RewardItem {
  const RewardItem({
    required this.key,
    required this.title,
    required this.description,
    required this.costXp,
    this.maxHeld,
    this.held = 0,
    this.used = 0,
  });

  final String key;
  final String title;
  final String description;
  final int costXp;

  /// Most that can be held unused at once; null = no cap.
  final int? maxHeld;

  /// Bought and not yet used.
  final int held;

  /// Used up — streak freezes that covered a missed day.
  final int used;

  bool get atCap => maxHeld != null && held >= maxHeld!;

  factory RewardItem.fromMap(Map<String, dynamic> m) => RewardItem(
        key: m['key'] as String,
        title: (m['title'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        costXp: (m['cost_xp'] as num?)?.toInt() ?? 0,
        maxHeld: (m['max_held'] as num?)?.toInt(),
        held: (m['held'] as num?)?.toInt() ?? 0,
        used: (m['used'] as num?)?.toInt() ?? 0,
      );
}

/// The student's XP balance and the store catalog, from `get_reward_wallet`.
///
/// Balance is XP ever earned minus XP ever spent. Spending never lowers level
/// or leaderboard rank — those read earned XP.
class RewardWallet {
  const RewardWallet({
    this.earned = 0,
    this.spent = 0,
    this.balance = 0,
    this.rewards = const [],
  });

  final int earned;
  final int spent;
  final int balance;
  final List<RewardItem> rewards;

  factory RewardWallet.fromMap(Map<String, dynamic> m) => RewardWallet(
        earned: (m['earned'] as num?)?.toInt() ?? 0,
        spent: (m['spent'] as num?)?.toInt() ?? 0,
        balance: (m['balance'] as num?)?.toInt() ?? 0,
        rewards: [
          for (final r in (m['rewards'] as List? ?? const []))
            RewardItem.fromMap(Map<String, dynamic>.from(r as Map)),
        ],
      );
}

/// A row of `study_sessions` — a completed Pomodoro block.
class StudySession {
  const StudySession({
    required this.id,
    this.subjectId,
    this.lengthMin,
    this.sessionsCount,
    this.focusedMin,
    required this.sessionDate,
  });

  final String id;
  final String? subjectId;
  final int? lengthMin;
  final int? sessionsCount;
  final int? focusedMin;
  final DateTime sessionDate;

  factory StudySession.fromMap(Map<String, dynamic> m) => StudySession(
        id: m['id'] as String,
        subjectId: m['subject_id'] as String?,
        lengthMin: (m['length_min'] as num?)?.toInt(),
        sessionsCount: (m['sessions_count'] as num?)?.toInt(),
        focusedMin: (m['focused_min'] as num?)?.toInt(),
        sessionDate: DateTime.parse(m['session_date'] as String),
      );
}
