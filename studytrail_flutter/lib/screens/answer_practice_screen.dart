import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/nav.dart';

/// Writing practice for 5- and 10-mark questions, graded like an examiner
/// would against the student's own notes — typed, or written on paper and
/// photographed, the way the real exam is.
class AnswerPracticeScreen extends StatefulWidget {
  const AnswerPracticeScreen({super.key, this.onBack, this.initial});

  final VoidCallback? onBack;

  /// A question to start on, e.g. one picked from a past paper.
  final PracticeQuestion? initial;

  @override
  State<AnswerPracticeScreen> createState() => _AnswerPracticeScreenState();
}

class _AnswerPracticeScreenState extends State<AnswerPracticeScreen> {
  final _answer = TextEditingController();
  int _words = 0;

  /// Answering on paper: photos of the pages, in order.
  bool _byPhoto = false;
  final List<File> _pages = [];
  static const _maxPages = 3;

  /// How many questions the next set has; the student picks 1–5.
  int _count = 3;

  /// Descriptive theory answers, or case-based NEP application questions.
  AnswerKind _kind = AnswerKind.theory;

  @override
  void initState() {
    super.initState();
    _answer.addListener(() {
      final words = _answer.text.trim().isEmpty
          ? 0
          : _answer.text.trim().split(RegExp(r'\s+')).length;
      if (words != _words) setState(() => _words = words);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<AnswerPracticeStore>();
      final initial = widget.initial;
      if (initial != null) store.use(initial);
      store.load();
    });
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _clearAnswer() {
    _answer.clear();
    setState(_pages.clear);
  }

  Future<void> _newSet() async {
    _clearAnswer();
    await context.read<AnswerPracticeStore>().newQuestions(count: _count, kind: _kind);
  }

  /// The next question in the set, or — after the last — back to choosing
  /// how many to do next.
  void _next() {
    _clearAnswer();
    final store = context.read<AnswerPracticeStore>();
    if (!store.next()) store.clearSet();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await context.read<AnswerPracticeStore>().submit(_answer.text);
  }

  Future<void> _submitPhotos() async {
    final ok =
        await context.read<AnswerPracticeStore>().submitPhotos(List.of(_pages));
    if (ok && mounted) setState(_pages.clear);
  }

  Future<void> _addPages({required bool camera}) async {
    final picker = ImagePicker();
    final room = _maxPages - _pages.length;
    if (room <= 0) return;
    try {
      // Big enough to read small handwriting, small enough to upload fast.
      const width = 2000.0;
      const quality = 80;
      final List<XFile> picked;
      if (camera || room == 1) {
        final one = await picker.pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          maxWidth: width,
          imageQuality: quality,
        );
        picked = [?one];
      } else {
        picked = await picker.pickMultiImage(
          maxWidth: width,
          imageQuality: quality,
          limit: room,
        );
      }
      if (!mounted || picked.isEmpty) return;
      setState(() =>
          _pages.addAll(picked.take(room).map((x) => File(x.path))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(camera
              ? "Couldn't open the camera."
              : "Couldn't open your photos.")));
    }
  }

  String _marks(double m) =>
      m == m.roundToDouble() ? m.toInt().toString() : m.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<AnswerPracticeStore>();
    final question = store.question;
    final result = store.result;

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
                      Text('Answer practice',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      Text('Write it like the exam, get marked like it',
                          style: TextStyle(color: p.ink3, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                if (store.error != null && !store.busy) ...[
                  ErrorNotice(message: store.error!, onRetry: store.clearError),
                  const SizedBox(height: 12),
                ],
                if (question == null)
                  _SetPicker(
                    count: _count,
                    kind: _kind,
                    busy: store.busy,
                    onKind: (k) => setState(() => _kind = k),
                    onCount: (n) => setState(() => _count = n),
                    onStart: _newSet,
                  )
                else ...[
                  _QuestionCard(
                    question: question,
                    marks: _marks,
                    position: store.setSize > 1
                        ? 'Question ${store.position} of ${store.setSize}'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  if (result == null) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SoftChip('Type it',
                            key: const ValueKey('answer-mode-type'),
                            icon: Symbols.keyboard,
                            tone: _byPhoto ? ChipTone.neutral : ChipTone.primary,
                            onTap: store.busy
                                ? null
                                : () => setState(() => _byPhoto = false)),
                        SoftChip('Photo of my paper',
                            key: const ValueKey('answer-mode-photo'),
                            icon: Symbols.photo_camera,
                            tone: _byPhoto ? ChipTone.primary : ChipTone.neutral,
                            onTap: store.busy
                                ? null
                                : () => setState(() => _byPhoto = true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (result == null && _byPhoto) ...[
                    _PhotoAnswer(
                      pages: _pages,
                      maxPages: _maxPages,
                      busy: store.busy,
                      onCamera: () => _addPages(camera: true),
                      onGallery: () => _addPages(camera: false),
                      onRemove: (i) => setState(() => _pages.removeAt(i)),
                    ),
                    const SizedBox(height: 14),
                    PillButton(
                      store.busy
                          ? 'Reading your handwriting…'
                          : _pages.length > 1
                              ? 'Grade my ${_pages.length} pages'
                              : 'Grade my handwriting',
                      icon: store.busy ? null : Symbols.grading,
                      onTap: store.busy || _pages.isEmpty ? null : _submitPhotos,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: store.busy ? null : _next,
                        child: Text(store.hasNext
                            ? 'Skip to the next question'
                            : 'Choose new questions'),
                      ),
                    ),
                  ] else if (result == null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: p.line),
                      ),
                      child: TextField(
                        controller: _answer,
                        minLines: 10,
                        maxLines: null,
                        maxLength: 12000,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(color: p.ink, fontSize: 14.5, height: 1.5),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          hintText: 'Write your answer as you would in the exam…',
                          hintStyle: TextStyle(color: p.ink3, fontSize: 14),
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      question.kind == AnswerKind.nep
                          ? '$_words words · answer each part (a, b, c…) '
                              'separately and give a reason from the case'
                          : question.marks >= 10
                              ? '$_words words · a 10-mark answer is usually 250–400'
                              : '$_words words · a 5-mark answer is usually 120–200',
                      style: TextStyle(color: p.ink3, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    PillButton(
                      store.busy ? 'Grading…' : 'Submit for grading',
                      icon: store.busy ? null : Symbols.grading,
                      onTap: store.busy || _words < 5 ? null : _submit,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: store.busy ? null : _next,
                        child: Text(store.hasNext
                            ? 'Skip to the next question'
                            : 'Choose new questions'),
                      ),
                    ),
                  ] else ...[
                    _ResultCard(attempt: result, marks: _marks),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: PillButton('Improve my answer',
                              icon: Symbols.edit,
                              variant: PillVariant.outline,
                              onTap: store.busy ? null : store.retry),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: store.hasNext
                              ? PillButton('Next question',
                                  trailingIcon: Symbols.arrow_forward,
                                  onTap: store.busy ? null : _next)
                              : PillButton('New questions',
                                  icon: Symbols.refresh,
                                  onTap: store.busy ? null : _next),
                        ),
                      ],
                    ),
                  ],
                ],
                if (store.history.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  CardHeader('Recent answers'),
                  for (final a in store.history.take(10)) ...[
                    _HistoryRow(attempt: a, marks: _marks),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Before a set: how many questions (1–5), and the button that writes them.
class _SetPicker extends StatelessWidget {
  const _SetPicker({
    required this.count,
    required this.kind,
    required this.busy,
    required this.onKind,
    required this.onCount,
    required this.onStart,
  });

  final int count;
  final AnswerKind kind;
  final bool busy;
  final ValueChanged<AnswerKind> onKind;
  final ValueChanged<int> onCount;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(Symbols.edit_note, bg: p.primarySoft, fg: p.primary, size: 48),
          const SizedBox(height: 12),
          Text('Practise written answers',
              style: TextStyle(
                  color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              kind == AnswerKind.nep
                  ? 'Case-based questions in the NEP style: a real situation, '
                      'then parts that ask you to choose, estimate, analyse '
                      'and justify. Marked part by part.'
                  : 'Get 5 or 10-mark questions from your weakest units, write '
                      'your answers, and see what an examiner would give each '
                      'one — and what was missing.',
              style: TextStyle(color: p.ink2, fontSize: 13, height: 1.45)),
          const SizedBox(height: 18),
          Text('Type of question',
              style: TextStyle(
                  color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftChip('Theory',
                  key: const ValueKey('kind-theory'),
                  icon: Symbols.menu_book,
                  tone: kind == AnswerKind.theory
                      ? ChipTone.primary
                      : ChipTone.neutral,
                  onTap: busy ? null : () => onKind(AnswerKind.theory)),
              SoftChip('Practical (NEP)',
                  key: const ValueKey('kind-nep'),
                  icon: Symbols.psychology,
                  tone: kind == AnswerKind.nep
                      ? ChipTone.primary
                      : ChipTone.neutral,
                  onTap: busy ? null : () => onKind(AnswerKind.nep)),
            ],
          ),
          const SizedBox(height: 18),
          Text('How many questions?',
              style: TextStyle(
                  color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var n = 1; n <= AnswerPracticeStore.maxQuestions; n++) ...[
                if (n > 1) const SizedBox(width: 8),
                Expanded(
                  child: _CountChoice(
                    n,
                    selected: n == count,
                    onTap: busy ? null : () => onCount(n),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          PillButton(
            busy
                ? (count == 1 ? 'Writing a question…' : 'Writing your questions…')
                : count == 1
                    ? 'Give me a question'
                    : 'Give me $count questions',
            icon: busy ? null : Symbols.auto_awesome,
            onTap: busy ? null : onStart,
          ),
        ],
      ),
    );
  }
}

class _CountChoice extends StatelessWidget {
  const _CountChoice(this.n, {required this.selected, this.onTap});
  final int n;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: selected ? p.primary : p.card2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? p.primary : p.line),
          ),
          child: Text('$n',
              style: TextStyle(
                  color: selected ? p.onPrimary : p.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard(
      {required this.question, required this.marks, this.position});

  final PracticeQuestion question;
  final String Function(double) marks;

  /// "Question 2 of 3", in a set of more than one.
  final String? position;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (position != null)
                SoftChip(position!,
                    icon: Symbols.format_list_numbered,
                    tone: ChipTone.amber,
                    small: true),
              SoftChip('${marks(question.marks)} marks',
                  tone: ChipTone.primary, small: true),
              if (question.kind == AnswerKind.nep)
                const SoftChip('Case-based',
                    icon: Symbols.psychology, tone: ChipTone.green, small: true),
              if (question.unitLabel != null)
                SoftChip(question.unitLabel!, icon: Symbols.menu_book, small: true),
              if (question.paperQuestionId != null)
                const SoftChip('Past paper',
                    icon: Symbols.history_edu, tone: ChipTone.amber, small: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(question.text,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  height: 1.45)),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.attempt, required this.marks});

  final AnswerAttempt attempt;
  final String Function(double) marks;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final f = attempt.feedback;
    final tone = attempt.fraction >= 0.7
        ? p.green
        : attempt.fraction >= 0.4
            ? p.amber
            : p.coral;

    Widget section(String title, IconData icon, Color color, List<String> points) =>
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final point in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(point,
                            style: TextStyle(
                                color: p.ink2, fontSize: 13, height: 1.4)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: attempt.fraction,
                      strokeWidth: 6,
                      backgroundColor: p.card2,
                      color: tone,
                    ),
                    Text(marks(attempt.score),
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${marks(attempt.score)} / ${marks(attempt.maxMarks)} marks',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(f.summary,
                        style: TextStyle(color: p.ink2, fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
          if (!f.usedNotes)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'None of your notes covered this, so it was marked on general '
                'knowledge.',
                style: TextStyle(color: p.ink3, fontSize: 12),
              ),
            ),
          if (f.fromPhoto && attempt.answer.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('What I read from your page',
                    style: TextStyle(
                        color: p.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                subtitle: Text('Marked as read. [illegible] counts as missing.',
                    style: TextStyle(color: p.ink3, fontSize: 11.5)),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(attempt.answer,
                        style: TextStyle(color: p.ink2, fontSize: 13, height: 1.5)),
                  ),
                ],
              ),
            ),
          if (f.strengths.isNotEmpty)
            section('What you got right', Symbols.check_circle, p.green, f.strengths),
          if (f.missing.isNotEmpty)
            section('What would earn more', Symbols.add_circle, p.amber, f.missing),
          if (f.modelAnswer.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Full-marks outline',
                    style: TextStyle(
                        color: p.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(f.modelAnswer,
                        style: TextStyle(color: p.ink2, fontSize: 13, height: 1.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.attempt, required this.marks});

  final AnswerAttempt attempt;
  final String Function(double) marks;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Text(attempt.question,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 13.5)),
          ),
          const SizedBox(width: 10),
          if (attempt.kind == AnswerKind.nep) ...[
            const SoftChip('NEP', tone: ChipTone.green, small: true),
            const SizedBox(width: 6),
          ],
          SoftChip('${marks(attempt.score)}/${marks(attempt.maxMarks)}',
              tone: attempt.fraction >= 0.7
                  ? ChipTone.green
                  : attempt.fraction >= 0.4
                      ? ChipTone.amber
                      : ChipTone.coral,
              small: true),
        ],
      ),
    );
  }
}

/// The pages of a handwritten answer: thumbnails, and buttons to add more.
class _PhotoAnswer extends StatelessWidget {
  const _PhotoAnswer({
    required this.pages,
    required this.maxPages,
    required this.busy,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  final List<File> pages;
  final int maxPages;
  final bool busy;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final full = pages.length >= maxPages;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Write your answer on paper, the way you would in the exam, then '
            'photograph each page — up to $maxPages. It is read, marked, and '
            'the photos are deleted.',
            style: TextStyle(color: p.ink2, fontSize: 13, height: 1.45),
          ),
          if (pages.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (i, page) in pages.indexed)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(page,
                            width: 72,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                                width: 72, height: 96, color: p.card2)),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                      if (!busy)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: GestureDetector(
                            onTap: () => onRemove(i),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Symbols.close,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  pages.isEmpty ? 'Take a photo' : 'Next page',
                  icon: Symbols.photo_camera,
                  variant: PillVariant.outline,
                  onTap: busy || full ? null : onCamera,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(
                  'From gallery',
                  icon: Symbols.photo_library,
                  variant: PillVariant.outline,
                  onTap: busy || full ? null : onGallery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
