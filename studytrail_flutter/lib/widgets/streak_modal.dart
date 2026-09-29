import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../state/stores.dart';
import '../theme/app_theme.dart';

/// Shows the PW-inspired Streak Celebration bottom sheet.
void showStreakCelebrationSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const StreakModalSheet(),
  );
}

class StreakModalSheet extends StatelessWidget {
  const StreakModalSheet({super.key});

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final homeStore = context.watch<HomeStore>();
    final gamificationStore = context.watch<GamificationStore>();

    final streak = homeStore.streak.currentStreak;
    final done = homeStore.doneCount;
    final total = homeStore.tasks.length;
    final isStreakCompletedToday = done > 0 && done >= total;

    // Days completed this week (M to S) from gamificationStore if loaded
    final todayWeekday = DateTime.now().weekday; // 1 = Mon, 7 = Sun
    final weekDots = gamificationStore.weekDots;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
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
          const SizedBox(height: 8),

          // Close button bar
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: p.card2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Symbols.close, size: 18, color: p.ink2),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          // Main Streak Card (Adapted for Light & Dark mode)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF241C14) : const Color(0xFFFEF6E8),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? const Color(0xFF4A3416) : const Color(0xFFFDE4B8),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Big streak number + Day Streak! + Share icon
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Big orange streak numeral with fire
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '$streak',
                          style: const TextStyle(
                            color: Color(0xFFF57C00),
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Symbols.local_fire_department,
                          color: Color(0xFFFF9800),
                          size: 32,
                          fill: 1,
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Day Streak!!',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFFFFD180)
                                  : const Color(0xFF4A3416),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Every day counts!\nkeep the momentum going!',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFFFFCC80)
                                  : const Color(0xFF8A6C44),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => _shareStreak(streak),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? p.card2 : Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? p.line : const Color(0xFFFDE4B8),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Symbols.share,
                          size: 18,
                          color: isDark ? p.ink : const Color(0xFF4A3416),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Weekday circles (M T W T F S S)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (index) {
                    final dayLabel = _days[index];
                    final dayNum = index + 1; // 1 = Mon, 7 = Sun
                    final isPast = dayNum < todayWeekday;
                    final isToday = dayNum == todayWeekday;
                    final isSunday = index == 6;

                    final isActive = weekDots.length > index
                        ? weekDots[index]
                        : (isToday ? isStreakCompletedToday : isPast);

                    return Column(
                      children: [
                        Text(
                          dayLabel,
                          style: TextStyle(
                            color: isToday
                                ? const Color(0xFF1E5BB8)
                                : const Color(0xFF8A6C44),
                            fontSize: 12,
                            fontWeight: isToday
                                ? FontWeight.w900
                                : FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? const Color(0xFFFF5722)
                                : (isDark ? p.card : Colors.white),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFFFF7043)
                                  : isToday
                                      ? const Color(0xFF1E5BB8)
                                      : (isDark ? p.line : const Color(0xFFE2C89E)),
                              width: isToday ? 2 : 1.5,
                            ),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFFF5722)
                                          .withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: isActive
                                ? const Icon(
                                    Symbols.local_fire_department,
                                    color: Colors.white,
                                    size: 22,
                                    fill: 1,
                                  )
                                : isSunday
                                    ? const Icon(
                                        Symbols.sports_score,
                                        color: Color(0xFFD4B180),
                                        size: 18,
                                      )
                                    : null,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Status message
          Text(
            isStreakCompletedToday
                ? 'You have successfully completed your streak!'
                : 'Complete your daily tasks to lock in your streak!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.ink,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),

          // Daily Progress Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.line, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Today's Tasks",
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$done/$total completed',
                      style: TextStyle(
                        color: p.ink2,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: p.card2,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFFF9800)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Button: Share Achievement
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _shareStreak(streak),
              icon: const Icon(Symbols.share, size: 18),
              label: const Text(
                'Share Achievement',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? p.primary : const Color(0xFF1B1C1E),
                foregroundColor: isDark ? p.onPrimary : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Secondary Button: What's a Streak?
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _showWhatsAStreakDialog(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.ink,
                side: BorderSide(color: p.line, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                "What's a Streak?",
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _shareStreak(int streak) {
    SharePlus.instance.share(
      ShareParams(
        text:
            '🔥 I am on a $streak-day study streak on StudyTrail! Join me in conquering our syllabus: https://studytrail.app',
        subject: 'My StudyTrail Streak!',
      ),
    );
  }

  static void _showWhatsAStreakDialog(BuildContext context) {
    final p = context.p;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: const [
            Icon(Symbols.local_fire_department,
                color: Color(0xFFFF9800), size: 26, fill: 1),
            SizedBox(width: 8),
            Text('What is a Streak?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RuleItem(
              icon: Symbols.check_circle,
              title: 'Daily Action',
              description:
                  'Complete at least one daily task or study session every day before midnight.',
            ),
            const SizedBox(height: 12),
            _RuleItem(
              icon: Symbols.trending_up,
              title: 'Build Momentum',
              description:
                  'Each consecutive day adds +1 to your streak and gives you bonus XP multiplier.',
            ),
            const SizedBox(height: 12),
            _RuleItem(
              icon: Symbols.alarm,
              title: "Don't Break the Chain",
              description:
                  'If you miss a day, your streak resets back to 0. Stay consistent!',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it!',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: p.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: p.ink2,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
