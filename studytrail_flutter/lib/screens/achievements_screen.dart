import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../theme/badge_style.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/nav.dart';
import '../widgets/streak_modal.dart';
import 'leaderboard_screen.dart';
import 'rewards_screen.dart';

/// Achievements + class leaderboard screen.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<GamificationStore>().load();
    });
  }

  /// 1240 → "1,240".
  String _thousands(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<GamificationStore>();
    final streak = store.streak;
    final entries = store.leaderboard;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 6),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back,
                    onTap: widget.onBack ??
                        () => Navigator.of(context).maybePop()),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Achievements',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ),
                RoundIconButton(
                  Symbols.featured_seasonal_and_gifts,
                  plain: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RewardsScreen()),
                  ),
                ),
                const SizedBox(width: 6),
                RoundIconButton(
                  Symbols.emoji_events,
                  plain: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const LeaderboardScreen()),
                  ),
                ),
                const SizedBox(width: 6),
                if (store.badges.isNotEmpty)
                  SoftChip('${store.unlockedCount}/${store.badges.length}',
                      icon: Symbols.workspace_premium,
                      tone: ChipTone.amber,
                      small: true),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: p.primary,
              onRefresh: () => context.read<GamificationStore>().load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (store.error != null)
                    ErrorNotice(
                      message: store.error!,
                      onRetry: () => context.read<GamificationStore>().load(),
                    ),

                  // streak banner
                  GestureDetector(
                    onTap: () => showStreakCelebrationSheet(context),
                    child: AppCard(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [p.coral, const Color(0xFFF8951D)]),
                      child: Row(
                        children: [
                          const Icon(Symbols.local_fire_department,
                              color: Colors.white, size: 46, fill: 1),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    streak.currentStreak == 0
                                        ? 'Start your streak'
                                        : '${streak.currentStreak}-day streak 🔥',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text(
                                    streak.currentStreak == 0
                                        ? 'Study today and the counter begins.'
                                        : 'Your best is ${streak.bestStreak} days — keep going!',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.9),
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // week dots — one per day of the current week
                  AppCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final (i, active) in store.weekDots.indexed)
                          Column(children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: active ? p.coralSoft : p.card2,
                              ),
                              child: Icon(
                                  active ? Symbols.check : Symbols.circle,
                                  color: active ? p.coral : p.line2,
                                  size: active ? 18 : 8,
                                  fill: 1),
                            ),
                            const SizedBox(height: 6),
                            Text(_dayLabels[i],
                                style: TextStyle(
                                    color: p.ink3,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  CardHeader('Badges'),
                  if (store.loading && store.badges.isEmpty)
                    const LoadingBlock(height: 180)
                  else if (store.badges.isEmpty)
                    EmptyState(
                      icon: Symbols.workspace_premium,
                      title: 'No badges yet',
                      message:
                          'Badges appear as you study, review cards, and finish quizzes.',
                    )
                  else ...[
                    _BadgeSummary(
                        earned: store.unlockedCount,
                        total: store.badges.length),
                    if (store.nextUp.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _NextUp(
                        badges: store.nextUp.take(3).toList(),
                        onTap: (badge) => _showBadgeDetail(context, badge),
                      ),
                    ],
                    const SizedBox(height: 14),
                    GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      // A fixed height, not an aspect ratio: on a 320 dp
                      // phone a ratio made the tiles too short for the
                      // ring, a two-line name and the count.
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 136,
                      ),
                      children: [
                        for (final badge in store.badgesInOrder)
                          _BadgeTile(
                            badge: badge,
                            onTap: () => _showBadgeDetail(context, badge),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),

                  CardHeader(
                    'Class leaderboard',
                    action: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const LeaderboardScreen()),
                      ),
                      icon: const Icon(Symbols.chevron_right, size: 18),
                      label: const Text('See all',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  if (store.loading && store.leaderboard.isEmpty)
                    const LoadingBlock(height: 120)
                  else if (entries.isEmpty)
                    EmptyState(
                      icon: Symbols.leaderboard,
                      title: store.profile?.classId == null
                          ? 'Not in a class yet'
                          : 'No rankings yet',
                      message: store.profile?.classId == null
                          ? 'Join your class from Study Rooms to see how you rank.'
                          : 'Classmates appear here as they earn XP.',
                    )
                  else
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          for (final entry in entries.take(5))
                            _LeaderRow(
                              entry: entry,
                              xpLabel: '${_thousands(entry.totalXp)} XP',
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBadgeDetail(BuildContext context, AchievementBadge badge) {
    final p = context.p;
    final style = BadgeStyle.of(context, badge);
    final unlocked = badge.unlocked;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: p.shadow,
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: p.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: unlocked
                    ? LinearGradient(
                        colors: [style.color.withValues(alpha: 0.85), style.color],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: unlocked ? null : p.card2,
                boxShadow: unlocked
                    ? [
                        BoxShadow(
                          color: style.color.withValues(alpha: 0.45),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        )
                      ]
                    : null,
              ),
              child: Icon(
                style.icon,
                color: unlocked ? Colors.white : p.ink3.withValues(alpha: 0.6),
                size: 38,
                fill: 1,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge.name,
              style: TextStyle(
                color: p.ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: p.card2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.line, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Symbols.info, size: 18, color: p.primary),
                      const SizedBox(width: 8),
                      Text(
                        'How to earn:',
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    badge.description ??
                        'Keep studying and completing goals to unlock this achievement.',
                    style: TextStyle(
                      color: p.ink2,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            if (!unlocked && badge.goal != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text('Your progress',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ),
                  Text(badge.progressLabel ?? 'Not yet',
                      style: TextStyle(
                          color: style.color,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              ProgressTrack(badge.fraction, color: style.color, height: 10),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: unlocked ? p.greenSoft : p.amberSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (unlocked ? p.green : p.amber).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    unlocked ? Symbols.verified : Symbols.lock_clock,
                    color: unlocked ? p.green : p.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      unlocked
                          ? (badge.unlockedAt != null
                              ? 'Earned! (Unlocked on ${badge.unlockedAt!.day}/${badge.unlockedAt!.month}/${badge.unlockedAt!.year})'
                              : 'Earned! You have completed this achievement.')
                          : (toGo(badge) ?? 'Not earned yet. Complete the requirement to unlock!'),
                      style: TextStyle(
                        color: unlocked ? p.green : p.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "2 days to go", "27% to go", or null when there's no count to give.
@visibleForTesting
String? toGo(AchievementBadge badge) {
  final goal = badge.goal, done = badge.progress, unit = badge.unit;
  if (badge.unlocked || goal == null || done == null || unit == null) {
    return null;
  }
  final left = goal - done;
  if (left <= 0) return 'Almost there — it unlocks on your next study action.';
  if (unit == '%') return '$left% to go.';
  // "1 days" → "1 day"; "XP" stays as it is.
  final name = left == 1 && unit.endsWith('s') ? unit.substring(0, unit.length - 1) : unit;
  final n = left.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '$n $name to go.';
}

/// How many badges are earned, as a count and a bar.
class _BadgeSummary extends StatelessWidget {
  const _BadgeSummary({required this.earned, required this.total});
  final int earned, total;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      child: Row(
        children: [
          IconTile(Symbols.workspace_premium,
              bg: p.amberSoft, fg: p.onAmber, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '$earned',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                    TextSpan(
                        text: ' of $total badges earned',
                        style: TextStyle(
                            color: p.ink2,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 8),
                ProgressTrack(total == 0 ? 0 : earned / total,
                    color: p.amber, height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The locked badges closest to unlocking, each with its bar and what's
/// left.
class _NextUp extends StatelessWidget {
  const _NextUp({required this.badges, required this.onTap});
  final List<AchievementBadge> badges;
  final ValueChanged<AchievementBadge> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.trending_up, color: p.primary, size: 20),
              const SizedBox(width: 8),
              Text('Next up',
                  style: TextStyle(
                      color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          for (final badge in badges)
            InkWell(
              onTap: () => onTap(badge),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Builder(builder: (context) {
                  final style = BadgeStyle.of(context, badge);
                  return Row(
                    children: [
                      IconTile(style.icon,
                          bg: style.color.withValues(alpha: 0.14),
                          fg: style.color,
                          size: 38,
                          radius: 12),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(badge.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: p.ink,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800)),
                                ),
                                if (badge.progressLabel != null)
                                  Text(badge.progressLabel!,
                                      style: TextStyle(
                                          color: p.ink3,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ProgressTrack(badge.fraction,
                                color: style.color, height: 6),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

/// One badge in the grid. Locked, a ring around it fills as the student
/// gets closer, with the count underneath.
class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, this.onTap});

  final AchievementBadge badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final style = BadgeStyle.of(context, badge);
    final unlocked = badge.unlocked;
    final color = style.color;
    final goal = badge.goal, done = badge.progress;
    final count = goal == null || done == null
        ? null
        : badge.unit == null
            ? 'Not yet'
            : badge.unit == '%'
                ? '$done%'
                : '$done/$goal';

    return Tooltip(
      message: badge.description ?? badge.name,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: p.shadowSm,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!unlocked && goal != null)
                      SizedBox.expand(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: badge.fraction),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutCubic,
                          builder: (_, value, _) => CircularProgressIndicator(
                            value: value,
                            strokeWidth: 3.5,
                            strokeCap: StrokeCap.round,
                            color: color,
                            backgroundColor: p.line,
                          ),
                        ),
                      ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: unlocked
                            ? LinearGradient(
                                colors: [color.withValues(alpha: 0.9), color],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight)
                            : null,
                        color: unlocked ? null : p.card2,
                        boxShadow: unlocked
                            ? [
                                BoxShadow(
                                    color: color.withValues(alpha: 0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6))
                              ]
                            : null,
                      ),
                      // Locked, its own icon greyed: what it will be, not a
                      // padlock.
                      child: Icon(style.icon,
                          color: unlocked ? Colors.white : p.ink3.withValues(alpha: 0.6),
                          size: 26,
                          fill: 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(badge.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: unlocked ? p.ink2 : p.ink3,
                      fontSize: 11,
                      height: 1.15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              if (unlocked)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.check_circle, color: p.green, size: 12, fill: 1),
                    const SizedBox(width: 3),
                    Text('Earned',
                        style: TextStyle(
                            color: p.green,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800)),
                  ],
                )
              else if (count != null)
                Text(count,
                    style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.entry, required this.xpLabel});

  final LeaderboardEntry entry;
  final String xpLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final me = entry.isMe;

    // Top three get a trophy tinted by position; everyone else shows a number.
    final trophyColor = switch (entry.rank) {
      1 => p.amber,
      2 => p.ink3,
      3 => p.coral,
      _ => null,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: me ? p.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: trophyColor != null
                ? Icon(Symbols.trophy, color: trophyColor, size: 24, fill: 1)
                : Text('${entry.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.ink2,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          GradAvatar(entry.initial, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                entry.fullName.contains('(You)')
                    ? entry.fullName
                    : (me ? '${entry.fullName} (You)' : entry.fullName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink,
                    fontSize: 14.5,
                    fontWeight: me ? FontWeight.w800 : FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text(xpLabel,
              style: TextStyle(
                  color: me ? p.primary : p.ink2,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
