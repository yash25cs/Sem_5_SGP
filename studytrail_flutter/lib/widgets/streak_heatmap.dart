import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// GitHub-style activity heatmap — a grid of coloured squares, one per day,
/// grouped into weeks. Intensity comes from `activity_log` via the store.
///
/// Extracted from `progress_screen.dart` so both the Progress and Profile tabs
/// can show it without duplicating the layout.
class StreakHeatmap extends StatelessWidget {
  const StreakHeatmap(this.days, {super.key, this.weeks = 8});

  final List<ActivityDay> days;

  /// How many weeks of history to render. The default 8 matches the Analytics
  /// screen; Profile uses 12 for a wider view.
  final int weeks;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final today = DateTime.now();
    final thisMonday = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - 1));

    final byDate = {
      for (final d in days) DateTime(d.date.year, d.date.month, d.date.day): d,
    };

    Color shade(int level) => switch (level) {
          0 => p.card3,
          1 => p.heat1,
          2 => p.heat3,
          _ => p.heat4,
        };

    return Column(
      children: [
        for (var weeksAgo = weeks - 1; weeksAgo >= 0; weeksAgo--)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (var weekday = 0; weekday < 7; weekday++)
                  Expanded(
                    child: Container(
                      height: 26,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: shade(byDate[
                                    thisMonday.add(Duration(
                                        days: weekday - weeksAgo * 7))]
                                ?.intensity ??
                            0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The legend strip below the heatmap: Less □ □ □ □ More.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(children: [
      Text('Less', style: TextStyle(color: p.ink3, fontSize: 11)),
      const SizedBox(width: 8),
      _box(p.card3),
      _box(p.heat1),
      _box(p.heat3),
      _box(p.heat4),
      const SizedBox(width: 8),
      Text('More', style: TextStyle(color: p.ink3, fontSize: 11)),
    ]);
  }

  Widget _box(Color c) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 13,
        height: 13,
        decoration:
            BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
      );
}
