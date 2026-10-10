import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/custom_pace_sheet.dart';
import '../widgets/data_states.dart';
import '../widgets/nav.dart';

/// Names an exam season, its pace and its subjects — each with the date of its
/// own paper — then creates the `goals` row (plus a `subjects` row per
/// subject) that the rest of the app hangs off. The goal's date is the last
/// paper, so the roadmap finishes before every exam (0018, 0025).
///
/// Serves two entry points: onboarding step 3, and "New goal" from Home or
/// Settings — a student keeps one goal per exam. [stepLabel] and [title] are
/// what distinguish them; the write is identical, and `create_goal` retires the
/// previously active goal, so the new one is the one the app works against.
class SetTargetScreen extends StatefulWidget {
  const SetTargetScreen({
    super.key,
    this.onDone,
    this.onBack,
    this.stepLabel = 'Step 3 of 3',
    this.title = 'Set your target',
  });

  final VoidCallback? onDone;
  final VoidCallback? onBack;

  /// Top-right progress hint. Meaningless outside onboarding, where callers pass
  /// something like 'New goal' instead.
  final String stepLabel;
  final String title;

  @override
  State<SetTargetScreen> createState() => _SetTargetScreenState();
}

class _SetTargetScreenState extends State<SetTargetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  Pace _pace = Pace.steady;

  /// Set when the student chose their own time a day instead of a preset.
  int? _customMinutes;

  /// Starts empty: every student's subjects are different, so none are
  /// guessed. Kept in exam order, so the list reads as their timetable.
  final _subjects = <_NewSubject>[];

  /// Set when a save is tried with no subjects; the next add clears it.
  bool _needsSubject = false;

  static const _paceHours = {
    Pace.relaxed: '1 hr/day',
    Pace.steady: '2 hrs/day',
    Pace.intense: '4 hrs/day',
  };

  static const _chipTones = [
    ChipTone.primary,
    ChipTone.coral,
    ChipTone.green,
    ChipTone.amber,
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The last paper: where the roadmap has to end. Null until a subject is in.
  DateTime? get _lastExam => _subjects.isEmpty ? null : _subjects.last.examDate;

  void _sortSubjects() =>
      _subjects.sort((a, b) => a.examDate.compareTo(b.examDate));

  /// Rough roadmap length shown in the hint card — days to the last exam, or
  /// a pace-based default until a subject is added.
  int get _estimatedDays {
    final exam = _lastExam;
    if (exam == null) {
      return switch (_pace) {
        Pace.relaxed => 45,
        Pace.steady => 30,
        Pace.intense => 21,
      };
    }
    final now = DateTime.now();
    final days = DateTime(exam.year, exam.month, exam.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    return days < 1 ? 1 : days;
  }

  Future<void> _pickCustomPace() async {
    final minutes =
        await showCustomPaceSheet(context, initial: _customMinutes ?? _pace.minutes);
    if (minutes == null || !mounted) return;
    setState(() {
      _customMinutes = minutes;
      _pace = Pace.nearest(minutes);
    });
  }

  Future<void> _changeDate(_NewSubject subject) async {
    final picked = await _pickExamDate(context, subject.name, subject.examDate);
    if (picked == null || !mounted) return;
    setState(() {
      final i = _subjects.indexOf(subject);
      if (i >= 0) _subjects[i] = (name: subject.name, examDate: picked);
      _sortSubjects();
    });
  }

  /// Opens the add-subject sheet and adds what came back.
  ///
  /// The sheet's text controller belongs to [_AddSubjectSheet], not to this
  /// method: `showModalBottomSheet` returns the moment the route pops, while the
  /// sheet is still mounted for its exit animation. Disposing the controller
  /// here — right after the `await` — threw "A TextEditingController was used
  /// after being disposed" from the still-building `TextField`, which is the red
  /// screen reported when adding a subject.
  Future<void> _addSubject() async {
    final p = context.p;

    final added = await showModalBottomSheet<_NewSubject>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _AddSubjectSheet(
          taken: {for (final s in _subjects) s.name.toLowerCase()}),
    );

    if (added == null || !mounted) return;
    setState(() {
      _subjects.add(added);
      _sortSubjects();
      _needsSubject = false;
    });
  }

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (_subjects.isEmpty) setState(() => _needsSubject = true);
    if (!valid || _subjects.isEmpty) return;
    FocusScope.of(context).unfocus();

    final store = context.read<OnboardingStore>();
    final ok = await store.createGoal(
      name: _name.text.trim(),
      examDate: _lastExam,
      pace: _pace,
      subjects: [for (final s in _subjects) s.name],
      subjectExamDates: [for (final s in _subjects) s.examDate],
      dailyMinutes: _customMinutes,
    );
    if (!mounted) return;

    if (ok) {
      widget.onDone?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.error ?? 'Could not save your goal')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<OnboardingStore>();
    final lastExam = _lastExam;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 4),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back, onTap: widget.onBack),
                const Spacer(),
                Text(widget.stepLabel,
                    style: TextStyle(
                        color: p.ink3, fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6)),
                  const SizedBox(height: 8),
                  Text('Add each subject with its exam date. We’ll pace your roadmap around them.',
                      style: TextStyle(color: p.ink2, fontSize: 14, height: 1.5)),
                  const SizedBox(height: 22),

                  if (store.error != null)
                    ErrorNotice(
                      message: store.error!,
                      onRetry: () =>
                          context.read<OnboardingStore>().clearError(),
                    ),

                  _Label('Exam / goal name'),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: p.ink, fontSize: 14.5),
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'Give your goal a name'
                        : null,
                    decoration: _fieldDecoration(context,
                        hint: 'e.g. Semester exams', icon: Symbols.flag),
                  ),
                  const SizedBox(height: 18),

                  _Label('Subjects & exam dates'),
                  for (final (i, subject) in _subjects.indexed) ...[
                    _SubjectRow(
                      subject: subject,
                      tone: _chipTones[i % _chipTones.length],
                      onChangeDate: () => _changeDate(subject),
                      onRemove: () =>
                          setState(() => _subjects.remove(subject)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _AddSubjectButton(
                      first: _subjects.isEmpty, onTap: _addSubject),
                  if (_needsSubject && _subjects.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Text('Add at least one subject with its exam date',
                          style: TextStyle(
                              color: p.error,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 18),

                  _Label('Daily study pace'),
                  Row(
                    children: [
                      for (final pace in Pace.values) ...[
                        Expanded(
                          child: _PaceCard(
                            label: pace.label,
                            hours: _paceHours[pace] ?? '',
                            selected: _customMinutes == null && _pace == pace,
                            onTap: () => setState(() {
                              _pace = pace;
                              _customMinutes = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _PaceCard(
                          key: const ValueKey('pace-custom'),
                          label: 'Custom',
                          hours: _customMinutes == null
                              ? 'Set my own'
                              : '${formatStudyTime(_customMinutes!)}/day',
                          selected: _customMinutes != null,
                          onTap: _pickCustomPace,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  AppCard(
                    color: p.primarySoft,
                    shadow: false,
                    child: Row(
                      children: [
                        Icon(Symbols.auto_awesome, color: p.primary, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                              lastExam == null
                                  ? 'StudyTrail will generate a ~$_estimatedDays-day roadmap with daily tasks and weekly checkpoints.'
                                  : 'StudyTrail will generate a ~$_estimatedDays-day roadmap with daily tasks and weekly checkpoints, finishing before your last exam on ${_dateLabel(lastExam)}.',
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
              ),
            ),
          ),
          FooterBar(
            child: PillButton(
                store.busy ? 'Saving…' : 'Generate my roadmap',
                icon: Symbols.auto_awesome,
                onTap: store.busy ? null : _save),
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context,
    {required String hint, IconData? icon}) {
  final p = context.p;
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: p.ink3, fontSize: 14.5),
    prefixIcon: icon == null ? null : Icon(icon, color: p.ink3, size: 20),
    filled: true,
    fillColor: p.card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: border(p.line, 1.2),
    enabledBorder: border(p.line, 1.2),
    focusedBorder: border(p.primary, 1.6),
    errorBorder: border(p.error, 1.2),
    focusedErrorBorder: border(p.error, 1.6),
  );
}

/// A subject as the form holds it, before the goal exists.
typedef _NewSubject = ({String name, DateTime examDate});

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dateLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

/// Today onwards: an exam already sat isn't something to plan for.
Future<DateTime?> _pickExamDate(
    BuildContext context, String subject, DateTime? current) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return showDatePicker(
    context: context,
    initialDate: current != null && !current.isBefore(today)
        ? current
        : today.add(const Duration(days: 30)),
    firstDate: today,
    lastDate: today.add(const Duration(days: 365 * 3)),
    helpText: subject.isEmpty ? 'Exam date' : '$subject exam date',
  );
}

/// Body of the add-subject sheet: the subject's name and the date of its
/// exam, both required. Pops a [_NewSubject].
///
/// A widget rather than an inline `builder` so the [TextEditingController] is
/// owned by the element that uses it and disposed only once that element is
/// gone. See [_SetTargetScreenState._addSubject] for why that matters.
class _AddSubjectSheet extends StatefulWidget {
  const _AddSubjectSheet({required this.taken});

  /// Lower-cased names already on the form. A repeat is refused here, with a
  /// reason, rather than silently dropped after the sheet closes.
  final Set<String> taken;

  @override
  State<_AddSubjectSheet> createState() => _AddSubjectSheetState();
}

class _AddSubjectSheetState extends State<_AddSubjectSheet> {
  final _controller = TextEditingController();
  DateTime? _examDate;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final picked =
        await _pickExamDate(context, _controller.text.trim(), _examDate);
    if (picked == null || !mounted) return;
    setState(() {
      _examDate = picked;
      _error = null;
    });
  }

  void _submit() {
    final name = _controller.text.trim();
    final date = _examDate;
    String? error;
    if (name.isEmpty) {
      error = 'Enter the subject name';
    } else if (widget.taken.contains(name.toLowerCase())) {
      error = '$name is already added';
    } else if (date == null) {
      error = 'Pick the exam date';
    }
    if (error != null || date == null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop((name: name, examDate: date));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final date = _examDate;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );

    return Padding(
      // Lifts the sheet clear of the keyboard.
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SafeArea(
        top: false,
        // Scrollable so a large font scale or a landscape keyboard squeezes the
        // sheet instead of overflowing it.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add a subject',
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              _Label('Subject'),
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: p.ink, fontSize: 14.5),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                // Name first, then straight on to its date.
                onSubmitted: (_) => date == null ? _pickDate() : _submit(),
                decoration: InputDecoration(
                  hintText: 'Subject name',
                  hintStyle: TextStyle(color: p.ink3, fontSize: 14),
                  prefixIcon:
                      Icon(Symbols.menu_book, color: p.ink3, size: 20),
                  filled: true,
                  fillColor: p.card2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: border(p.line, 1),
                  enabledBorder: border(p.line, 1),
                  focusedBorder: border(p.primary, 1.6),
                ),
              ),
              const SizedBox(height: 14),
              _Label('Exam date'),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: p.card2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.line),
                  ),
                  child: Row(
                    children: [
                      Icon(Symbols.event, color: p.ink3, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                            date == null ? 'Pick a date' : _dateLabel(date),
                            style: TextStyle(
                                color: date == null ? p.ink3 : p.ink,
                                fontSize: 14.5,
                                fontWeight: date == null
                                    ? FontWeight.w400
                                    : FontWeight.w700)),
                      ),
                      Icon(Symbols.expand_more, color: p.ink3, size: 22),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10, left: 4),
                  child: Text(_error!,
                      style: TextStyle(
                          color: p.error,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 18),
              PillButton('Add subject', icon: Symbols.add, onTap: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full-width add button under the subject list — the form's main
/// action until a subject is in, so it is sized like one.
class _AddSubjectButton extends StatelessWidget {
  const _AddSubjectButton({required this.first, required this.onTap});

  /// No subjects yet: worded as the first step.
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: p.primarySoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: p.primary.withValues(alpha: 0.45), width: 1.4),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration:
                    BoxDecoration(color: p.primary, shape: BoxShape.circle),
                child: Icon(Symbols.add, color: p.onPrimary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(first ? 'Add your first subject' : 'Add another subject',
                        style: TextStyle(
                            color: p.onPrimarySoft,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Subject name and its exam date',
                        style: TextStyle(
                            color: p.onPrimarySoft.withValues(alpha: 0.75),
                            fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(Symbols.chevron_right, color: p.onPrimarySoft, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: TextStyle(
                color: context.p.ink2,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      );
}

/// One added subject: its name and exam date. Tap to change the date.
class _SubjectRow extends StatelessWidget {
  const _SubjectRow(
      {required this.subject,
      required this.tone,
      required this.onChangeDate,
      required this.onRemove});
  final _NewSubject subject;
  final ChipTone tone;
  final VoidCallback onChangeDate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (bg, fg) = switch (tone) {
      ChipTone.primary => (p.primarySoft, p.onPrimarySoft),
      ChipTone.coral => (p.coralSoft, p.coralInk),
      ChipTone.green => (p.greenSoft, p.green),
      ChipTone.amber => (p.amberSoft, p.onAmber),
      ChipTone.error => (p.errorSoft, p.onError),
      ChipTone.neutral => (p.card2, p.ink2),
    };
    final exam = subject.examDate;
    final now = DateTime.now();
    final days = DateTime(exam.year, exam.month, exam.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final when = switch (days) {
      <= 0 => 'today',
      1 => 'tomorrow',
      _ => 'in $days days',
    };

    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onChangeDate,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.line, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(Symbols.menu_book, color: fg, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Exam ${_dateLabel(subject.examDate)} · $when',
                        style: TextStyle(color: p.ink2, fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: 'Remove ${subject.name}',
                icon: Icon(Symbols.close, color: p.ink3, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaceCard extends StatelessWidget {
  const _PaceCard(
      {super.key,
      required this.label,
      required this.hours,
      required this.selected,
      this.onTap});
  final String label, hours;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? p.primary : p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? p.primary : p.line, width: 1.4),
          boxShadow: selected ? p.glow : null,
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? p.onPrimary : p.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(hours,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: selected
                        ? p.onPrimary.withValues(alpha: 0.8)
                        : p.ink3,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
