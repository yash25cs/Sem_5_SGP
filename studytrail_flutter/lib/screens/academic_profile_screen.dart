import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../data/repositories/profile_repository.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';
import 'login_screen.dart' show FieldLabel, InputField, Validators;

/// Screen where students input or edit their college, program/branch, roll number,
/// and academic details.
///
/// Used both immediately after sign-up (onboarding step) and from Settings/Profile
/// for editing later.
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
  final _enrollment = TextEditingController();
  String _selectedSemester = 'Semester 5';
  bool _saving = false;

  static const _semesters = [
    'Semester 1',
    'Semester 2',
    'Semester 3',
    'Semester 4',
    'Semester 5',
    'Semester 6',
    'Semester 7',
    'Semester 8',
  ];

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
        if (_enrollment.text.isEmpty) _enrollment.text = p.enrollmentId ?? '';

        final storedBranch = p.branch ?? '';
        if (storedBranch.contains('·')) {
          final parts = storedBranch.split('·');
          _branch.text = parts.first.trim();
          final sem = parts.last.trim();
          if (_semesters.contains(sem)) _selectedSemester = sem;
        } else {
          _branch.text = storedBranch;
        }
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _college.dispose();
    _branch.dispose();
    _enrollment.dispose();
    super.dispose();
  }

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
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() => _saving = true);

    final fullName = _name.text.trim();
    final college = _college.text.trim();
    final enrollment = _enrollment.text.trim();
    // Combine branch + semester for rich academic representation
    final branchWithSem = _branch.text.trim().isNotEmpty
        ? '${_branch.text.trim()} · $_selectedSemester'
        : _selectedSemester;

    try {
      final repo = const ProfileRepository();
      await repo.updateProfile(
        fullName: fullName,
        college: college,
        branch: branchWithSem,
        enrollmentId: enrollment,
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
                        ? 'Keep your college, program, and roll number up to date.'
                        : 'Tell us where and what you are studying so StudyTrail can personalize your study roadmap.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.ink2, fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 28),

                  // ── Full Name ──
                  const FieldLabel('Full Name'),
                  InputField(
                    hint: 'e.g. Yash Patel',
                    icon: Symbols.person,
                    controller: _name,
                    validator: (v) => Validators.required(v, 'Full name'),
                    textInputAction: TextInputAction.next,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  // ── College Name ──
                  const FieldLabel('College / University Name'),
                  InputField(
                    hint: 'e.g. CSPIT, Charusat University',
                    icon: Symbols.account_balance,
                    controller: _college,
                    validator: (v) =>
                        Validators.required(v, 'College name'),
                    textInputAction: TextInputAction.next,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  // ── Program / Degree & Branch ──
                  const FieldLabel('Program & Branch / Major'),
                  InputField(
                    hint: 'e.g. B.Tech Computer Engineering',
                    icon: Symbols.architecture,
                    controller: _branch,
                    validator: (v) =>
                        Validators.required(v, 'Program & Branch'),
                    textInputAction: TextInputAction.next,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  // ── ID / Roll No / Enrollment ID ──
                  const FieldLabel('Student ID / Roll No / Enrollment ID'),
                  InputField(
                    hint: 'e.g. 22CS045 or D25CS118',
                    icon: Symbols.badge,
                    controller: _enrollment,
                    validator: (v) =>
                        Validators.required(v, 'Student ID / Roll No'),
                    textInputAction: TextInputAction.done,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  // ── Current Semester / Year ──
                  const FieldLabel('Current Semester'),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.line, width: 1.2),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedSemester,
                        isExpanded: true,
                        dropdownColor: p.card,
                        icon: Icon(Symbols.expand_more, color: p.ink3),
                        items: [
                          for (final sem in _semesters)
                            DropdownMenuItem(
                              value: sem,
                              child: Row(
                                children: [
                                  Icon(Symbols.calendar_today,
                                      color: p.primary, size: 18),
                                  const SizedBox(width: 10),
                                  Text(
                                    sem,
                                    style: TextStyle(
                                      color: p.ink,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() => _selectedSemester = val);
                                }
                              },
                      ),
                    ),
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
