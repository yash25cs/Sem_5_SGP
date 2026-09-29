import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';

class _MockCohortStudent {
  final String name;
  final int xp;
  const _MockCohortStudent(this.name, this.xp);
}

/// Full-featured PW-inspired League Leaderboard Screen with Dark Mode support.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  /// Generates a realistic 30-student cohort if the database class leaderboard is sparse.
  static List<LeaderboardEntry> resolveEntries(
    List<LeaderboardEntry> realEntries,
    Profile? profile,
  ) {
    if (realEntries.length >= 5) return realEntries;

    final myXp = profile?.xp ?? 170;
    final myName = (profile?.fullName ?? '').trim().isEmpty
        ? 'You'
        : '${profile!.fullName} (You)';

    // Baseline cohort inspired by the reference screenshot
    final mockClassmates = [
      _MockCohortStudent('Ainam Mushtaq', (myXp + 20).clamp(190, 9999)),
      _MockCohortStudent('Ananya Adivi', (myXp + 4).clamp(174, 9999)),
      _MockCohortStudent(myName, myXp),
      _MockCohortStudent('Paras P', (myXp - 62).clamp(50, 9999)),
      _MockCohortStudent('Charmin Patel', (myXp - 72).clamp(40, 9999)),
      _MockCohortStudent('Rohan Sharma', (myXp - 85).clamp(35, 9999)),
      _MockCohortStudent('Devika Nair', (myXp - 95).clamp(30, 9999)),
      _MockCohortStudent('Kavya Verma', (myXp - 110).clamp(25, 9999)),
      _MockCohortStudent('Aarav Gupta', (myXp - 120).clamp(20, 9999)),
      _MockCohortStudent('Tanvi Joshi', (myXp - 135).clamp(15, 9999)),
    ];

    mockClassmates.sort((a, b) => b.xp.compareTo(a.xp));

    return mockClassmates.indexed.map((e) {
      final (i, item) = e;
      final isMe = item.name.contains('(You)') || item.name == 'You';
      return LeaderboardEntry(
        userId: isMe ? (profile?.id ?? 'me') : 'mock-$i',
        fullName: item.name,
        xp: item.xp,
        isMe: isMe,
        rank: i + 1,
        level: 1,
      );
    }).toList();
  }

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _showBanner = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<GamificationStore>().load();
      }
    });
  }

  /// Calculates days left in the current 14-day reshuffle cycle.
  int get _daysLeftInCycle {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final remaining = 14 - (dayOfYear % 14);
    return remaining == 0 ? 14 : remaining;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final store = context.watch<GamificationStore>();
    final profile = store.profile;
    final entries = LeaderboardScreen.resolveEntries(store.leaderboard, profile);

    final myRank = entries.where((e) => e.isMe).firstOrNull?.rank ?? 3;
    final daysRemaining = _daysLeftInCycle;

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
            icon: const Icon(Symbols.emoji_events,
                color: Color(0xFFFFB300), size: 24),
            onPressed: () => _showLevelUpInfo(context),
          ),
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
            // Warning/Info Banner
            if (_showBanner)
              Container(
                color: isDark ? p.card2 : const Color(0xFFFFF9E6),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Symbols.error,
                        color: Color(0xFFE6A100), size: 20, fill: 1),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Don't worry if there's a small error, missing XP points will be added soon!",
                        style: TextStyle(
                          color: isDark ? p.amber : const Color(0xFF6B4E00),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _showBanner = false),
                      child: Icon(Symbols.close,
                          size: 18, color: isDark ? p.ink2 : const Color(0xFF6B4E00)),
                    ),
                  ],
                ),
              ),

            // Top Stage / Podium with light ray & Level Badges
            _LeaguePodiumStage(currentLevel: 1),

            const SizedBox(height: 12),

            // Zone Slider Card (Safety Zone vs Promotion Zone)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ZoneCard(
                myRank: myRank,
                daysRemaining: daysRemaining,
                onInfoTap: () => _showLevelUpInfo(context),
              ),
            ),

            const SizedBox(height: 18),

            // Leaderboard List
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (final entry in entries)
                    _LeaderboardItemTile(entry: entry),
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

/// The decorative Stage with light beam and level badges (Level 1 Bronze, Level 2 Silver, Level 3 Gold).
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
              child: _LevelHexBadge(level: 2, color: const Color(0xFF90A4AE)),
            ),
          ),

          // Side badge right: Level 3
          Positioned(
            right: 16,
            top: 54,
            child: Opacity(
              opacity: 0.3,
              child: _LevelHexBadge(level: 3, color: const Color(0xFFB0BEC5), size: 30),
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

/// Zone Slider Card showing Safety Zone vs Promotion Zone and user's pinpoint rank.
class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.myRank,
    required this.daysRemaining,
    required this.onInfoTap,
  });

  final int myRank;
  final int daysRemaining;
  final VoidCallback onInfoTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 30 ranks total. Ranks 1-15: Promotion Zone (Green). Ranks 16-30: Safety Zone (Orange).
    // The bar runs from left (rank 30) to right (rank 1).
    final progress = ((30 - myRank) / 29).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.line, width: 1.2),
        boxShadow: p.shadowSm,
      ),
      child: Column(
        children: [
          // Header: Leaderboard updates in X days (i)
          InkWell(
            onTap: onInfoTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Leaderboard updates in $daysRemaining days',
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Symbols.info, size: 16, color: p.ink2),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Zone Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Safety zone',
                style: TextStyle(
                  color: p.ink2,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Promotion zone',
                style: TextStyle(
                  color: p.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Zone bar + Floating Pin
          LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              final pinLeft = (barWidth * progress) - 40;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Floating Rank Tooltip Badge
                  Padding(
                    padding: EdgeInsets.only(
                      left: pinLeft.clamp(0.0, barWidth - 84),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark ? p.card2 : const Color(0xFFE8F1FC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF63A0F2), width: 1.5),
                      ),
                      child: Text(
                        'Rank: $myRank',
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Horizontal 2-tone track
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Row(
                        children: [
                          // Safety Zone (Orange)
                          Expanded(
                            flex: 1,
                            child: Container(
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFBBF24),
                                borderRadius: BorderRadius.horizontal(
                                    left: Radius.circular(999)),
                              ),
                            ),
                          ),
                          // Promotion Zone (Green)
                          Expanded(
                            flex: 1,
                            child: Container(
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF86EFAC),
                                borderRadius: BorderRadius.horizontal(
                                    right: Radius.circular(999)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Blue Circular Slider Thumb
                      Positioned(
                        left: (barWidth * progress - 8).clamp(0.0, barWidth - 16),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF3B82F6)
                                    .withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Rank labels (30, 15, 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('30',
                          style: TextStyle(
                              color: p.ink3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      Text('Ranks',
                          style: TextStyle(
                              color: p.ink3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      Text('15',
                          style: TextStyle(
                              color: p.ink3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      Text('Ranks',
                          style: TextStyle(
                              color: p.ink3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      Text('1',
                          style: TextStyle(
                              color: p.ink3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Single Student Rank Row.
class _LeaderboardItemTile extends StatelessWidget {
  const _LeaderboardItemTile({required this.entry});
  final LeaderboardEntry entry;

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
          color: isMe ? p.primary : p.line,
          width: isMe ? 1.6 : 1,
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

          // Student Name
          Expanded(
            child: Text(
              entry.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.ink,
                fontSize: 14.5,
                fontWeight: isMe ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),

          // XP Badge Pill (190 XP)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${entry.xp}',
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

/// The Level Up Information Modal (From Image 4).
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
                        'Earn XP by completing daily tasks, reviewing flashcards, and taking quizzes. Compete with classmates and climb the leaderboard!',
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
                      'XP is like a reward coin. You earn it every time you complete study sessions, solve flashcards, or take a quiz.',
                ),
                _DashedStepConnector(),

                // Milestone 2: Leaderboard
                _InfoRoadmapStep(
                  iconBg: const Color(0xFFFEF3C7),
                  icon: Symbols.emoji_events,
                  iconColor: const Color(0xFFD97706),
                  title: 'Leaderboard',
                  description:
                      "You're grouped with 30 students from your batch. Your XP decides your rank in the group.",
                ),
                _DashedStepConnector(),

                // Milestone 3: Reshuffling
                _InfoRoadmapStep(
                  iconBg: const Color(0xFFDCFCE7),
                  icon: Symbols.military_tech,
                  iconColor: const Color(0xFF15803D),
                  title: 'Reshuffling',
                  description:
                      'The Leaderboard resets every 14 days. Your leaderboard rank at the end of this period decides if you get promoted, stay, or get demoted.',
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
