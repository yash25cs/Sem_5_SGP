import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/data_states.dart';
import 'buddy_room_screen.dart';

/// The class leaderboard: everyone in the student's class, ranked by total XP
/// earned (`get_class_leaderboard`).
///
/// Only real classmates are listed. An earlier version padded a sparse class
/// with nine invented names and showed a "promotion zone" and a 14-day
/// reshuffle that nothing in the backend implements; a leaderboard that makes
/// people up can't be trusted about anything else either.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<GamificationStore>().load();
      }
    });
  }

  void _openRooms() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (routeCtx) =>
          BuddyRoomScreen(onBack: () => Navigator.of(routeCtx).pop()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<GamificationStore>();
    final profile = store.profile;
    final entries = store.leaderboard;
    final inClass = profile?.classId != null;

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Symbols.arrow_back_ios_new, size: 20, color: p.ink),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
        title: Text(
          'Leaderboard',
          style: TextStyle(
            color: p.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Symbols.info, color: p.ink2, size: 22),
            onPressed: () => _showLevelUpInfo(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: p.primary,
        onRefresh: () => context.read<GamificationStore>().load(),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _LeaguePodiumStage(currentLevel: profile?.level ?? 1),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: store.loading && entries.isEmpty
                  ? const LoadingBlock(height: 180)
                  : !inClass && profile != null
                      ? EmptyState(
                          icon: Symbols.groups,
                          title: 'Join your class to compete',
                          message: 'The leaderboard ranks you against '
                              'classmates. Pick your class in Study Rooms.',
                          actionLabel: 'Choose my class',
                          onAction: _openRooms,
                        )
                      : entries.isEmpty
                          ? const EmptyState(
                              icon: Symbols.leaderboard,
                              title: 'No rankings yet',
                              message:
                                  'Pull down to refresh once you have some XP.',
                            )
                          : Column(
                              children: [
                                _RankCard(entries: entries),
                                const SizedBox(height: 18),
                                for (final entry in entries)
                                  _LeaderboardItemTile(entry: entry),
                                if (entries.length < 3) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Only ${entries.length} of your class '
                                    '${entries.length == 1 ? 'is' : 'are'} on '
                                    'StudyTrail so far. Share the app and the '
                                    'race gets interesting.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: p.ink3,
                                        fontSize: 12.5,
                                        height: 1.4),
                                  ),
                                ],
                              ],
                            ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showLevelUpInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const LevelUpInfoSheet(),
    );
  }
}

/// The stage: the student's current level on the pedestal, the next two
/// levels faded behind it.
class _LeaguePodiumStage extends StatelessWidget {
  const _LeaguePodiumStage({required this.currentLevel});
  final int currentLevel;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [p.card, p.bg]
              : [const Color(0xFFE3EDF9), const Color(0xFFF4F7FB)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Light beam
          Positioned(
            top: 0,
            bottom: 24,
            width: 140,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFFE082).withValues(alpha: isDark ? 0.2 : 0.45),
                    const Color(0xFFFFF9C4).withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ),

          // Disc / Light source emitter
          Positioned(
            top: 10,
            child: Container(
              width: 90,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD54F),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFCA28).withValues(alpha: 0.6),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),

          // Side badge left: Level 2
          Positioned(
            right: 48,
            top: 50,
            child: Opacity(
              opacity: 0.4,
              child: _LevelHexBadge(level: currentLevel + 1, color: const Color(0xFF90A4AE)),
            ),
          ),

          // Side badge right: Level 3
          Positioned(
            right: 16,
            top: 54,
            child: Opacity(
              opacity: 0.3,
              child: _LevelHexBadge(level: currentLevel + 2, color: const Color(0xFFB0BEC5), size: 30),
            ),
          ),

          // Main Center Stage Pedestal
          Positioned(
            bottom: 6,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LevelHexBadge(
                  level: currentLevel,
                  color: const Color(0xFFD84315),
                  size: 44,
                ),
                const SizedBox(height: 6),
                Text(
                  'Level $currentLevel',
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                // Blue cylinder pedestal
                Container(
                  width: 92,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E63B8),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF64B5F6),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A3F7A).withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelHexBadge extends StatelessWidget {
  const _LevelHexBadge({
    required this.level,
    required this.color,
    this.size = 38,
  });

  final int level;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$level',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.48,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// Where the student stands: rank, class size, and the XP to the next place.
class _RankCard extends StatelessWidget {
  const _RankCard({required this.entries});

  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final me = entries.where((e) => e.isMe).firstOrNull;
    final leader = entries.first;

    final String headline;
    final String detail;
    if (me == null) {
      headline = '${entries.length} classmates ranked';
      detail = 'Earn XP to appear on the board.';
    } else if (me.rank == 1) {
      headline = "You're #1 of ${entries.length}";
      detail = entries.length > 1
          ? '${me.totalXp - entries[1].totalXp} XP ahead of #2. Keep it up!'
          : 'Top of the class.';
    } else {
      final above = entries[me.rank - 2];
      final gap = above.totalXp - me.totalXp;
      headline = "You're #${me.rank} of ${entries.length}";
      detail = gap <= 0
          ? 'Level with #${above.rank}. One more task takes the spot.'
          : '$gap XP behind #${above.rank}. A couple of tasks closes that.';
    }

    final progress = me == null || leader.totalXp <= 0
        ? 0.0
        : (me.totalXp / leader.totalXp).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.line, width: 1.2),
        boxShadow: p.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: TextStyle(
              color: p.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(detail,
              style: TextStyle(color: p.ink2, fontSize: 13, height: 1.35)),
          if (me != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: p.card2,
                color: p.primary,
              ),
            ),
            const SizedBox(height: 6),
            // Wraps rather than overflowing when both figures are large.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text('You · ${me.totalXp} XP',
                    style: TextStyle(
                        color: p.ink3,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
                Text('#1 · ${leader.totalXp} XP',
                    style: TextStyle(
                        color: p.ink3,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Single Student Rank Row.
class _LeaderboardItemTile extends StatelessWidget {
  const _LeaderboardItemTile({required this.entry});
  final LeaderboardEntry entry;

  static const _gold = Color(0xFFEAB308);

  Color _rankBadgeColor(int rank) {
    if (rank == 1) return const Color(0xFFF59E0B); // Gold / Yellow
    if (rank == 2) return const Color(0xFF0284C7); // Blue
    if (rank == 3) return const Color(0xFF10B981); // Green
    return const Color(0xFFA7D4B6); // Soft green
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rank = entry.rank;
    final isMe = entry.isMe;
    final badgeColor = _rankBadgeColor(rank);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? (isDark ? p.primary.withValues(alpha: 0.25) : const Color(0xFFE8F1FC))
            : p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: entry.goldenBorder
              ? _gold
              : isMe
                  ? p.primary
                  : p.line,
          width: entry.goldenBorder || isMe ? 1.8 : 1,
        ),
      ),
      child: Row(
        children: [
          // Hexagon Rank Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Student name (with the golden border reward if they bought it),
          // and the level under it rather than beside it, so a long name
          // keeps its room on a narrow phone.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isMe ? '${entry.fullName} (You)' : entry.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: isMe ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                    ),
                    if (entry.goldenBorder) ...[
                      const SizedBox(width: 4),
                      const Icon(Symbols.military_tech,
                          size: 16, color: _gold, fill: 1),
                    ],
                  ],
                ),
                Text(
                  'Level ${entry.level}',
                  style: TextStyle(
                    color: p.ink3,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // XP Badge Pill (190 XP)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${entry.totalXp}',
                style: TextStyle(
                  color: p.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: p.card2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'XP',
                  style: TextStyle(
                    color: p.ink2,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How XP, levels and the leaderboard actually work.
class LevelUpInfoSheet extends StatelessWidget {
  const LevelUpInfoSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: p.line2,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Information',
                style: TextStyle(
                  color: p.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                icon: Icon(Symbols.close, size: 20, color: p.ink),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Divider(height: 16, color: p.line),

          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 8),

                // Level Up Title banner
                Center(
                  child: Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Symbols.star,
                              color: Color(0xFF3B82F6), size: 28),
                          const SizedBox(width: 8),
                          Text(
                            'Level Up!',
                            style: TextStyle(
                              color: p.primary,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'MAKING LEARNING FUN',
                        style: TextStyle(
                          color: p.ink2,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Earn XP by completing daily tasks, focusing with the Pomodoro timer, reviewing flashcards, and taking quizzes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.ink2,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Milestone 1: XP
                _InfoRoadmapStep(
                  iconBg: const Color(0xFFE0E7FF),
                  icon: Symbols.diamond,
                  iconColor: const Color(0xFF4338CA),
                  title: 'XP or Experience Points',
                  description:
                      '15 XP per daily task, 1 XP per focused Pomodoro minute, 2 XP per due flashcard reviewed, and up to 10 XP per correct quiz answer. The server calculates every award.',
                ),
                _DashedStepConnector(),

                // Milestone 2: Leaderboard
                _InfoRoadmapStep(
                  iconBg: const Color(0xFFFEF3C7),
                  icon: Symbols.emoji_events,
                  iconColor: const Color(0xFFD97706),
                  title: 'Levels',
                  description:
                      'Level 2 takes 500 XP, and each level after that needs 20% more than the one before.',
                ),
                _DashedStepConnector(),

                // Milestone 3: Reshuffling
                _InfoRoadmapStep(
                  iconBg: const Color(0xFFDCFCE7),
                  icon: Symbols.military_tech,
                  iconColor: const Color(0xFF15803D),
                  title: 'Class leaderboard',
                  description:
                      'Everyone in your class, ranked by total XP ever earned. Spending XP on rewards never lowers your rank. Leave your class to stop appearing.',
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRoadmapStep extends StatelessWidget {
  const _InfoRoadmapStep({
    required this.iconBg,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final Color iconBg;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: iconBg,
            shape: BoxShape.circle,
            border: Border.all(color: iconColor.withValues(alpha: 0.3), width: 2),
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: p.ink2,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashedStepConnector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      margin: const EdgeInsets.only(left: 24),
      height: 36,
      width: 2,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          5,
          (_) => Container(
            width: 2,
            height: 4,
            color: p.line2,
          ),
        ),
      ),
    );
  }
}
