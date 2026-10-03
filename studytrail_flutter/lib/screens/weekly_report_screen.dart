import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/nav.dart';
import 'flashcards_screen.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _duration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The last seven days against the seven before (`get_weekly_report`).
class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WeeklyReportStore>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<WeeklyReportStore>();
    final report = store.report;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back,
                    onTap: widget.onBack ??
                        () => Navigator.of(context).maybePop()),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your week',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      Text(
                          report == null
                              ? 'The last seven days'
                              : '${_date(report.from)} – ${_date(report.to)} · '
                                  'against the week before',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.ink3, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: p.primary,
              onRefresh: store.load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  if (store.error != null)
                    ErrorNotice(message: store.error!, onRetry: store.load)
                  else if (report == null)
                    const LoadingBlock(height: 220)
                  else
                    ..._body(context, report),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, WeeklyReport r) {
    final p = context.p;
    final now = r.thisWeek;
    final before = r.lastWeek;
    final weak = r.units.where((u) => u.accuracy < 0.7).take(3).toList();
    final strong =
        r.units.reversed.where((u) => u.accuracy >= 0.7).take(3).toList();

    return [
      // The one number the week leads with.
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Focused this week',
                style: TextStyle(
                    color: p.ink2, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_duration(now.minutes),
                style: TextStyle(
                    color: p.ink,
                    fontSize: 48,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5)),
            const SizedBox(height: 6),
            _Delta(now: now.minutes, before: before.minutes, unit: _duration),
            if (r.empty) ...[
              const SizedBox(height: 12),
              Text(
                  'Nothing logged in the last seven days yet. A focus session, '
                  'a quiz or a ticked task all count.',
                  style: TextStyle(color: p.ink3, fontSize: 13, height: 1.4)),
            ],
            const SizedBox(height: 18),
            _DayChart(days: r.days),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _TileGrid(tiles: [
        _Tile(Symbols.bolt, 'XP earned', '${now.xp}',
            _Delta(now: now.xp, before: before.xp)),
        _Tile(Symbols.task_alt, 'Tasks done', '${now.tasks}',
            _Delta(now: now.tasks, before: before.tasks)),
        _Tile(Symbols.calendar_month, 'Days studied', '${now.activeDays} of 7',
            _Delta(now: now.activeDays, before: before.activeDays)),
        _Tile(
            Symbols.quiz,
            'Quiz accuracy',
            now.quizAccuracy == null
                ? '—'
                : '${(now.quizAccuracy! * 100).round()}%',
            now.quizAccuracy == null || before.quizAccuracy == null
                ? _Note('${now.quizzes} quiz${now.quizzes == 1 ? '' : 'zes'}')
                : _Delta(
                    now: (now.quizAccuracy! * 100).round(),
                    before: (before.quizAccuracy! * 100).round(),
                    unit: (v) => '$v pts')),
        _Tile(
            Symbols.groups,
            'Group quizzes',
            '${now.groupQuizzes}',
            _Note(now.podiums == 0
                ? 'No podium yet'
                : '${now.podiums} in the top 3')),
        _Tile(
            Symbols.edit_note,
            'Written answers',
            '${now.answers}',
            _Note(now.answerPercent == null
                ? 'None graded'
                : 'Averaging ${now.answerPercent}%')),
      ]),
      if (weak.isNotEmpty || strong.isNotEmpty) ...[
        const SizedBox(height: 22),
        CardHeader('Quiz topics this week'),
        if (weak.isNotEmpty) ...[
          _UnitGroup(title: 'Needs work', units: weak, tone: p.coral),
          const SizedBox(height: 10),
        ],
        if (strong.isNotEmpty)
          _UnitGroup(title: 'Going well', units: strong, tone: p.green),
      ],
      const SizedBox(height: 22),
      AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.local_fire_department,
                    color: p.coral, fill: 1, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      r.streak == 0
                          ? 'No streak running'
                          : '${r.streak}-day streak · best ${r.bestStreak}',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            if (r.mistakesDue > 0) ...[
              const SizedBox(height: 12),
              Text(
                  r.mistakesDue == 1
                      ? 'One question you got wrong is waiting in My mistakes.'
                      : '${r.mistakesDue} questions you got wrong are waiting '
                          'in My mistakes.',
                  style: TextStyle(color: p.ink2, fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              PillButton('Review my mistakes',
                  icon: Symbols.replay,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (ctx) => FlashcardsScreen(
                          onBack: () => Navigator.of(ctx).pop())))),
            ],
          ],
        ),
      ),
    ];
  }
}

/// This week against last: signed, and green only when up is good.
class _Delta extends StatelessWidget {
  const _Delta({required this.now, required this.before, this.unit});

  final int now;
  final int before;
  final String Function(int)? unit;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final diff = now - before;
    final show = unit ?? (v) => '$v';
    final (icon, color, text) = diff == 0
        ? (Symbols.trending_flat, p.ink3, 'Same as last week')
        : diff > 0
            ? (Symbols.trending_up, p.green, '+${show(diff)} on last week')
            : (Symbols.trending_down, p.coral, '−${show(-diff)} on last week');
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              // Text stays in ink; the arrow carries the direction.
              style: TextStyle(
                  color: p.ink2, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          color: context.p.ink3, fontSize: 12, fontWeight: FontWeight.w600));
}

class _Tile {
  const _Tile(this.icon, this.label, this.value, this.footer);
  final IconData icon;
  final String label;
  final String value;
  final Widget footer;
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget tile(_Tile t) => AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(t.icon, size: 18, color: p.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(t.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink2,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(t.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              t.footer,
            ],
          ),
        );

    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tile(tiles[i])),
                const SizedBox(width: 12),
                Expanded(
                    child: i + 1 < tiles.length
                        ? tile(tiles[i + 1])
                        : const SizedBox()),
              ],
            ),
          ),
          if (i + 2 < tiles.length) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Focus minutes per day: one series, so no legend — the title names it. The
/// busiest day is labelled on its cap; tap any day for its value.
class _DayChart extends StatelessWidget {
  const _DayChart({required this.days});
  final List<WeekDay> days;

  static const _plotHeight = 110.0;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final top = days.fold<int>(0, (m, d) => d.minutes > m ? d.minutes : m);
    final busiest = top == 0 ? -1 : days.indexWhere((d) => d.minutes == top);

    return Semantics(
      label: 'Focus minutes per day: '
          '${[
        for (final d in days) '${_days[d.date.weekday - 1]} ${d.minutes}'
      ].join(', ')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Focus minutes per day',
                style: TextStyle(
                    color: p.ink2,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SizedBox(
              // The bars, plus room above the tallest for its value.
              height: _plotHeight + 28,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, d) in days.indexed)
                    Expanded(
                      child: Tooltip(
                        message:
                            '${_days[d.date.weekday - 1]} ${_date(d.date)}: '
                            '${_duration(d.minutes)}',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (i == busiest)
                              Text('${d.minutes}',
                                  maxLines: 1,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 11,
                                      height: 1.2,
                                      fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Container(
                              width: 20,
                              height: top == 0
                                  ? 0
                                  : (d.minutes / top * _plotHeight).clamp(
                                      d.minutes > 0 ? 3.0 : 0.0, _plotHeight),
                              decoration: BoxDecoration(
                                color: p.primary,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(height: 1, color: p.line),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final (i, d) in days.indexed)
                  Expanded(
                    child: Text(_days[d.date.weekday - 1],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: i == days.length - 1 ? p.ink : p.ink3,
                            fontSize: 11,
                            fontWeight: i == days.length - 1
                                ? FontWeight.w800
                                : FontWeight.w600)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitGroup extends StatelessWidget {
  const _UnitGroup({
    required this.title,
    required this.units,
    required this.tone,
  });

  final String title;
  final List<UnitAccuracy> units;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
          for (final u in units) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(u.unitLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: p.ink2, fontSize: 13, height: 1.3)),
                ),
                const SizedBox(width: 10),
                Text('${(u.accuracy * 100).round()}%',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 5),
            ProgressTrack(u.accuracy, color: tone, height: 6),
            if (u.accuracyBefore != null) ...[
              const SizedBox(height: 4),
              Text(
                  'Last week ${(u.accuracyBefore! * 100).round()}% · '
                  '${u.correct} of ${u.answered} right this week',
                  style: TextStyle(color: p.ink3, fontSize: 11.5)),
            ] else ...[
              const SizedBox(height: 4),
              Text('${u.correct} of ${u.answered} right',
                  style: TextStyle(color: p.ink3, fontSize: 11.5)),
            ],
          ],
        ],
      ),
    );
  }
}
