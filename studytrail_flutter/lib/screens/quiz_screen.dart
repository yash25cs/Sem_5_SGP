import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/expandable_item_card.dart';
import '../widgets/generate_sheet.dart';
import '../widgets/nav.dart';

/// Quiz flow — pick a quiz, answer one MCQ at a time with an explanation
/// reveal, then a server-scored result.
///
/// Correctness is shown from `correct_index` for instant feedback, but the
/// score and XP that count come back from `finish_quiz_attempt`, so a modified
/// app can't award itself points.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, this.onClose});
  final VoidCallback? onClose;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  /// Set once the attempt has been submitted, so the results card replaces the
  /// question view.
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<QuizStore>().load();
    });
  }

  Future<void> _startQuiz(Quiz quiz) async {
    final store = context.read<QuizStore>();
    final ok = await store.start(quiz.id);
    if (!mounted) return;
    if (ok && store.questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This quiz has no questions yet.')),
      );
      store.reset();
      return;
    }
    setState(() => _showResults = false);
  }

  Future<void> _advance() async {
    final store = context.read<QuizStore>();
    final wasLast = store.next();
    if (!wasLast) return;

    final ok = await store.finish();
    if (!mounted) return;
    if (ok) {
      setState(() => _showResults = true);
      // These answers are new evidence for Home's weak spots.
      context.read<WeakSpotsStore>().load();
    }
  }

  void _backToList() {
    context.read<QuizStore>().reset();
    setState(() => _showResults = false);
  }

  Future<void> _useLifeline() async {
    final store = context.read<QuizStore>();
    final ok = await store.useLifeline();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(store.error ?? 'Could not use a 50:50 right now.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<QuizStore>();
    final question = store.current;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          // header — progress bar only makes sense inside a quiz
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 20, 10),
            child: Row(
              children: [
                RoundIconButton(Symbols.close, onTap: widget.onClose),
                const SizedBox(width: 14),
                if (store.quiz != null && !_showResults) ...[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 300),
                        tween: Tween(begin: 0, end: store.progress),
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 8,
                          backgroundColor: p.card2,
                          valueColor: AlwaysStoppedAnimation(p.primary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text('${store.questionNumber}/${store.questionCount}',
                      style: TextStyle(
                          color: p.ink2,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                ] else
                  Expanded(
                    child: Text(_showResults ? 'Results' : 'Practice quiz',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _showResults
                ? _Results(
                    attempt: store.attempt,
                    onDone: _backToList,
                    onRetake: store.quiz == null || store.busy
                        ? null
                        : () => _startQuiz(store.quiz!),
                  )
                : store.quiz == null || question == null
                    ? _QuizPicker(onStart: _startQuiz)
                    : _QuestionView(
                        question: question,
                        picked: store.picked,
                        score: store.runningScore,
                        hidden: store.hiddenOptions,
                        lifelines: store.lifelines,
                        onLifeline: store.canUseLifeline && !store.busy
                            ? _useLifeline
                            : null,
                      ),
          ),
          if (store.quiz != null && question != null && !_showResults)
            FooterBar(
              child: PillButton(
                store.answered
                    ? (store.isLastQuestion ? 'See results' : 'Next question')
                    : 'Pick an answer',
                trailingIcon: store.answered ? Symbols.arrow_forward : null,
                variant:
                    store.answered ? PillVariant.primary : PillVariant.soft,
                onTap: store.answered && !store.busy ? _advance : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Quiz list, shown before an attempt starts.
///
/// Tapping a quiz opens it in place with Start (Retake once it has been
/// finished) and Delete; one is open at a time. A finished quiz shows its
/// last marks and when they were scored.
class _QuizPicker extends StatefulWidget {
  const _QuizPicker({required this.onStart});

  final ValueChanged<Quiz> onStart;

  @override
  State<_QuizPicker> createState() => _QuizPickerState();
}

class _QuizPickerState extends State<_QuizPicker> {
  /// The quiz whose actions are showing, if any.
  String? _open;

  Future<void> _delete(Quiz quiz) async {
    final name = quiz.title ?? 'this quiz';
    final sure = await confirmDelete(
      context,
      title: 'Delete quiz?',
      message: quiz.attempted
          ? '“$name” and all its attempts and marks will be deleted. '
              'XP you earned stays, and so do its cards in My mistakes.'
          : '“$name” will be deleted.',
    );
    if (!sure || !mounted) return;
    final store = context.read<QuizStore>();
    final ok = await store.deleteQuiz(quiz);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Quiz deleted.'
          : store.error ?? 'Could not delete that quiz.'),
    ));
  }

  Future<void> _deleteAll() async {
    final store = context.read<QuizStore>();
    final n = store.available.length;
    final sure = await confirmDelete(
      context,
      title: 'Delete all quizzes?',
      message: 'All $n quiz${n == 1 ? '' : 'zes'}, with every attempt and '
          'mark, will be deleted. XP you earned stays, and so does My '
          'mistakes.',
    );
    if (!sure || !mounted) return;
    final ok = await store.deleteAllQuizzes();
    if (!mounted) return;
    setState(() => _open = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'All quizzes deleted.'
          : store.error ?? 'Could not delete your quizzes.'),
    ));
  }

  /// Writes a new quiz from a file the student picks.
  ///
  /// Appends rather than replaces, so the list grows: each quiz keeps its own
  /// `quiz_attempts` history.
  Future<void> _generate(BuildContext context) async {
    final made = await showGenerateSheet<QuizStore>(
      context,
      title: 'Generate a quiz',
      subtitle: 'Written from one file you uploaded',
      actionLabel: 'Generate quiz',
      unit: 'questions',
      counts: const [5, 10, 15],
      onGenerate: (store, materialId, count) =>
          store.generate(materialId: materialId, length: count),
    );
    if (!made || !context.mounted) return;

    final store = context.read<QuizStore>();
    final quiz =
        store.available.where((q) => q.id == store.generatedQuizId).firstOrNull;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(quiz == null
            ? 'Quiz ready.'
            : '${quiz.title ?? 'Your quiz'} is ready — '
                '${quiz.length ?? quiz.questions.length} questions.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<QuizStore>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        if (store.error != null)
          ErrorNotice(
            message: store.error!,
            onRetry: () => context.read<QuizStore>().load(),
          ),
        CardHeader(
          'Your quizzes',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (store.available.isNotEmpty) ...[
                RoundIconButton(Symbols.delete_sweep,
                    onTap: store.busy ? null : _deleteAll),
                const SizedBox(width: 6),
              ],
              PillButton('New',
                  icon: Symbols.auto_awesome,
                  expand: false,
                  onTap: store.busy ? null : () => _generate(context)),
            ],
          ),
        ),
        if (store.loading && !store.loaded) ...[
          const LoadingBlock(height: 84),
          const LoadingBlock(height: 84),
        ] else if (store.available.isEmpty)
          EmptyState(
            icon: Symbols.quiz,
            title: 'No quizzes yet',
            message:
                'Generate a quiz from a file you uploaded and it will show up here.',
            actionLabel: store.busy ? null : 'Generate a quiz',
            onAction: store.busy ? null : () => _generate(context),
          )
        else
          for (final quiz in store.available)
            _QuizTile(
              quiz: quiz,
              expanded: _open == quiz.id,
              onToggle: () =>
                  setState(() => _open = _open == quiz.id ? null : quiz.id),
              onStart: store.busy ? null : () => widget.onStart(quiz),
              onHistory: store.busy
                  ? null
                  : () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: context.p.card,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        builder: (_) => _AttemptsSheet(quiz: quiz),
                      ),
              onDelete: store.busy ? null : () => _delete(quiz),
            ),
      ],
    );
  }
}

/// One quiz in the list. Finished, it shows the last marks (coloured by how
/// they went) and when, and offers Retake.
class _QuizTile extends StatelessWidget {
  const _QuizTile({
    required this.quiz,
    required this.expanded,
    required this.onToggle,
    required this.onStart,
    required this.onDelete,
    this.onHistory,
  });

  final Quiz quiz;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onStart;
  final VoidCallback? onDelete;

  /// Opens every past attempt; offered once the quiz has been finished.
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final last = quiz.lastAttempt;
    final finishedAt = last?.completedAt;
    final pct = ((last?.accuracy ?? 0) * 100).round();
    final tone = switch (pct) {
      >= 80 => (bg: p.greenSoft, fg: p.green),
      >= 50 => (bg: p.primarySoft, fg: p.primary),
      _ => (bg: p.coralSoft, fg: p.coralInk),
    };

    return ExpandableItemCard(
      expanded: expanded,
      onToggle: onToggle,
      leading: quiz.attempted
          ? IconTile(Symbols.task_alt, bg: tone.bg, fg: tone.fg, size: 46)
          : IconTile(Symbols.quiz, bg: p.primarySoft, fg: p.primary, size: 46),
      title: quiz.title ?? 'Practice quiz',
      badge: quiz.attempted
          ? Tag('${last?.score ?? 0}/${last?.total ?? 0}',
              bg: tone.bg, fg: tone.fg)
          : null,
      details: [
        Text(
            '${quiz.length ?? quiz.questions.length} questions · '
            '${quiz.timerSec}s each',
            style: TextStyle(color: p.ink3, fontSize: 12.5)),
        if (finishedAt != null) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(Symbols.history, color: p.ink3, size: 14),
              const SizedBox(width: 4),
              // The marks are in the badge; this line is when. Two lines
              // rather than an ellipsis, so the time is never cut off.
              Expanded(
                child: Text(
                    'Last attempt: ${whenLabel(finishedAt, DateTime.now())}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink2,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ],
      actions: [
        ItemAction(quiz.attempted ? 'Retake' : 'Start quiz',
            icon: quiz.attempted ? Symbols.replay : Symbols.play_arrow,
            onTap: onStart),
        if (quiz.attempted)
          ItemAction('History', icon: Symbols.history, onTap: onHistory),
        ItemAction('Delete',
            icon: Symbols.delete, danger: true, onTap: onDelete),
      ],
    );
  }
}

/// Every finished attempt at one quiz, newest first, each deletable, with
/// Clear history at the bottom.
class _AttemptsSheet extends StatefulWidget {
  const _AttemptsSheet({required this.quiz});

  final Quiz quiz;

  @override
  State<_AttemptsSheet> createState() => _AttemptsSheetState();
}

class _AttemptsSheetState extends State<_AttemptsSheet> {
  List<QuizAttempt>? _attempts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<QuizStore>().attemptsFor(widget.quiz.id);
      if (mounted) setState(() => _attempts = list);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load past attempts.");
    }
  }

  Future<void> _delete(QuizAttempt a) async {
    final sure = await confirmDelete(
      context,
      title: 'Delete this attempt?',
      message: 'Your ${a.score ?? 0}/${a.total ?? 0} from '
          '${whenLabel(a.completedAt!, DateTime.now())} will be deleted. '
          'XP you earned stays.',
    );
    if (!sure || !mounted) return;
    final store = context.read<QuizStore>();
    final ok = await store.deleteAttempt(a);
    if (!mounted) return;
    if (ok) {
      setState(() => _attempts = [
            for (final x in _attempts ?? const <QuizAttempt>[])
              if (x.id != a.id) x,
          ]);
      if (_attempts!.isEmpty) Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(store.error ?? 'Could not delete that attempt.')));
    }
  }

  Future<void> _clear() async {
    final sure = await confirmDelete(
      context,
      title: 'Clear history?',
      message: 'Every attempt at “${widget.quiz.title ?? 'this quiz'}” will '
          'be deleted. The quiz stays, ready to take again, and XP you '
          'earned stays too.',
    );
    if (!sure || !mounted) return;
    final store = context.read<QuizStore>();
    final ok = await store.clearAttempts(widget.quiz);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(store.error ?? 'Could not clear the history.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final busy = context.watch<QuizStore>().busy;
    final attempts = _attempts;
    final now = DateTime.now();

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text('Past attempts',
              style: TextStyle(
                  color: p.ink, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(widget.quiz.title ?? 'Practice quiz',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.ink2, fontSize: 13.5)),
          const SizedBox(height: 14),
          if (_error != null)
            Text(_error!, style: TextStyle(color: p.ink3, fontSize: 13))
          else if (attempts == null)
            Center(child: CircularProgressIndicator(color: p.primary))
          else if (attempts.isEmpty)
            Text('No finished attempts.',
                style: TextStyle(color: p.ink3, fontSize: 13))
          else ...[
            for (final a in attempts) _AttemptRow(
              attempt: a,
              now: now,
              onDelete: busy ? null : () => _delete(a),
            ),
            const SizedBox(height: 12),
            PillButton('Clear history',
                icon: Symbols.delete_sweep,
                variant: PillVariant.danger,
                onTap: busy ? null : _clear),
          ],
        ],
      ),
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({
    required this.attempt,
    required this.now,
    required this.onDelete,
  });

  final QuizAttempt attempt;
  final DateTime now;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final a = attempt;
    final tone = a.accuracy >= 0.8
        ? (bg: p.greenSoft, fg: p.green)
        : a.accuracy >= 0.5
            ? (bg: p.primarySoft, fg: p.primary)
            : (bg: p.coralSoft, fg: p.coralInk);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Tag('${a.score ?? 0}/${a.total ?? 0}', bg: tone.bg, fg: tone.fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(whenLabel(a.completedAt!, now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
                Text('${(a.accuracy * 100).round()}% · +${a.xpEarned ?? 0} XP',
                    style: TextStyle(color: p.ink3, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete attempt',
            onPressed: onDelete,
            icon: Icon(Symbols.delete, color: p.ink3, size: 20),
          ),
        ],
      ),
    );
  }
}

/// A single question with its four options and the explanation reveal.
class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.question,
    required this.picked,
    required this.score,
    this.hidden = const {},
    this.lifelines = 0,
    this.onLifeline,
  });

  final QuizQuestion question;
  final int? picked;
  final int score;

  /// Options a 50:50 removed.
  final Set<int> hidden;

  /// 50:50 lifelines held; the chip shows only when there are some, or one
  /// was just used here.
  final int lifelines;
  final VoidCallback? onLifeline;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final answered = picked != null;
    final gotIt = answered && question.isCorrect(picked!);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Row(children: [
          SoftChip('+${question.xpReward} XP',
              icon: Symbols.bolt, tone: ChipTone.amber, small: true),
          const SizedBox(width: 8),
          SoftChip('$score correct',
              icon: Symbols.check_circle, tone: ChipTone.green, small: true),
          const Spacer(),
          if (lifelines > 0 || hidden.isNotEmpty)
            Opacity(
              opacity: onLifeline == null ? 0.45 : 1,
              child: SoftChip('50:50 · $lifelines',
                  icon: Symbols.exposure_neg_2,
                  tone: ChipTone.primary,
                  small: true,
                  onTap: onLifeline),
            ),
        ]),
        const SizedBox(height: 20),
        Text(question.question,
            style: TextStyle(
                color: p.ink,
                fontSize: 22,
                height: 1.35,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4)),
        const SizedBox(height: 22),
        for (final (i, option) in question.options.indexed) ...[
          // A removed option fades and stops taking taps, but keeps its
          // place, so A–D don't shuffle under the student's thumb.
          AnimatedOpacity(
            opacity: hidden.contains(i) ? 0.25 : 1,
            duration: const Duration(milliseconds: 300),
            child: _Option(
              label: option,
              index: i,
              picked: picked,
              correct: question.correctIndex,
              onTap: answered || hidden.contains(i)
                  ? null
                  : () => context.read<QuizStore>().pick(i),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (answered && (question.explanation ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          AppCard(
            color: gotIt ? p.greenSoft : p.primarySoft,
            shadow: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(gotIt ? Symbols.check_circle : Symbols.lightbulb,
                    color: gotIt ? p.green : p.primary, fill: 1, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(gotIt ? 'Correct!' : 'Not quite',
                          style: TextStyle(
                              color: gotIt ? p.green : p.primary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(question.explanation!,
                          style: TextStyle(
                              color: p.onPrimarySoft,
                              fontSize: 13,
                              height: 1.45,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Server-scored result of the attempt.
class _Results extends StatelessWidget {
  const _Results({required this.attempt, required this.onDone, this.onRetake});

  final QuizAttempt? attempt;
  final VoidCallback onDone;
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final score = attempt?.score ?? 0;
    final total = attempt?.total ?? 0;
    final pct = ((attempt?.accuracy ?? 0) * 100).round();

    // Tone the celebration to how it actually went.
    final (tone, icon, headline) = switch (pct) {
      >= 80 => (p.green, Symbols.celebration, 'Excellent!'),
      >= 50 => (p.primary, Symbols.trending_up, 'Good effort'),
      _ => (p.coral, Symbols.refresh, 'Keep practising'),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        AppCard(
          child: Column(
            children: [
              IconTile(icon,
                  bg: tone.withValues(alpha: 0.14), fg: tone, size: 60),
              const SizedBox(height: 16),
              Text(headline,
                  style: TextStyle(
                      color: p.ink, fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('You scored $score out of $total',
                  style: TextStyle(color: p.ink3, fontSize: 13.5)),
              const SizedBox(height: 18),
              ProgressTrack(total == 0 ? 0 : score / total,
                  color: tone, height: 10),
              const SizedBox(height: 8),
              Text('$pct% accuracy',
                  style: TextStyle(
                      color: tone, fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ResultStat(
                  Symbols.check_circle, '$score', 'Correct', p.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ResultStat(Symbols.bolt, '+${attempt?.xpEarned ?? 0}',
                  'XP earned', p.onAmber),
            ),
          ],
        ),
        if (total > score) ...[
          const SizedBox(height: 12),
          AppCard(
            color: p.coralSoft,
            shadow: false,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Symbols.replay, color: p.coral, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      total - score == 1
                          ? 'The one you missed is now a card in My mistakes, '
                              'due today.'
                          : 'The ${total - score} you missed are now cards in '
                              'My mistakes, due today.',
                      style: TextStyle(
                          color: p.coralInk,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: PillButton('Retake',
                  icon: Symbols.replay,
                  variant: PillVariant.outline,
                  onTap: onRetake),
            ),
            const SizedBox(width: 10),
            Expanded(child: PillButton('Back to quizzes', onTap: onDone)),
          ],
        ),
      ],
    );
  }
}

class _ResultStat extends StatelessWidget {
  const _ResultStat(this.icon, this.value, this.label, this.color);
  final IconData icon;
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: p.shadowSm,
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24, fill: 1),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                Text(label, style: TextStyle(color: p.ink3, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.index,
    required this.picked,
    required this.correct,
    this.onTap,
  });
  final String label;
  final int index;
  final int? picked;
  final int correct;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final answered = picked != null;
    final isCorrect = index == correct;
    final isPicked = index == picked;

    Color bg = p.card, border = p.line, fg = p.ink, badgeBg = p.card2, badgeFg = p.ink2;
    IconData? mark;
    if (answered) {
      if (isCorrect) {
        bg = p.greenSoft;
        border = p.green;
        fg = p.ink;
        badgeBg = p.green;
        badgeFg = Colors.white;
        mark = Symbols.check;
      } else if (isPicked) {
        bg = p.errorSoft;
        border = p.error;
        badgeBg = p.error;
        badgeFg = Colors.white;
        mark = Symbols.close;
      }
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: border,
              width: (answered && (isCorrect || isPicked)) ? 2 : 1.2),
          boxShadow: (answered && (isCorrect || isPicked)) ? null : p.shadowSm,
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: badgeBg, borderRadius: BorderRadius.circular(9)),
              child: mark != null
                  ? Icon(mark, color: badgeFg, size: 18, weight: 700)
                  : Text(String.fromCharCode(65 + index),
                      style: TextStyle(
                          color: badgeFg,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: fg,
                      fontSize: 14.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
