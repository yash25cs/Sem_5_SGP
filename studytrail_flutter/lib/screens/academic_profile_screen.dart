import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../data/repositories/profile_repository.dart';
import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';
import 'login_screen.dart' show FieldLabel, InputField, Validators;

/// Screen where students input or edit their program, school or college, and
/// semester or class.
///
/// Used both immediately after sign-up (onboarding step) and from Settings/Profile
/// for editing later. The program is picked from [AcademicProgram.groups];
/// choosing School swaps the semester for a class and drops the branch.
class AcademicProfileScreen extends StatefulWidget {
  const AcademicProfileScreen({
    super.key,
    this.onDone,
    this.onBack,
    this.isEditing = false,
  });

  final VoidCallback? onDone;
  final VoidCallback? onBack;
  final bool isEditing;

  @override
  State<AcademicProfileScreen> createState() => _AcademicProfileScreenState();
}

class _AcademicProfileScreenState extends State<AcademicProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _college = TextEditingController();
  final _branch = TextEditingController();
  final _otherProgram = TextEditingController();
  AcademicProgram? _program;
  String? _term;
  bool _saving = false;

  /// Set by the first save attempt, so the two dropdowns only show
  /// "required" once the student has tried to continue.
  bool _showPickErrors = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
  }

  Future<void> _prefill() async {
    final store = context.read<ProfileStore>();
    if (!store.loaded) await store.load();
    final p = store.profile;
    if (p != null && mounted) {
      setState(() {
        if (_name.text.isEmpty) _name.text = p.fullName;
        if (_college.text.isEmpty) _college.text = p.college ?? '';

        // Only into an untouched form: the load can land after a pick.
        final place = AcademicPlace.parse(p.branch);
        if (place != null && _program == null) {
          _program = place.program;
          _otherProgram.text = place.customProgram;
          _branch.text = place.specialisation;
          _term = place.term;
        }
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _college.dispose();
    _branch.dispose();
    _otherProgram.dispose();
    super.dispose();
  }

  void _pickProgram(AcademicProgram program) => setState(() {
        _program = program;
        // "Semester 7" means nothing to a Class 9 student, nor "Final" to a
        // B.Com one.
        if (!program.options.contains(_term)) _term = null;
      });

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: context.p.ink,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _submit() async {
    if (_saving) return;
    final valid = _formKey.currentState?.validate() ?? false;
    setState(() => _showPickErrors = true);
    final program = _program;
    if (!valid || program == null || _term == null) return;
    FocusScope.of(context).unfocus();

    setState(() => _saving = true);

    final fullName = _name.text.trim();
    final college = _college.text.trim();
    // Program, branch and semester (or class) in the one `branch` column.
    final branch = AcademicPlace(
      program: program,
      customProgram: _otherProgram.text,
      specialisation: _branch.text,
      term: _term,
    ).format();

    try {
      final repo = const ProfileRepository();
      await repo.updateProfile(
        fullName: fullName,
        college: college,
        branch: branch,
      );

      if (!mounted) return;
      await context.read<ProfileStore>().load();
      if (!mounted) return;
      await context.read<HomeStore>().load();

      if (!mounted) return;
      _toast(widget.isEditing
          ? 'Academic profile updated!'
          : 'Welcome aboard, $fullName!');
      widget.onDone?.call();
    } catch (e) {
      if (mounted) {
        _toast('Could not save details. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final program = _program;
    final isSchool = program?.isSchool ?? false;
    // "semester", "class" or "level", for the hint and the error.
    final termWord = (program?.termLabel ?? 'Semester').toLowerCase();

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),

          // ── App Bar / Step indicator ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 20, 8),
            child: Row(
              children: [
                if (widget.onBack != null)
                  RoundIconButton(Symbols.arrow_back, onTap: widget.onBack)
                else
                  const SizedBox(width: 40),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.primarySoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    widget.isEditing ? 'Settings' : 'Academic Profile',
                    style: TextStyle(
                      color: p.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                children: [
                  // Icon badge
                  Center(
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: p.primarySoft,
                        shape: BoxShape.circle,
                        boxShadow: p.glow,
                      ),
                      child: Icon(Symbols.school,
                          color: p.primary, size: 30),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    widget.isEditing
                        ? 'Edit Academic Profile'
                        : 'Your Academic Details',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.isEditing
                        ? 'Keep your program, school or college, and semester up to date.'
                        : 'Tell us where and what you are studying so StudyTrail can personalize your study roadmap.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.ink2, fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 28),

                  // ── Full Name ──
                  const FieldLabel('Full Name'),
                  InputField(
                    hint: 'Enter your full name',
                    icon: Symbols.person,
                    controller: _name,
                    validator: (v) => Validators.required(v, 'Full name'),
                    textInputAction: TextInputAction.next,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  // ── Program ──
                  const FieldLabel('Program'),
                  _SelectField(
                    icon: Symbols.architecture,
                    hint: 'Select your program',
                    value: program?.name,
                    items: [
                      for (final (group, programs) in AcademicProgram.groups) ...[
                        (text: group, header: true),
                        for (final option in programs)
                          (text: option.name, header: false),
                      ],
                    ],
                    error: _showPickErrors && program == null
                        ? 'Select your program'
                        : null,
                    onChanged: _saving
                        ? null
                        : (name) {
                            final picked = AcademicProgram.byName(name);
                            if (picked != null) _pickProgram(picked);
                          },
                  ),
                  const SizedBox(height: 16),

                  if (program != null && program.isOther) ...[
                    const FieldLabel('Program Name'),
                    InputField(
                      hint: 'Enter your program',
                      icon: Symbols.edit,
                      controller: _otherProgram,
                      validator: (v) => Validators.required(v, 'Program name'),
                      textInputAction: TextInputAction.next,
                      enabled: !_saving,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Branch / Major (not for school) ──
                  if (program != null && !isSchool) ...[
                    const FieldLabel('Branch / Major (optional)'),
                    InputField(
                      hint: 'Enter your branch or major',
                      icon: Symbols.category,
                      controller: _branch,
                      textInputAction: TextInputAction.next,
                      enabled: !_saving,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── School / College Name ──
                  FieldLabel(
                      isSchool ? 'School Name' : 'College / University Name'),
                  InputField(
                    hint: isSchool
                        ? 'Enter your school name'
                        : 'Enter your college name',
                    icon: isSchool ? Symbols.school : Symbols.account_balance,
                    controller: _college,
                    validator: (v) => Validators.required(
                        v, isSchool ? 'School name' : 'College name'),
                    textInputAction: TextInputAction.done,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  // ── Class for school, semester (or level) otherwise ──
                  FieldLabel(isSchool
                      ? 'Class'
                      : 'Current ${program?.termLabel ?? 'Semester'}'),
                  _SelectField(
                    icon: Symbols.calendar_today,
                    hint: program == null
                        ? 'Select your program first'
                        : 'Select your $termWord',
                    value: _term,
                    items: [
                      for (final option in program?.options ?? const <String>[])
                        (text: option, header: false),
                    ],
                    error: _showPickErrors && program != null && _term == null
                        ? 'Select your $termWord'
                        : null,
                    onChanged: _saving
                        ? null
                        : (term) => setState(() => _term = term),
                  ),
                  const SizedBox(height: 30),

                  PillButton(
                    _saving
                        ? 'Saving…'
                        : widget.isEditing
                            ? 'Save Changes'
                            : 'Save & Continue',
                    icon: widget.isEditing
                        ? Symbols.check
                        : Symbols.arrow_forward,
                    onTap: _saving ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dropdown dressed like [InputField]. The form's validators can't see it,
/// so the screen decides when it is in error and passes [error] in.
class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.icon,
    required this.hint,
    required this.value,
    required this.items,
    this.error,
    this.onChanged,
  });

  final IconData icon;
  final String hint;
  final String? value;

  /// The choices; a `header` is a group heading that can't be picked.
  final List<({String text, bool header})> items;
  final String? error;

  /// Null disables the field.
  final ValueChanged<String>? onChanged;

  /// Headings need a value too, and it must not collide with a choice's.
  static String _headerValue(String text) => '#$text';

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final error = this.error;
    final onChanged = this.onChanged;

    Widget line(String text, {required bool chosen}) => Row(
          children: [
            Icon(icon, color: chosen ? p.primary : p.ink3, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: chosen
                      ? TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)
                      : TextStyle(color: p.ink3, fontSize: 14.5)),
            ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 16, right: 10),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: error == null ? p.line : p.error, width: 1.2),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              menuMaxHeight: 420,
              borderRadius: BorderRadius.circular(16),
              dropdownColor: p.card,
              icon: Icon(Symbols.expand_more, color: p.ink3),
              hint: line(hint, chosen: false),
              disabledHint: line(value ?? hint, chosen: value != null),
              selectedItemBuilder: (_) => [
                for (final item in items) line(item.text, chosen: true),
              ],
              items: [
                for (final item in items)
                  item.header
                      ? DropdownMenuItem(
                          value: _headerValue(item.text),
                          enabled: false,
                          child: Text(item.text.toUpperCase(),
                              style: TextStyle(
                                  color: p.primary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6)),
                        )
                      : DropdownMenuItem(
                          value: item.text,
                          child: Text(item.text,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600)),
                        ),
              ],
              onChanged: onChanged == null
                  ? null
                  : (picked) {
                      if (picked != null) onChanged(picked);
                    },
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 16),
            child: Text(error,
                style: TextStyle(
                    color: p.error, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}
