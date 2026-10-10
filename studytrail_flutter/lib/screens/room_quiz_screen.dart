import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/generate_sheet.dart';
import '../widgets/nav.dart';

/// A quiz a whole study room takes together (`0019_room_quiz.sql`).
///
/// The host picks one of their own notes and how many questions; everyone in
/// the room has to agree before anyone sees a question; everyone gets the same
/// questions; the server marks them, and once the last person hands in (or the
/// host ends it) the whole room sees every score. The top three earn XP.

/// XP for first, second and third — mirrors the `room_quiz_*` rows in
/// `xp_rules`, which is what is actually paid.
const _podiumXp = [30, 20, 10];

/// Host only: pick the kind of quiz, then a material and a size, and propose
/// it to the room.
Future<bool> startGroupQuiz(BuildContext context) async {
  final kind = await showModalBottomSheet<(bool, int)>(
    context: context,
    backgroundColor: context.p.card,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _KindSheet(),
  );
  if (kind == null || !context.mounted) return false;
  final (speed, seconds) = kind;
  // The sheet shows the store's error; an old one (a chat send, say) isn't
  // about this.
  context.read<RoomStore>().clearError();
  return showGenerateSheet<RoomStore>(
    context,
    title: speed ? 'Start a speed round' : 'Start a group quiz',
    subtitle: speed
        ? 'Same question for everyone at once · $seconds s each'
        : 'Everyone in the room gets the same questions',
    actionLabel: 'Write the quiz',
    unit: 'questions',
    counts: RoomStore.quizSizes,
    onGenerate: (store, materialId, count) => store.proposeQuiz(
        materialId: materialId, count: count, speed: speed, seconds: seconds),
  );
}

/// Everyone at their own pace, or a speed round on one clock.
class _KindSheet extends StatefulWidget {
  const _KindSheet();

  @override
  State<_KindSheet> createState() => _KindSheetState();
}

class _KindSheetState extends State<_KindSheet> {
  int _seconds = 20;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget option({
      required Key key,
      required IconData icon,
      required String title,
      required String body,
      required VoidCallback onTap,
      Widget? extra,
    }) =>
        AppCard(
          key: key,
          color: p.card2,
          shadow: false,
          padding: const EdgeInsets.all(14),
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon, bg: p.primarySoft, fg: p.primary, size: 40, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(body,
                        style: TextStyle(color: p.ink2, fontSize: 12.5, height: 1.4)),
                    ?extra,
                  ],
                ),
              ),
            ],
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What kind of quiz?',
                style: TextStyle(
                    color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            option(
              key: const ValueKey('quiz-kind-standard'),
              icon: Symbols.quiz,
              title: 'At your own pace',
              body: 'Everyone answers the same questions in their own time. '
                  'Most right answers wins.',
              onTap: () => Navigator.of(context).pop((false, 20)),
            ),
            const SizedBox(height: 10),
            option(
              key: const ValueKey('quiz-kind-speed'),
              icon: Symbols.bolt,
              title: 'Speed round',
              body: 'One question at a time, on everyone\'s screen at once. '
                  'Faster right answers score more.',
              onTap: () => Navigator.of(context).pop((true, _seconds)),
              extra: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in RoomStore.speedSeconds)
                      SoftChip('$s s',
                          small: true,
                          tone: s == _seconds ? ChipTone.primary : ChipTone.neutral,
                          onTap: () => setState(() => _seconds = s)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}

String _firstName(String name) {
  final first = name.trim().split(' ').first;
  return first.isEmpty ? 'Student' : first;
}

/// The group quiz's place on the room screen, whatever state it is in.
class RoomQuizCard extends StatefulWidget {
  const RoomQuizCard({super.key});

  @override
  State<RoomQuizCard> createState() => _RoomQuizCardState();
}

class _RoomQuizCardState extends State<RoomQuizCard> {
  /// The speed round this card already took the student into.
  String? _openedSpeedRound;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RoomStore>();
    final quiz = store.quiz;

    // A speed round runs on one clock, so everyone in it is taken to the
    // question screen as it starts, not left to notice a card.
    if (quiz != null &&
        quiz.speed &&
        quiz.running &&
        quiz.player(store.myUserId) != null &&
        _openedSpeedRound != quiz.id) {
      _openedSpeedRound = quiz.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RoomQuizScreen()),
        );
      });
    }

    final child = switch (quiz) {
      null => _NoQuiz(store: store),
      RoomQuiz(voting: true) => _Voting(store: store, quiz: quiz),
      RoomQuiz(running: true) => _Running(store: store, quiz: quiz),
      RoomQuiz(finished: true) => _Results(store: store, quiz: quiz),
      _ => _Cancelled(store: store, quiz: quiz),
    };
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle, this.icon});

  final String title;
  final String subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      children: [
        IconTile(icon ?? Symbols.quiz,
            bg: p.primarySoft, fg: p.primary, size: 40, radius: 12),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      color: p.ink3,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Text(text,
        style: TextStyle(color: p.ink2, fontSize: 13, height: 1.45));
  }
}

class _NoQuiz extends StatelessWidget {
  const _NoQuiz({required this.store});

  final RoomStore store;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: 'Group quiz',
          subtitle:
              'Top 3 earn ${_podiumXp[0]} / ${_podiumXp[1]} / ${_podiumXp[2]} XP',
        ),
        const SizedBox(height: 12),
        _Note(store.isHost
            ? 'Pick one of your notes and how many questions. Everyone gets '
                'the same ones, and it starts once the whole room says yes.'
            : "When the host starts a quiz, you'll be asked to join. Everyone "
                'answers the same questions and sees the scores at the end.'),
        if (store.isHost) ...[
          const SizedBox(height: 14),
          if (store.quizWorking)
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: p.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Writing the questions…',
                      style: TextStyle(
                          color: p.ink2,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            )
          else
            PillButton(
              'Start a group quiz',
              icon: Symbols.quiz,
              onTap: () {
                // The function checks this too; saying it here saves a
                // minute of writing questions nobody can take.
                if (store.members.isNotEmpty && store.members.length < 2) {
                  _toast(context,
                      'Share the room code first: a group quiz needs two people.');
                  return;
                }
                startGroupQuiz(context);
              },
            ),
        ],
      ],
    );
  }
}

class _Voting extends StatelessWidget {
  const _Voting({required this.store, required this.quiz});

  final RoomStore store;
  final RoomQuiz quiz;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final me = quiz.player(store.myUserId);
    final waiting = quiz.players.where((pl) => pl.vote == null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: quiz.title,
          subtitle: quiz.speed
              ? 'Speed round · ${quiz.questionCount} questions, '
                  '${quiz.secondsPerQuestion} s each · starts when everyone '
                  'agrees'
              : '${quiz.questionCount} questions · starts when everyone '
                  'agrees',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final pl in quiz.players)
              SoftChip(
                pl.userId == store.myUserId ? 'You' : _firstName(pl.name),
                small: true,
                icon: switch (pl.vote) {
                  true => Symbols.check_circle,
                  false => Symbols.cancel,
                  null => Symbols.hourglass_top,
                },
                tone: switch (pl.vote) {
                  true => ChipTone.green,
                  false => ChipTone.error,
                  null => ChipTone.neutral,
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (me == null)
          const _Note("This quiz was set before you joined. You'll be in the "
              'next one.')
        else if (me.vote == null)
          Row(
            children: [
              Expanded(
                child: PillButton(
                  'Not now',
                  variant: PillVariant.outline,
                  onTap: store.busy ? null : () => _vote(context, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(
                  "I'm in",
                  icon: Symbols.check,
                  onTap: store.busy ? null : () => _vote(context, true),
                ),
              ),
            ],
          )
        else
          _Note(waiting == 0
              ? 'Everyone agreed. Starting…'
              : "You're in. Waiting for $waiting more "
                  '${waiting == 1 ? 'person' : 'people'} to say yes.'),
        if (store.isHost) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: store.busy ? null : () => _cancel(context),
              child: Text('Cancel quiz',
                  style: TextStyle(
                      color: p.error,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _vote(BuildContext context, bool agree) async {
    final store = context.read<RoomStore>();
    final ok = await store.voteQuiz(agree);
    if (!context.mounted) return;
    if (!ok) {
      _toast(context, store.error ?? 'Could not send your answer.');
    } else if (store.quiz?.running == true && store.quiz?.speed == false) {
      // The last yes starts it: straight in. (A speed round's card takes
      // everyone in itself.)
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RoomQuizScreen()),
      );
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final store = context.read<RoomStore>();
    final ok = await store.endQuiz();
    if (!ok && context.mounted) {
      _toast(context, store.error ?? 'Could not cancel the quiz.');
    }
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.store, required this.quiz});

  final RoomStore store;
  final RoomQuiz quiz;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final me = quiz.player(store.myUserId);
    if (quiz.speed) return _SpeedCard(store: store, quiz: quiz, me: me);
    final total = quiz.players.length;
    final done = quiz.submittedCount;
    final answered = store.draftPicks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: quiz.title,
          subtitle: 'Quiz on · $done of $total handed in',
          icon: Symbols.edit_note,
        ),
        const SizedBox(height: 12),
        ProgressTrack(total == 0 ? 0 : done / total,
            color: p.primary, height: 6),
        const SizedBox(height: 14),
        if (me == null)
          const _Note("This quiz started before you joined. You'll be in the "
              'next one.')
        else if (me.submitted)
          const _Note("Handed in. Everyone's scores show up here once the "
              'last person is done.')
        else
          PillButton(
            answered == 0
                ? 'Start the quiz'
                : 'Continue ($answered of ${quiz.questions.length})',
            icon: Symbols.play_arrow,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RoomQuizScreen()),
            ),
          ),
        if (store.isHost) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: store.busy ? null : () => _endNow(context),
              child: Text('End quiz now',
                  style: TextStyle(
                      color: p.error,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _endNow(BuildContext context) async {
    final p = context.p;
    final store = context.read<RoomStore>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: p.card,
        title: Text('End the quiz now?', style: TextStyle(color: p.ink)),
        content: Text(
            "Scores are shown for everyone who has handed in. Anyone who "
            "hasn't gets no score.",
            style: TextStyle(color: p.ink2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Keep going')),
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text('End quiz', style: TextStyle(color: p.error))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await store.endQuiz();
    if (!ok && context.mounted) {
      _toast(context, store.error ?? 'Could not end the quiz.');
    }
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.store, required this.quiz});

  final RoomStore store;
  final RoomQuiz quiz;

  @override
  Widget build(BuildContext context) {
    final me = quiz.player(store.myUserId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: 'Results',
          subtitle: quiz.title,
          icon: Symbols.emoji_events,
        ),
        const SizedBox(height: 12),
        for (final pl in quiz.players)
          _ScoreRow(
            player: pl,
            outOf: quiz.questionCount,
            speed: quiz.speed,
            isMe: pl.userId == store.myUserId,
          ),
        const SizedBox(height: 4),
        _Note('Top 3 with at least one right answer earn '
            '${_podiumXp[0]} / ${_podiumXp[1]} / ${_podiumXp[2]} XP, when two '
            'or more people hand in.'),
        if (me != null &&
            me.submitted &&
            _rightCount(quiz) < quiz.questionCount) ...[
          const SizedBox(height: 6),
          const _Note('The ones you missed are now cards in My mistakes.'),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            if (me != null) ...[
              Expanded(
                child: PillButton(
                  'Answers',
                  icon: Symbols.fact_check,
                  variant: PillVariant.outline,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RoomQuizScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: PillButton(
                'Done',
                variant: PillVariant.soft,
                onTap: store.dismissQuiz,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One line of the results board.
class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.player,
    required this.outOf,
    this.speed = false,
    required this.isMe,
  });

  final RoomQuizPlayer player;
  final int outOf;

  /// Speed rounds score points, not right answers.
  final bool speed;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final rank = player.rank;
    final medal = switch (rank) {
      1 => p.amber,
      2 => p.ink3,
      3 => p.coral,
      _ => null,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? p.primarySoft : p.card2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: medal ?? p.card,
              shape: BoxShape.circle,
            ),
            child: Text(rank == null ? '–' : '$rank',
                style: TextStyle(
                    color: medal != null ? Colors.white : p.ink2,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(isMe ? '${player.name} (you)' : player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text(
            !player.submitted
                ? 'no answers'
                : speed
                    ? '${player.score ?? 0} pts'
                    : '${player.score ?? 0}/$outOf',
            style: TextStyle(
                color: player.submitted ? p.ink : p.ink3,
                fontSize: 13,
                fontWeight: FontWeight.w800),
          ),
          if (player.xpAwarded > 0) ...[
            const SizedBox(width: 8),
            SoftChip('+${player.xpAwarded} XP',
                tone: ChipTone.amber, small: true),
          ],
        ],
      ),
    );
  }
}

class _Cancelled extends StatelessWidget {
  const _Cancelled({required this.store, required this.quiz});

  final RoomStore store;
  final RoomQuiz quiz;

  @override
  Widget build(BuildContext context) {
    RoomQuizPlayer? decliner;
    for (final pl in quiz.players) {
      if (pl.vote == false) decliner = pl;
    }
    final who = decliner == null
        ? null
        : decliner.userId == store.myUserId
            ? 'You'
            : _firstName(decliner.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: quiz.title,
          subtitle: 'Quiz cancelled',
          icon: Symbols.event_busy,
        ),
        const SizedBox(height: 12),
        _Note(who == null
            ? 'The host cancelled this quiz.'
            : '$who said not now, so nobody takes it. The host can start '
                'another one any time.'),
        const SizedBox(height: 14),
        PillButton('OK', variant: PillVariant.soft, onTap: store.dismissQuiz),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The quiz itself
// ─────────────────────────────────────────────────────────────────────────────

/// Answering the room's quiz, waiting for the others, and the answers once
/// it's over. Follows the quiz's state, so the host ending it mid-question
/// lands everyone on the results.
class RoomQuizScreen extends StatefulWidget {
  const RoomQuizScreen({super.key});

  @override
  State<RoomQuizScreen> createState() => _RoomQuizScreenState();
}

class _RoomQuizScreenState extends State<RoomQuizScreen> {
  int _index = 0;

  Future<void> _handIn(RoomStore store, RoomQuiz quiz) async {
    final p = context.p;
    final left = quiz.questions.length - store.draftPicks.length;
    if (left > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: p.card,
          title: Text('Hand in now?', style: TextStyle(color: p.ink)),
          content: Text(
              left == 1
                  ? "One question is still unanswered. It counts as wrong."
                  : '$left questions are still unanswered. They count as '
                      'wrong.',
              style: TextStyle(color: p.ink2)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Keep answering')),
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Hand in')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final ok = await store.submitQuiz();
    if (!ok && mounted) {
      _toast(context, store.error ?? 'Could not hand in. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<RoomStore>();
    final quiz = store.quiz;
    final me = quiz?.player(store.myUserId);

    final Widget body;
    if (store.currentRoom == null || store.closedNotice != null) {
      body = const _Message(
          icon: Symbols.door_front, text: 'This room has closed.');
    } else if (quiz == null || quiz.cancelled) {
      body = const _Message(
          icon: Symbols.event_busy, text: 'This quiz was cancelled.');
    } else if (me == null) {
      body = const _Message(
          icon: Symbols.group, text: "You weren't in the room for this quiz.");
    } else if (quiz.finished) {
      body = _Review(quiz: quiz, me: me);
    } else if (quiz.speed && quiz.running) {
      body = _SpeedRound(quiz: quiz, store: store);
    } else if (quiz.voting || quiz.questions.isEmpty) {
      body = const _Message(
          icon: Symbols.hourglass_top,
          text: 'Waiting for everyone to agree…');
    } else if (me.submitted) {
      final left = quiz.players.length - quiz.submittedCount;
      body = _Message(
        icon: Symbols.task_alt,
        text: 'Handed in!',
        detail: 'Scores show up once ${left == 1 ? 'the last person is' : '$left more people are'} '
            'done, or the host ends the quiz.',
      );
    } else {
      final questions = quiz.questions;
      final i = _index.clamp(0, questions.length - 1);
      final q = questions[i];
      final picked = store.draftPicks[q.id];
      final last = i == questions.length - 1;
      body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: ProgressTrack((i + 1) / questions.length,
                color: p.primary, height: 6),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                Text('Question ${i + 1} of ${questions.length}',
                    style: TextStyle(
                        color: p.ink3,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(q.question,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 20,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
                const SizedBox(height: 20),
                for (final (n, option) in q.options.indexed) ...[
                  _Choice(
                    label: option,
                    index: n,
                    selected: picked == n,
                    onTap: () => store.pickAnswer(q.id, n),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          FooterBar(
            child: Row(
              children: [
                if (i > 0) ...[
                  Expanded(
                    child: PillButton(
                      'Back',
                      variant: PillVariant.outline,
                      onTap: () => setState(() => _index = i - 1),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: PillButton(
                    last ? 'Hand in' : 'Next',
                    icon: last ? Symbols.send : null,
                    trailingIcon: last ? null : Symbols.arrow_forward,
                    onTap: store.busy
                        ? null
                        : last
                            ? () => _handIn(store, quiz)
                            : () => setState(() => _index = i + 1),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back,
                    onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(quiz?.title ?? 'Group quiz',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Text('Group quiz · same questions for everyone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.ink3, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.detail});

  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: p.ink3),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.ink2, fontSize: 13, height: 1.45)),
            ],
            const SizedBox(height: 18),
            PillButton('Back to the room',
                expand: false, onTap: () => Navigator.of(context).maybePop()),
          ],
        ),
      ),
    );
  }
}

/// Every question with this student's pick and the right answer, once the
/// quiz is over.
class _Review extends StatelessWidget {
  const _Review({required this.quiz, required this.me});

  final RoomQuiz quiz;
  final RoomQuizPlayer me;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final summary = !me.submitted
        ? quiz.speed
            ? "You didn't answer in time, so this one has no score."
            : "You didn't hand in, so this one has no score."
        : quiz.speed
            ? '${me.score ?? 0} points · ${_rightCount(quiz)} of '
                '${quiz.questionCount} right'
                '${me.rank != null ? ' · #${me.rank} in the room' : ''}'
                '${me.xpAwarded > 0 ? ' · +${me.xpAwarded} XP' : ''}'
        : 'You got ${me.score ?? 0} of ${quiz.questionCount}'
            '${me.rank != null ? ' · #${me.rank} in the room' : ''}'
            '${me.xpAwarded > 0 ? ' · +${me.xpAwarded} XP' : ''}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        AppCard(
          color: p.primarySoft,
          shadow: false,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Symbols.emoji_events, color: p.primary, fill: 1, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(summary,
                    style: TextStyle(
                        color: p.onPrimarySoft,
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final (i, q) in quiz.questions.indexed) ...[
          Text('${i + 1}. ${q.question}',
              style: TextStyle(
                  color: p.ink,
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final (n, option) in q.options.indexed) ...[
            _Choice(
              label: option,
              index: n,
              selected: quiz.myPicks[q.id] == n,
              correct: q.correctIndex,
            ),
            const SizedBox(height: 8),
          ],
          if ((q.explanation ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Symbols.lightbulb, color: p.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(q.explanation!,
                        style: TextStyle(
                            color: p.ink2, fontSize: 12.5, height: 1.45)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 22),
        ],
      ],
    );
  }
}

/// One option. While answering, [selected] is the student's pick; once the
/// quiz is over [correct] is known and the tile shows right and wrong.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.index,
    required this.selected,
    this.correct,
    this.onTap,
  });

  final String label;
  final int index;
  final bool selected;
  final int? correct;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final reveal = correct != null;
    final isCorrect = reveal && index == correct;

    var bg = p.card;
    var border = p.line;
    var badgeBg = p.card2;
    var badgeFg = p.ink2;
    IconData? mark;
    if (reveal && isCorrect) {
      bg = p.greenSoft;
      border = p.green;
      badgeBg = p.green;
      badgeFg = Colors.white;
      mark = Symbols.check;
    } else if (reveal && selected) {
      bg = p.errorSoft;
      border = p.error;
      badgeBg = p.error;
      badgeFg = Colors.white;
      mark = Symbols.close;
    } else if (!reveal && selected) {
      bg = p.primarySoft;
      border = p.primary;
      badgeBg = p.primary;
      badgeFg = Colors.white;
    }
    final strong = border != p.line;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: strong ? 2 : 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: badgeBg, borderRadius: BorderRadius.circular(8)),
              child: mark != null
                  ? Icon(mark, color: badgeFg, size: 17, weight: 700)
                  : Text(String.fromCharCode(65 + index),
                      style: TextStyle(
                          color: badgeFg,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right answers among this student's picks, once answers are known.
int _rightCount(RoomQuiz quiz) => quiz.questions
    .where((q) => q.correctIndex != null && quiz.myPicks[q.id] == q.correctIndex)
    .length;

/// The card while a speed round runs.
class _SpeedCard extends StatelessWidget {
  const _SpeedCard({required this.store, required this.quiz, required this.me});

  final RoomStore store;
  final RoomQuiz quiz;
  final RoomQuizPlayer? me;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final clock = quiz.clockAt(DateTime.now());
    final at = clock == null || clock.lead
        ? 'starting'
        : 'question ${(clock.index + 1).clamp(1, quiz.questionCount)} of '
            '${quiz.questionCount}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(title: quiz.title, subtitle: 'Speed round on · $at', icon: Symbols.bolt),
        const SizedBox(height: 14),
        if (me == null)
          const _Note("This round started before you joined. You'll be in the "
              'next one.')
        else
          PillButton(
            'Back to the round',
            icon: Symbols.play_arrow,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RoomQuizScreen()),
            ),
          ),
        if (store.isHost) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: store.busy
                  ? null
                  : () async {
                      final ok = await store.endQuiz();
                      if (!ok && context.mounted) {
                        _toast(context, store.error ?? 'Could not end the round.');
                      }
                    },
              child: Text('End round now',
                  style: TextStyle(
                      color: p.error, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }
}

/// A speed round in play, drawn on the server's clock: a countdown to the
/// start, each question with its timer, then a short reveal of the right answer
/// and the scores so far.
class _SpeedRound extends StatefulWidget {
  const _SpeedRound({required this.quiz, required this.store});

  final RoomQuiz quiz;
  final RoomStore store;

  @override
  State<_SpeedRound> createState() => _SpeedRoundState();
}

class _SpeedRoundState extends State<_SpeedRound> {
  late final Timer _ticker;

  /// (question, answering?) last drawn — a change means re-read the quiz.
  (int, bool)? _phase;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final quiz = widget.store.quiz;
    final clock = quiz?.clockAt(DateTime.now());
    if (quiz == null || clock == null) return;
    final phase = (clock.index, clock.answering);
    if (phase != _phase) {
      _phase = phase;
      // A new question to fetch, or one whose answer is now out.
      widget.store.refreshQuiz();
    }
    final last = quiz.questionCount - 1;
    final over = clock.index > last ||
        (clock.index == last && clock.inSlot >= clock.seconds + 1.5);
    if (over && DateTime.now().difference(_lastTick).inSeconds >= 2) {
      _lastTick = DateTime.now();
      widget.store.tickQuiz();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final quiz = widget.quiz;
    final store = widget.store;
    final clock = quiz.clockAt(DateTime.now());
    if (clock == null) return const SizedBox();

    if (clock.lead) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Get ready',
                style: TextStyle(color: p.ink2, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('${clock.secondsLeft.ceil().clamp(1, 5)}',
                style: TextStyle(
                    color: p.primary, fontSize: 72, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('${quiz.questionCount} questions · ${clock.seconds} s each',
                style: TextStyle(color: p.ink3, fontSize: 13)),
          ],
        ),
      );
    }

    final i = clock.index.clamp(0, quiz.questionCount - 1);
    final question = i < quiz.questions.length ? quiz.questions[i] : null;
    if (question == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final picked = quiz.myPicks[question.id];
    final answered = quiz.players.where((pl) => pl.answeredCurrent).length;
    final revealing = clock.revealing && question.correctIndex != null;
    final ranked = [...quiz.players]
      ..sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Question ${i + 1} of ${quiz.questionCount}',
                  style: TextStyle(
                      color: p.ink3, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            Text(
                clock.answering
                    ? '${clock.secondsLeft.ceil()} s'
                    : (i == quiz.questionCount - 1 ? 'Last one' : 'Next in ${clock.secondsLeft.ceil()} s'),
                style: TextStyle(
                    color: clock.answering && clock.secondsLeft <= 5 ? p.coral : p.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        ProgressTrack(
            clock.answering ? (clock.secondsLeft / clock.seconds).clamp(0.0, 1.0) : 0,
            color: clock.secondsLeft <= 5 ? p.coral : p.primary,
            height: 6),
        const SizedBox(height: 18),
        Text(question.question,
            style: TextStyle(
                color: p.ink,
                fontSize: 20,
                height: 1.35,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
        const SizedBox(height: 18),
        for (final (n, option) in question.options.indexed) ...[
          _Choice(
            label: option,
            index: n,
            selected: picked == n,
            correct: revealing ? question.correctIndex : null,
            // Changeable until the window closes (0031); tapping the one
            // already picked does nothing.
            onTap: clock.answering && picked != n && !store.busy
                ? () => store.answerSpeed(question.id, n)
                : null,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 4),
        if (clock.answering)
          Text(
              picked == null
                  ? '$answered of ${quiz.players.length} answered'
                  : 'Tap another option to change it. '
                      '$answered of ${quiz.players.length} answered',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.ink3, fontSize: 12.5, fontWeight: FontWeight.w600))
        else ...[
          Text(
              picked == null
                  ? 'No answer this time.'
                  : picked == question.correctIndex
                      ? 'Right!'
                      : 'Not this one.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scores so far',
                    style: TextStyle(
                        color: p.ink2, fontSize: 12.5, fontWeight: FontWeight.w700)),
                for (final (rank, pl) in ranked.indexed) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${rank + 1}',
                            style: TextStyle(
                                color: p.ink3, fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                      Expanded(
                        child: Text(
                            pl.userId == store.myUserId ? '${pl.name} (you)' : pl.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 13.5,
                                fontWeight: pl.userId == store.myUserId
                                    ? FontWeight.w800
                                    : FontWeight.w600)),
                      ),
                      Text('${pl.score ?? 0}',
                          style: TextStyle(
                              color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
