import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';

/// Roadmap tab — a vertical timeline of weekly milestones with day tasks.
class RoadmapScreen extends StatefulWidget {
  const RoadmapScreen({super.key});

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen>
    with TickerProviderStateMixin {
  late final ConfettiController _confetti;
  final Set<String> _collapsedMilestones = {};

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RoadmapStore>().load();
      }
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Generates (or regenerates) the weekly plan for the active goal.
  Future<void> _generate() async {
    final store = context.read<RoadmapStore>();
    if (store.goal == null) {
      _toast('Set a study goal first, then generate a roadmap.');
      return;
    }

    if (store.milestones.isNotEmpty && !await _confirmReplace()) return;
    if (!mounted) return;

    final ok = await store.generate();
    if (!ok) return;
    final weeks = store.milestones.length;
    _toast('Roadmap ready — $weeks week${weeks == 1 ? '' : 's'} planned.');
  }

  /// Ticks a roadmap checkbox, and refreshes Home when the same task is also on
  /// its checklist.
  Future<void> _toggle(Milestone milestone, MilestoneTask task) async {
    final store = context.read<RoadmapStore>();
    final wasDone = milestone.doneCount;
    await store.toggleTask(milestone, task);
    if (!mounted) return;

    // Check if a milestone was just completed — celebrate!
    final updatedMilestone = store.milestones
        .where((m) => m.id == milestone.id)
        .firstOrNull;
    if (updatedMilestone != null &&
        updatedMilestone.doneCount == updatedMilestone.tasks.length &&
        wasDone < milestone.tasks.length) {
      _confetti.play();
    }

    if (!store.lastToggleTouchedDailyTask) return;
    await context.read<HomeStore>().load();
  }

  Future<bool> _confirmReplace() async {
    final p = context.p;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Replace this roadmap?',
            style: TextStyle(
                color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        content: Text(
            'A new plan is written from your goal and materials. The weeks you '
            'have already ticked off will be cleared.',
            style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep it', style: TextStyle(color: p.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Replace',
                style: TextStyle(
                    color: p.primary, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Color _accent(BuildContext context, Milestone m, int index) {
    final p = context.p;
    if (m.state == MilestoneState.done) return p.green;
    final cycle = [p.primary, p.coral, p.amber, p.primary2];
    return cycle[index % cycle.length];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<RoadmapStore>();
    final goal = store.goal;

    final subtitle = goal == null
        ? 'No goal set yet'
        : [
            goal.name,
            if (goal.daysLeft != null) '${goal.daysLeft} days left',
          ].join(' · ');

    // Find current active milestone index
    final activeIndex =
        store.milestones.indexWhere((m) => m.state == MilestoneState.active);

    return Stack(
      children: [
        RefreshIndicator(
          color: p.primary,
          onRefresh: () => context.read<RoadmapStore>().load(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            children: [
              // ── Header ──
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your roadmap',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: p.ink2, fontSize: 13.5)),
                      ],
                    ),
                  ),
                  RoundIconButton(Symbols.auto_awesome,
                      plain: false,
                      color: store.generating ? p.ink3 : p.primary,
                      onTap: store.generating ? null : _generate),
                ],
              ),
              const SizedBox(height: 16),

              if (store.error != null)
                ErrorNotice(
                  message: store.error!,
                  onRetry: () => context.read<RoadmapStore>().load(),
                ),

              // ── Generating indicator ──
              if (store.generating)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: p.primary, strokeWidth: 2.2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                              'Writing your weekly plan… this can take up to a '
                              'minute.',
                              style:
                                  TextStyle(color: p.ink2, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Stats Dashboard ──
              if (store.totalTasks > 0) ...[
                _StatsDashboard(
                  totalTasks: store.totalTasks,
                  doneTasks: store.doneTasks,
                  progress: store.overallProgress,
                  totalWeeks: store.milestones.length,
                  doneWeeks: store.milestones
                      .where((m) => m.state == MilestoneState.done)
                      .length,
                  currentWeek: activeIndex >= 0 ? activeIndex + 1 : null,
                  daysLeft: goal?.daysLeft,
                ),
                const SizedBox(height: 20),
              ],

              // ── Loading / Empty / Timeline ──
              if (store.loading && !store.loaded) ...[
                const LoadingBlock(height: 150),
                const LoadingBlock(height: 150),
              ] else if (store.isEmpty)
                EmptyState(
                  icon: Symbols.route,
                  title:
                      goal == null ? 'No roadmap yet' : 'Roadmap is empty',
                  message: goal == null
                      ? 'Set your exam goal and StudyTrail will plan the weeks for you.'
                      : 'Generate a roadmap from your syllabus to see weekly milestones here.',
                  actionLabel: goal == null
                      ? null
                      : store.generating
                          ? 'Working on it…'
                          : 'Generate my roadmap',
                  onAction:
                      goal == null || store.generating ? null : _generate,
                )
              else
                for (var i = 0; i < store.milestones.length; i++)
                  _MilestoneTile(
                    milestone: store.milestones[i],
                    color: _accent(context, store.milestones[i], i),
                    last: i == store.milestones.length - 1,
                    weekNumber: i + 1,
                    collapsed:
                        _collapsedMilestones.contains(store.milestones[i].id),
                    onToggle: (task) => _toggle(store.milestones[i], task),
                    onExpand: () {
                      setState(() {
                        final id = store.milestones[i].id;
                        if (_collapsedMilestones.contains(id)) {
                          _collapsedMilestones.remove(id);
                        } else {
                          _collapsedMilestones.add(id);
                        }
                      });
                    },
                  ),
            ],
          ),
        ),
        // Confetti overlay
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: [p.primary, p.coral, p.amber, p.green, p.primary2],
            numberOfParticles: 25,
            gravity: 0.15,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class _StatsDashboard extends StatelessWidget {
  const _StatsDashboard({
    required this.totalTasks,
    required this.doneTasks,
    required this.progress,
    required this.totalWeeks,
    required this.doneWeeks,
    this.currentWeek,
    this.daysLeft,
  });

  final int totalTasks, doneTasks, totalWeeks, doneWeeks;
  final double progress;
  final int? currentWeek;
  final int? daysLeft;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Circular progress ring
              SizedBox(
                width: 80,
                height: 80,
                child: CustomPaint(
                  painter: _ProgressRingPainter(
                    progress: progress,
                    trackColor: p.card3,
                    fillColor: p.primary,
                    strokeWidth: 8,
                  ),
                  child: Center(
                    child: Text(
                      '${(progress * 100).round()}%',
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Stats grid
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStat(
                            icon: Symbols.check_circle,
                            label: 'Topics done',
                            value: '$doneTasks/$totalTasks',
                            color: p.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MiniStat(
                            icon: Symbols.calendar_month,
                            label: 'Weeks done',
                            value: '$doneWeeks/$totalWeeks',
                            color: p.coral,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (currentWeek != null)
                          Expanded(
                            child: _MiniStat(
                              icon: Symbols.bolt,
                              label: 'Current',
                              value: 'Week $currentWeek',
                              color: p.primary,
                            ),
                          ),
                        if (currentWeek != null && daysLeft != null)
                          const SizedBox(width: 12),
                        if (daysLeft != null)
                          Expanded(
                            child: _MiniStat(
                              icon: Symbols.timer,
                              label: 'Remaining',
                              value: '$daysLeft days',
                              color: p.amber,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Progress bar below
          const SizedBox(height: 16),
          ProgressTrack(progress, color: p.primary, height: 6),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                progress >= 1.0
                    ? '🎉 All topics completed!'
                    : '${totalTasks - doneTasks} topics remaining',
                style: TextStyle(
                    color: p.ink3, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              if (progress < 1.0 && progress > 0)
                Text(
                  _motivationalHint(progress),
                  style: TextStyle(
                      color: p.primary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _motivationalHint(double progress) {
    if (progress >= 0.75) return 'Almost there! 💪';
    if (progress >= 0.5) return 'Halfway! Keep going 🔥';
    if (progress >= 0.25) return 'Great start! 🚀';
    return 'You got this! ✨';
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color, fill: 1),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                Text(label,
                    style: TextStyle(color: p.ink3, fontSize: 10.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress Ring Painter
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color trackColor, fillColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Fill arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.progress != progress ||
      old.fillColor != fillColor ||
      old.trackColor != trackColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Milestone Tile (timeline row)
// ─────────────────────────────────────────────────────────────────────────────

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({
    required this.milestone,
    required this.color,
    required this.onToggle,
    required this.weekNumber,
    this.collapsed = false,
    required this.onExpand,
    this.last = false,
  });

  final Milestone milestone;
  final Color color;
  final ValueChanged<MilestoneTask> onToggle;
  final int weekNumber;
  final bool collapsed;
  final VoidCallback onExpand;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final active = milestone.state == MilestoneState.active;
    final done = milestone.state == MilestoneState.done;
    final tasks = milestone.tasks;

    final header = milestone.weekLabel ?? 'Week $weekNumber';
    final isCollapsible = done || milestone.state == MilestoneState.upcoming;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Timeline rail ──
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: active || done ? color : p.card,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: active || done ? color : p.line2, width: 2.4),
                  boxShadow: active ? p.glow : null,
                ),
                child: Center(
                  child: done
                      ? Icon(Symbols.check, color: Colors.white, size: 18,
                          weight: 700)
                      : active
                          ? Icon(Symbols.bolt, color: Colors.white, size: 18,
                              fill: 1)
                          : Text(
                              '$weekNumber',
                              style: TextStyle(
                                color: p.ink3,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2.4,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      gradient: done
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                color.withValues(alpha: 0.6),
                                color.withValues(alpha: 0.15),
                              ],
                            )
                          : null,
                      color: done ? null : p.line2,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // ── Milestone card ──
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: AppCard(
                color: active ? null : p.card,
                gradient: active
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                            color.withValues(alpha: 0.10),
                            p.card,
                          ])
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row with week label and task count
                    InkWell(
                      onTap: isCollapsible ? onExpand : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(header.toUpperCase(),
                                        style: TextStyle(
                                            color: color,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5)),
                                    const SizedBox(width: 8),
                                    if (done)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: p.greenSoft,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text('DONE',
                                            style: TextStyle(
                                                color: p.green,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.3)),
                                      ),
                                    if (active)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: p.primarySoft,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text('IN PROGRESS',
                                            style: TextStyle(
                                                color: p.primary,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.3)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(milestone.title,
                                    style: TextStyle(
                                        color: p.ink,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                          if (isCollapsible)
                            AnimatedRotation(
                              turns: collapsed ? -0.25 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(Symbols.expand_more,
                                  color: p.ink3, size: 22),
                            ),
                        ],
                      ),
                    ),

                    // Task count summary
                    if (tasks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Symbols.checklist,
                              size: 14, color: p.ink3),
                          const SizedBox(width: 4),
                          Text(
                            '${milestone.doneCount}/${tasks.length} topics',
                            style: TextStyle(
                                color: p.ink3,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                          if (active) ...[
                            const SizedBox(width: 12),
                            Icon(Symbols.schedule,
                                size: 14, color: p.ink3),
                            const SizedBox(width: 4),
                            Text(
                              '~${tasks.length * 25} min',
                              style: TextStyle(
                                  color: p.ink3,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ],

                    // Tasks list (collapsible)
                    if (tasks.isNotEmpty && !collapsed) ...[
                      const SizedBox(height: 12),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: Column(
                          children: [
                            for (var i = 0; i < tasks.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              _MiniTask(
                                task: tasks[i],
                                color: color,
                                onTap: () => onToggle(tasks[i]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // Progress bar for active milestone
                    if (active && milestone.doneCount < tasks.length) ...[
                      const SizedBox(height: 14),
                      ProgressTrack(milestone.progress,
                          color: color, height: 6),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTask extends StatelessWidget {
  const _MiniTask({
    required this.task,
    required this.color,
    required this.onTap,
  });

  final MilestoneTask task;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final done = task.done;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: done
              ? color.withValues(alpha: 0.06)
              : p.card2.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                done ? Symbols.check_circle : Symbols.circle,
                key: ValueKey(done),
                color: done ? color : p.line2,
                fill: done ? 1 : 0,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(task.name,
                  style: TextStyle(
                      color: done ? p.ink3 : p.ink2,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      decoration:
                          done ? TextDecoration.lineThrough : null)),
            ),
          ],
        ),
      ),
    );
  }
}
