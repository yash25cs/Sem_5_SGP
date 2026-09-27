import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/streak_heatmap.dart';

/// Progress analytics — weekly study bars, per-subject accuracy, and a
/// consistency heatmap, all derived from `activity_log`.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  /// Monday-first labels for the weekly bars.
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProgressStore>().load();
    });
  }

  /// Index of the tallest bar — it gets the solid fill and the value label.
  int _peakIndex(List<ActivityDay> days) {
    var best = -1, bestMinutes = 0;
    for (final (i, d) in days.indexed) {
      if (d.minutesStudied > bestMinutes) {
        bestMinutes = d.minutesStudied;
        best = i;
      }
    }
    return best;
  }

  /// 1240 → "1,240" for the XP tile.
  String _thousands(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<ProgressStore>();

    // Only subjects with graded quizzes have a meaningful accuracy; showing
    // every subject at 0% would read as "you got everything wrong".
    final accSubjects =
        store.subjects.where((s) => s.accuracy > 0).take(5).toList();
    final accColors = [p.primary, p.coral, p.green, p.onAmber];
    final peak = _peakIndex(store.weekly);

    return RefreshIndicator(
      color: p.primary,
      onRefresh: () => context.read<ProgressStore>().load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          Text('Your progress',
              style: TextStyle(
                  color: p.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6)),
          const SizedBox(height: 2),
          Text('Last 7 days',
              style: TextStyle(color: p.ink2, fontSize: 13.5)),
          const SizedBox(height: 18),

          if (store.error != null)
            ErrorNotice(
              message: store.error!,
              onRetry: () => context.read<ProgressStore>().load(),
            ),

          if (store.loading && !store.loaded) ...[
            const LoadingBlock(height: 108),
            const LoadingBlock(height: 200),
            const LoadingBlock(height: 160),
          ] else ...[
            // stat tiles
            Row(
              children: [
                Expanded(
                    child: _StatTile(
                        icon: Symbols.timer,
                        value: store.totals.studyTimeLabel,
                        label: 'Studied',
                        tone: p.primary,
                        bg: p.primarySoft)),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatTile(
                        icon: Symbols.check_circle,
                        value: '${(store.quizAccuracy * 100).round()}%',
                        label: 'Accuracy',
                        tone: p.green,
                        bg: p.greenSoft)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _StatTile(
                        icon: Symbols.local_fire_department,
                        value: '${store.streak.currentStreak}',
                        label: 'Day streak',
                        tone: p.coral,
                        bg: p.coralSoft)),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatTile(
                        icon: Symbols.bolt,
                        value: _thousands(store.totals.xpEarned),
                        label: 'XP this week',
                        tone: p.onAmber,
                        bg: p.amberSoft)),
              ],
            ),
            const SizedBox(height: 20),

            // weekly bar chart
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('Study time',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    SoftChip('This week',
                        tone: ChipTone.neutral, small: true),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 140,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (i, day) in store.weekly.indexed)
                          _Bar(
                            day: _dayLabels[i],
                            minutes: day.minutesStudied,
                            peakMinutes: store.weeklyPeak,
                            isPeak: i == peak,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // accuracy by subject
            CardHeader('Accuracy by subject'),
            AppCard(
              child: accSubjects.isEmpty
                  ? Row(
                      children: [
                        Icon(Symbols.track_changes, color: p.ink3, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              'Finish a quiz and your accuracy per subject shows up here.',
                              style: TextStyle(
                                  color: p.ink3, fontSize: 13, height: 1.45)),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        for (final (i, s) in accSubjects.indexed) ...[
                          if (i > 0) const SizedBox(height: 14),
                          _AccRow(s.name, s.accuracy,
                              accColors[i % accColors.length]),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 20),

            // consistency heatmap
            CardHeader('Consistency'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreakHeatmap(store.heatmap),
                  const SizedBox(height: 14),
                  const HeatmapLegend(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.icon,
      required this.value,
      required this.label,
      required this.tone,
      required this.bg});
  final IconData icon;
  final String value, label;
  final Color tone, bg;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: p.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: tone, size: 20),
          ),
          const SizedBox(height: 12),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          Text(label, style: TextStyle(color: p.ink3, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.minutes,
    required this.peakMinutes,
    required this.isPeak,
  });

  final String day;
  final int minutes;
  final int peakMinutes;
  final bool isPeak;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final color = isPeak ? p.coral : p.primary;

    // A studied day always gets a visible stub, so a short session doesn't
    // look identical to a day with nothing logged.
    final fraction =
        minutes == 0 ? 0.0 : (minutes / peakMinutes).clamp(0.08, 1.0);

    final label = minutes >= 60
        ? '${(minutes / 60).toStringAsFixed(1)}h'
        : '${minutes}m';

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (isPeak && minutes > 0) ...[
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
          ],
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            height: 96 * fraction,
            decoration: BoxDecoration(
              color: isPeak ? color : color.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 8),
          Text(day,
              style: TextStyle(
                  color: p.ink3, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _AccRow extends StatelessWidget {
  const _AccRow(this.name, this.value, this.color);
  final String name;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text('${(value * 100).round()}%',
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        ProgressTrack(value, color: color, height: 8),
      ],
    );
  }
}

