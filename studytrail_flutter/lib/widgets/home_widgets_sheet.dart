import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/home_widget_sync.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// The three home-screen widgets, previewed with the student's own data, each
/// with an Add button that asks the launcher to place it.
///
/// The previews are drawn here in Flutter to match the Android layouts
/// (`res/layout/studytrail_*.xml`), including their two animations: the task
/// line sliding to the next task, and the light circling the streak flame
/// while today is still to do. Where the launcher can't add widgets for an
/// app, the sheet says how to add one by hand instead.
class HomeWidgetsSheet extends StatelessWidget {
  const HomeWidgetsSheet({super.key});

  static Future<void> show(BuildContext context) {
    final p = context.p;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const HomeWidgetsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final facts = _Facts.from(context.read<HomeStore>());

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => FutureBuilder<bool>(
        future: HomeWidgetSync.canAdd(),
        builder: (context, snapshot) {
          final canAdd = snapshot.data ?? false;
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: p.line2, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Home-screen widgets',
                  style: TextStyle(
                      color: p.ink, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  'Your exam countdown, streak and today’s tasks, '
                  'without opening the app. Tap any part to jump straight in.',
                  style: TextStyle(color: p.ink2, fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 18),
              _Entry(
                kind: HomeWidgetKind.today,
                name: 'Today',
                size: '4 × 2',
                about: 'Countdown, today’s tasks and quick actions',
                canAdd: canAdd,
                delay: 0,
                preview: _TodayPreview(facts),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Entry(
                      kind: HomeWidgetKind.countdown,
                      name: 'Exam countdown',
                      size: '2 × 2',
                      about: 'Days to your next paper',
                      canAdd: canAdd,
                      delay: 1,
                      preview: _CountdownPreview(facts),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _Entry(
                      kind: HomeWidgetKind.streak,
                      name: 'Streak',
                      size: '2 × 1',
                      about: 'Glows until today is done',
                      canAdd: canAdd,
                      delay: 2,
                      preview: _StreakPreview(facts),
                    ),
                  ),
                ],
              ),
              if (snapshot.hasData && !canAdd) ...[
                const SizedBox(height: 18),
                AppCard(
                  color: p.primarySoft,
                  shadow: false,
                  child: Row(
                    children: [
                      Icon(Symbols.touch_app, color: p.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                            'Long-press an empty spot on your home screen, '
                            'tap Widgets, then find StudyTrail.',
                            style: TextStyle(
                                color: p.onPrimarySoft,
                                fontSize: 12.5,
                                height: 1.45,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// What the previews show: the student's own numbers once Home has loaded,
/// believable samples before then.
class _Facts {
  const _Facts({
    required this.days,
    required this.examName,
    required this.examDate,
    required this.papersLeft,
    required this.streak,
    required this.studiedToday,
    required this.done,
    required this.total,
    required this.nextTasks,
  });

  final int days;
  final String examName;
  final DateTime examDate;
  final int papersLeft;
  final int streak;
  final bool studiedToday;
  final int done;
  final int total;
  final List<String> nextTasks;

  factory _Facts.from(HomeStore store) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exam = store.nextExam;
    final upcoming =
        store.subjects.where((s) => (s.daysUntilExam() ?? -1) >= 0).length;
    final last = store.streak.lastActiveDate;
    final pending = [
      for (final t in store.tasks)
        if (!t.done) t.title,
    ];
    final hasTasks = store.tasks.isNotEmpty;
    return _Facts(
      days: exam?.daysUntilExam() ?? 12,
      examName: exam?.name ?? 'Physics',
      examDate: exam?.examDate ?? today.add(const Duration(days: 12)),
      papersLeft: exam == null ? 3 : upcoming,
      streak: store.goal == null ? 5 : store.streak.currentStreak,
      studiedToday:
          last != null && DateTime(last.year, last.month, last.day) == today,
      done: hasTasks ? store.doneCount : 2,
      total: hasTasks ? store.tasks.length : 5,
      nextTasks: hasTasks
          ? pending.take(3).toList()
          : const ['Revise Unit 2 notes', 'Practice quiz: Optics'],
    );
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
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

  /// "Fri, 20 Nov", as the widgets write it.
  String get dateLabel => '${_weekdays[examDate.weekday - 1]}, '
      '${examDate.day} ${_months[examDate.month - 1]}';
}

/// One widget in the sheet: its preview, name and size, and Add. Slides in a
/// beat after the one before it.
class _Entry extends StatefulWidget {
  const _Entry({
    required this.kind,
    required this.name,
    required this.size,
    required this.about,
    required this.canAdd,
    required this.delay,
    required this.preview,
  });

  final HomeWidgetKind kind;
  final String name, size, about;
  final bool canAdd;
  final int delay;
  final Widget preview;

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> with SingleTickerProviderStateMixin {
  late final _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
  Timer? _start;

  @override
  void initState() {
    super.initState();
    _start = Timer(Duration(milliseconds: 90 * widget.delay), _intro.forward);
  }

  @override
  void dispose() {
    _start?.cancel();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    await HomeWidgetSync.add(widget.kind);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Confirm on your home screen to add ${widget.name}.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final curve = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.12), end: Offset.zero)
            .animate(curve),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Pressable(
                onTap: widget.canAdd ? _add : null, child: widget.preview),
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  child: Text(widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                Text(widget.size,
                    style: TextStyle(
                        color: p.ink3,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 2),
            Text(widget.about,
                style: TextStyle(color: p.ink2, fontSize: 12, height: 1.35)),
            if (widget.canAdd) ...[
              const SizedBox(height: 10),
              PillButton('Add',
                  icon: Symbols.add, variant: PillVariant.soft, onTap: _add),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shrinks a little under the finger, the way the real widget ripples.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (widget.onTap != null && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// The widget's gradient card. Colours match `studytrail_*_bg.xml`.
class _WidgetCard extends StatelessWidget {
  const _WidgetCard({
    required this.colors,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final List<Color> colors;
  final Widget child;
  final EdgeInsets padding;

  static const today = [Color(0xFF24389C), Color(0xFF3F51B5)];
  static const countdown = [Color(0xFF5B21B6), Color(0xFF8B5CF6)];
  static const streak = [Color(0xFFFE6F42), Color(0xFFF59E0B)];

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: child,
        ),
      );
}

const _soft = Color(0x2EFFFFFF);

class _TodayPreview extends StatelessWidget {
  const _TodayPreview(this.facts);
  final _Facts facts;

  @override
  Widget build(BuildContext context) {
    final f = facts;
    final days = switch (f.days) {
      0 => 'Exam today',
      1 => '1 day',
      _ => '${f.days} days',
    };
    final lines = f.done >= f.total
        ? ['All ${f.total} tasks done today 🎉']
        : [
            for (final (i, t) in f.nextTasks.indexed)
              '${i == 0 ? 'Next' : 'Then'} · $t',
          ];

    return _WidgetCard(
      colors: _WidgetCard.today,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration:
                    const BoxDecoration(color: _soft, shape: BoxShape.circle),
                child: const Icon(Symbols.auto_awesome,
                    color: Colors.white, size: 13, fill: 1),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('StudyTrail',
                    style: TextStyle(
                        color: Color(0xD9FFFFFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              if (f.streak > 0)
                Container(
                  padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
                  decoration: BoxDecoration(
                      color: _soft, borderRadius: BorderRadius.circular(99)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Symbols.local_fire_department,
                          color: Colors.white, size: 14, fill: 1),
                      const SizedBox(width: 3),
                      Text('${f.streak}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(days,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 26,
                            height: 1.1,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                        f.days == 0
                            ? '${f.examName} · good luck!'
                            : 'to ${f.examName} · ${f.days == 1 ? 'tomorrow' : f.dateLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xE6FFFFFF), fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 54,
                height: 54,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                            begin: 0, end: f.total == 0 ? 0 : f.done / f.total),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (_, value, _) => CircularProgressIndicator(
                          value: value,
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round,
                          color: Colors.white,
                          backgroundColor: const Color(0x33FFFFFF),
                        ),
                      ),
                    ),
                    Text(f.total == 0 ? '—' : '${f.done}/${f.total}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _FlippingLine(
              lines.isEmpty ? const ['Open StudyTrail to plan today'] : lines),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(child: _ActionPill(Symbols.timer, 'Focus')),
              SizedBox(width: 8),
              Expanded(child: _ActionPill(Symbols.style, 'Cards')),
              SizedBox(width: 8),
              Expanded(child: _ActionPill(Symbols.chat, 'Ask AI')),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Today widget's task line: each task slides up and out as the next
/// slides in, every 3.5 s — `widget_task_in.xml` / `widget_task_out.xml`.
class _FlippingLine extends StatefulWidget {
  const _FlippingLine(this.lines);
  final List<String> lines;

  @override
  State<_FlippingLine> createState() => _FlippingLineState();
}

class _FlippingLineState extends State<_FlippingLine> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.lines.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
        setState(() => _index = (_index + 1) % widget.lines.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          transitionBuilder: (child, animation) {
            final entering = child.key == ValueKey(_index);
            final slide = Tween(
              begin: entering ? const Offset(0, 1) : const Offset(0, -1),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
            return SlideTransition(
              position: slide,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: SizedBox(
            key: ValueKey(_index),
            width: double.infinity,
            child: Text(widget.lines[_index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
          ),
        ),
      );
}

class _ActionPill extends StatelessWidget {
  const _ActionPill(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
            color: const Color(0x24FFFFFF),
            borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16, fill: 1),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _CountdownPreview extends StatelessWidget {
  const _CountdownPreview(this.facts);
  final _Facts facts;

  @override
  Widget build(BuildContext context) {
    final f = facts;
    final word = f.days == 0;
    return _WidgetCard(
      colors: _WidgetCard.countdown,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Row(
            children: [
              Icon(Symbols.event, color: Colors.white, size: 14, fill: 1),
              SizedBox(width: 5),
              Text('NEXT EXAM',
                  style: TextStyle(
                      color: Color(0xD9FFFFFF),
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: f.days),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => Text(word ? 'Today' : '$value',
                  style: TextStyle(
                      fontSize: word ? 32 : 46,
                      height: 1.1,
                      fontWeight: FontWeight.w900)),
            ),
          ),
          Text(
              word
                  ? 'good luck!'
                  : f.days == 1
                      ? 'day to go'
                      : 'days to go',
              style: const TextStyle(
                  color: Color(0xE6FFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(f.examName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          Text(
              '${f.dateLabel}${f.papersLeft > 1 ? ' · ${f.papersLeft} left' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11)),
        ],
      ),
    );
  }
}

class _StreakPreview extends StatefulWidget {
  const _StreakPreview(this.facts);
  final _Facts facts;

  @override
  State<_StreakPreview> createState() => _StreakPreviewState();
}

/// The flame with the light circling it — `widget_streak_glow.xml`, which the
/// real widget runs until today's studying is done.
class _StreakPreviewState extends State<_StreakPreview>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (!widget.facts.studiedToday) _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.facts;
    return _WidgetCard(
      colors: _WidgetCard.streak,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!f.studiedToday)
                  RotationTransition(
                    turns: _spin,
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(colors: [
                          Color(0x00FFFFFF),
                          Color(0x40FFFFFF),
                          Color(0xFFFFFFFF),
                        ]),
                      ),
                    ),
                  ),
                Container(
                  width: 37,
                  height: 37,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: f.studiedToday ? _soft : const Color(0xFFF9963A),
                  ),
                  child: const Icon(Symbols.local_fire_department,
                      color: Colors.white, size: 20, fill: 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${f.streak}',
                    style: const TextStyle(
                        fontSize: 26,
                        height: 1.1,
                        fontWeight: FontWeight.w900)),
                const Text('day streak',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Color(0xF2FFFFFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
