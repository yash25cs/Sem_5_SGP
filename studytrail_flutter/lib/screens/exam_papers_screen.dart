import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/nav.dart';

/// Previous-year papers: upload them, see which of your units they ask about
/// most, and take a mock exam weighted the same way.
class ExamPapersScreen extends StatefulWidget {
  const ExamPapersScreen({
    super.key,
    this.onBack,
    this.onOpenQuiz,
    this.onPractice,
  });

  final VoidCallback? onBack;

  /// Leaves this screen for the Quiz tab, where a new mock exam is waiting.
  final VoidCallback? onOpenQuiz;

  /// Opens long-answer practice on one past question, when available.
  final void Function(PaperQuestion question)? onPractice;

  @override
  State<ExamPapersScreen> createState() => _ExamPapersScreenState();
}

class _ExamPapersScreenState extends State<ExamPapersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ExamPapersStore>().load();
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add({required bool camera}) async {
    final store = context.read<ExamPapersStore>();
    final ok = camera
        ? await store.snapAndUpload()
        : await store.pickAndUpload();
    if (!mounted) return;
    if (store.error != null) {
      _toast(store.error!);
    } else if (ok) {
      final latest = store.papers.firstOrNull;
      _toast(latest == null
          ? 'Paper added.'
          : 'Found ${latest.questionCount} questions in ${latest.title}.');
    }
  }

  Future<void> _mockExam() async {
    final store = context.read<ExamPapersStore>();
    final id = await store.mockExam();
    if (!mounted) return;
    if (id == null) {
      _toast(store.error ?? 'Could not build the mock exam.');
      return;
    }
    await context.read<QuizStore>().load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Mock exam ready: 15 questions.'),
      action: widget.onOpenQuiz == null
          ? null
          : SnackBarAction(label: 'Start', onPressed: widget.onOpenQuiz!),
    ));
  }

  Future<void> _showQuestions(ExamTopic topic) async {
    final p = context.p;
    final store = context.read<ExamPapersStore>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, scroll) => FutureBuilder<List<PaperQuestion>>(
          future: store.questionsFor(topic),
          builder: (context, snap) {
            final questions = snap.data ?? const <PaperQuestion>[];
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                Text(topic.unitLabel,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Asked ${topic.timesAsked} time'
                    '${topic.timesAsked == 1 ? '' : 's'} in past papers',
                    style: TextStyle(color: p.ink3, fontSize: 13)),
                const SizedBox(height: 14),
                if (snap.connectionState != ConnectionState.done)
                  const LoadingBlock(height: 120)
                else if (snap.hasError)
                  Text("Couldn't load those questions.",
                      style: TextStyle(color: p.error))
                else
                  for (final q in questions) ...[
                    _QuestionTile(
                      question: q,
                      onPractice: widget.onPractice == null
                          ? null
                          : () {
                              Navigator.of(sheetCtx).pop();
                              widget.onPractice!(q);
                            },
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<ExamPapersStore>();
    final topics = store.topics.where((t) => !t.isOther).toList();
    final maxAsked = topics.fold<int>(1, (m, t) => t.timesAsked > m ? t.timesAsked : m);

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
                      Text('Past papers',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      Text('What your exam actually asks',
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
                  Text(
                    'Upload previous years\' question papers. StudyTrail '
                    'matches every question to your units, shows what gets '
                    'asked most, and builds a mock exam around it.',
                    style: TextStyle(color: p.ink2, fontSize: 13.5, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: PillButton('Upload a paper',
                            icon: Symbols.upload_file,
                            onTap: store.busy || store.atLimit
                                ? null
                                : () => _add(camera: false)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PillButton('Snap a paper',
                            icon: Symbols.photo_camera,
                            variant: PillVariant.outline,
                            onTap: store.busy || store.atLimit
                                ? null
                                : () => _add(camera: true)),
                      ),
                    ],
                  ),
                  if (store.error != null && !store.busy) ...[
                    const SizedBox(height: 12),
                    ErrorNotice(
                        message: store.error!, onRetry: store.clearError),
                  ],
                  const SizedBox(height: 22),

                  if (store.loading && !store.loaded)
                    const LoadingBlock(height: 160)
                  else if (store.papers.isEmpty)
                    const EmptyState(
                      icon: Symbols.history_edu,
                      title: 'No papers yet',
                      message: 'Add a PDF or a photo of a past paper. Upload '
                          'your notes too, so questions can be matched to '
                          'your units.',
                    )
                  else ...[
                    if (topics.isNotEmpty) ...[
                      CardHeader('Most-asked topics'),
                      AppCard(
                        child: Column(
                          children: [
                            for (var i = 0; i < topics.length; i++) ...[
                              if (i > 0) const SizedBox(height: 14),
                              _TopicRow(
                                topic: topics[i],
                                share: topics[i].timesAsked / maxAsked,
                                onTap: () => _showQuestions(topics[i]),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      AppCard(
                        color: p.primarySoft,
                        shadow: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Symbols.assignment,
                                    color: p.primary, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '15 questions, weighted toward the units '
                                    'that come up most — under exam timing.',
                                    style: TextStyle(
                                        color: p.ink, fontSize: 13, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            PillButton(
                              store.makingMock ? 'Writing…' : 'Take a mock exam',
                              icon: store.makingMock ? null : Symbols.timer,
                              onTap: store.busy ? null : _mockExam,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                    ] else if (store.hasAnalyzed) ...[
                      Text(
                        "None of the questions matched your units yet. Upload "
                        'the notes for this subject, then re-read the paper.',
                        style: TextStyle(color: p.ink3, fontSize: 13),
                      ),
                      const SizedBox(height: 18),
                    ],
                    CardHeader('Your papers'),
                    for (final paper in store.papers) ...[
                      _PaperTile(
                        paper: paper,
                        onRetry: store.busy ? null : () => store.analyze(paper),
                        onRemove: store.busy ? null : () => store.remove(paper),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topic, required this.share, required this.onTap});

  final ExamTopic topic;
  final double share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final marks = topic.totalMarks == topic.totalMarks.roundToDouble()
        ? topic.totalMarks.toInt().toString()
        : topic.totalMarks.toStringAsFixed(1);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(topic.unitLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700)),
              ),
              Text('${topic.timesAsked}×',
                  style: TextStyle(
                      color: p.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              Icon(Symbols.chevron_right, size: 18, color: p.ink3),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              backgroundColor: p.card2,
              color: p.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              '$marks marks',
              if (topic.years.isNotEmpty) topic.years.join(', '),
            ].join(' · '),
            style: TextStyle(color: p.ink3, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PaperTile extends StatelessWidget {
  const _PaperTile({required this.paper, this.onRetry, this.onRemove});

  final ExamPaper paper;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final Widget status;
    if (paper.working) {
      status = SoftChip('Reading…',
          customLeading: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: p.ink3),
          ),
          small: true);
    } else if (paper.failed) {
      status = SoftChip('Retry', icon: Symbols.refresh,
          tone: ChipTone.error, small: true, onTap: onRetry);
    } else {
      status = SoftChip('${paper.questionCount} questions',
          icon: Symbols.check_circle, tone: ChipTone.green, small: true);
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          IconTile(Symbols.history_edu,
              bg: p.primarySoft, fg: p.primary, size: 38, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(paper.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (paper.year != null) ...[
                      Text('${paper.year}',
                          style: TextStyle(color: p.ink3, fontSize: 12)),
                      const SizedBox(width: 8),
                    ],
                    Flexible(child: status),
                  ],
                ),
                if (paper.failed && paper.error != null) ...[
                  const SizedBox(height: 4),
                  Text(paper.error!,
                      style: TextStyle(color: p.error, fontSize: 12)),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Symbols.delete, color: p.ink3, size: 20),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({required this.question, this.onPractice});

  final PaperQuestion question;
  final VoidCallback? onPractice;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final meta = [
      if (question.questionNo != null) question.questionNo!,
      if (question.marks != null)
        '${question.marks! == question.marks!.roundToDouble() ? question.marks!.toInt() : question.marks} marks',
      if (question.year != null) '${question.year}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta.isNotEmpty)
            Text(meta,
                style: TextStyle(
                    color: p.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(question.text,
              style: TextStyle(color: p.ink, fontSize: 13.5, height: 1.45)),
          if (onPractice != null) ...[
            const SizedBox(height: 8),
            SoftChip('Practise answering',
                icon: Symbols.edit_note,
                tone: ChipTone.primary,
                small: true,
                onTap: onPractice),
          ],
        ],
      ),
    );
  }
}
