import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// "How did it go?" once a goal's exams are over: the marks, how it felt, and
/// which units were hard. Pops the [GoalResult] to save, or null.
///
/// Everything is optional: a student who'd rather not give marks can still
/// say what was hard, which is what steers the next goal's roadmap.
class GoalResultSheet extends StatefulWidget {
  const GoalResultSheet({
    super.key,
    required this.goal,
    this.existing,
    this.suggestions = const [],
  });

  final Goal goal;
  final GoalResult? existing;

  /// Units to offer as chips: the goal's subjects and the student's weak
  /// spots.
  final List<String> suggestions;

  @override
  State<GoalResultSheet> createState() => _GoalResultSheetState();
}

class _GoalResultSheetState extends State<GoalResultSheet> {
  late final TextEditingController _marks;
  late final TextEditingController _outOf;
  final _other = TextEditingController();
  int? _feeling;
  late final List<String> _hard;
  late final List<String> _options;
  String? _problem;

  static String _num(double? v) => v == null
      ? ''
      : v == v.roundToDouble()
          ? v.round().toString()
          : v.toString();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _marks = TextEditingController(text: _num(e?.marks));
    _outOf = TextEditingController(text: _num(e?.outOf));
    _feeling = e?.feeling;
    _hard = [...?e?.hardUnits];
    final seen = <String>{};
    _options = [
      for (final u in [...widget.suggestions, ..._hard])
        if (u.trim().isNotEmpty && seen.add(u.trim().toLowerCase())) u.trim(),
    ];
  }

  @override
  void dispose() {
    _marks.dispose();
    _outOf.dispose();
    _other.dispose();
    super.dispose();
  }

  void _toggle(String unit) => setState(() {
        if (!_hard.remove(unit)) _hard.add(unit);
      });

  void _addOther() {
    final unit = _other.text.trim();
    if (unit.isEmpty) return;
    setState(() {
      if (!_options.any((o) => o.toLowerCase() == unit.toLowerCase())) {
        _options.add(unit);
      }
      if (!_hard.any((h) => h.toLowerCase() == unit.toLowerCase())) {
        _hard.add(unit);
      }
      _other.clear();
    });
  }

  void _save() {
    _addOther();
    final marks = double.tryParse(_marks.text.trim());
    final outOf = double.tryParse(_outOf.text.trim());
    final String? problem;
    if (_marks.text.trim().isNotEmpty && marks == null) {
      problem = 'Marks should be a number.';
    } else if (_outOf.text.trim().isNotEmpty && (outOf == null || outOf <= 0)) {
      problem = '"Out of" should be a number above 0.';
    } else if (marks != null && outOf != null && marks > outOf) {
      problem = "Marks can't be more than the total.";
    } else if (marks == null && _feeling == null && _hard.isEmpty) {
      problem = 'Add your marks, how it felt, or what was hard.';
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.of(context).pop(GoalResult(
      goalId: widget.goal.id,
      marks: marks,
      outOf: marks == null ? null : outOf,
      feeling: _feeling,
      hardUnits: _hard.take(20).toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: p.card2,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
        );
    final numbers = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      LengthLimitingTextInputFormatter(6),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How did ${widget.goal.name} go?',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  'All optional. What you mark as hard gets more time in your '
                  'next roadmap.',
                  style: TextStyle(color: p.ink3, fontSize: 12.5)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _marks,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: numbers,
                      decoration: field('Marks'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _outOf,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: numbers,
                      decoration: field('Out of'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('How did it feel?',
                  style: TextStyle(
                      color: p.ink2,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, label) in GoalResult.feelings.indexed)
                    SoftChip(label,
                        tone: _feeling == i + 1
                            ? ChipTone.primary
                            : ChipTone.neutral,
                        icon: _feeling == i + 1 ? Symbols.check : null,
                        onTap: () => setState(
                            () => _feeling = _feeling == i + 1 ? null : i + 1)),
                ],
              ),
              const SizedBox(height: 16),
              Text('What was hard?',
                  style: TextStyle(
                      color: p.ink2,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (_options.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final unit in _options)
                      SoftChip(unit,
                          small: true,
                          tone: _hard.contains(unit)
                              ? ChipTone.coral
                              : ChipTone.neutral,
                          icon: _hard.contains(unit) ? Symbols.check : null,
                          onTap: () => _toggle(unit)),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _other,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _addOther(),
                      decoration: field('Another unit or topic')
                          .copyWith(counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoundIconButton(Symbols.add, plain: false, onTap: _addOther),
                ],
              ),
              if (_problem != null) ...[
                const SizedBox(height: 10),
                Text(_problem!,
                    style: TextStyle(color: p.error, fontSize: 12.5)),
              ],
              const SizedBox(height: 18),
              PillButton('Save', icon: Symbols.check, onTap: _save),
            ],
          ),
        ),
      ),
    );
  }
}
