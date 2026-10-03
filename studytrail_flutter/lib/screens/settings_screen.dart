import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../data/local_prefs.dart';
import '../services/calendar_export.dart';
import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../state/reminder_sync.dart';
import '../widgets/nav.dart';
import 'academic_profile_screen.dart';
import 'set_target_screen.dart';

/// Full settings screen — grouped preference rows with a back button.
///
/// Notifications and sound are local-only switches for now; everything under
/// "Study" and "Account" writes straight to Postgres through [ProfileStore].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// The 6 PM study reminder. Read from the device on open; the switch used
  /// to be a local bool that reset every visit and scheduled nothing.
  bool _notifications = true;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProfileStore>().load();
    });
    LocalPrefs.remindersEnabled().then((on) {
      if (mounted) setState(() => _notifications = on);
    });
  }

  Future<void> _setReminders(bool on) async {
    setState(() => _notifications = on);
    await LocalPrefs.setRemindersEnabled(on);
    await ReminderSync.run(askPermission: on);
    _toast(on
        ? 'Reminders on: 6 PM, and 9 PM if your streak is at risk.'
        : 'Daily study reminder turned off.');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens the full academic profile editor screen.
  Future<void> _editProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AcademicProfileScreen(
          isEditing: true,
          onDone: () => Navigator.pop(context),
          onBack: () => Navigator.pop(context),
        ),
      ),
    );
    if (mounted) context.read<ProfileStore>().load();
  }

  /// The goal manager — a row per goal, plus a way to add one.
  ///
  /// Replaces a dead end: the three Study rows used to toast "Set a study goal
  /// first" with no way to actually set one.
  Future<void> _manageGoals() async {
    final store = context.read<ProfileStore>();
    final p = context.p;

    if (store.allGoals.isEmpty) {
      await _newGoal();
      return;
    }

    final activeId = store.activeGoal?.id;
    final picked = await _showSheet<(String, String)>(
      title: 'Your study goals',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('One goal per exam. StudyTrail plans against the active one.',
              style: TextStyle(color: p.ink3, fontSize: 12.5)),
          const SizedBox(height: 6),
          for (final g in store.allGoals)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Symbols.flag,
                  color: g.id == activeId ? p.primary : p.ink3),
              title: Text(g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${_dateLabel(g.examDate)} · ${g.pace.label}'
                  '${g.id == activeId ? ' · active' : ''}',
                  style: TextStyle(color: p.ink3, fontSize: 12)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (g.id != activeId)
                    IconButton(
                      tooltip: 'Make active',
                      icon: Icon(Symbols.check_circle, color: p.primary),
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(('activate', g.id)),
                    ),
                  IconButton(
                    tooltip: 'Rename',
                    icon: Icon(Symbols.edit, color: p.ink3),
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(('rename', g.id)),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Symbols.delete, color: p.error),
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(('delete', g.id)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          PillButton('Add a study goal',
              icon: Symbols.add,
              onTap: () => Navigator.of(sheetContext).pop(('new', ''))),
        ],
      ),
    );

    if (picked == null || !mounted) return;
    final (action, goalId) = picked;

    switch (action) {
      case 'new':
        await _newGoal();
      case 'activate':
        final ok = await store.setActiveGoal(goalId);
        _toast(ok ? 'Goal switched' : store.error ?? 'Could not switch goal');
      case 'rename':
        await _editGoalName(goalId: goalId);
      case 'delete':
        await _confirmDeleteGoal(goalId);
    }
  }

  /// Opens the goal form. Same screen as onboarding step 3 — `create_goal`
  /// retires the previous active goal, so the new one takes over.
  Future<void> _newGoal() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (routeContext) => SetTargetScreen(
        stepLabel: 'New goal',
        title: 'New study goal',
        onDone: () => Navigator.of(routeContext).pop(),
        onBack: () => Navigator.of(routeContext).pop(),
      ),
    ));
    if (!mounted) return;
    await context.read<ProfileStore>().reloadGoals();
    // Home reads the same rows through its own store.
    if (mounted) await context.read<HomeStore>().load();
  }

  Future<void> _confirmDeleteGoal(String goalId) async {
    final store = context.read<ProfileStore>();
    final goal = store.allGoals.where((g) => g.id == goalId).firstOrNull;
    if (goal == null) return;
    final p = context.p;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Delete “${goal.name}”?',
            style: TextStyle(
                color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        content: Text(
            'Its subjects, roadmap and tasks go with it. Study sessions you '
            'already logged are kept.',
            style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: TextStyle(color: p.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete',
                style: TextStyle(color: p.error, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await store.removeGoal(goalId);
    _toast(ok ? 'Goal deleted' : store.error ?? 'Could not delete');
    if (ok && mounted) await context.read<HomeStore>().load();
  }

  /// Renames [goalId], or the active goal when none is named.
  Future<void> _editGoalName({String? goalId}) async {
    final store = context.read<ProfileStore>();
    final goal = goalId == null
        ? store.activeGoal
        : store.allGoals.where((g) => g.id == goalId).firstOrNull;
    if (goal == null) {
      await _manageGoals();
      return;
    }

    // The field keeps its own controller (see [_SheetField]); this just
    // follows what's typed.
    var name = goal.name;
    final saved = await _showSheet<bool>(
      title: 'Study goal',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetField(
              initialValue: goal.name,
              label: 'Goal name',
              onChanged: (v) => name = v),
          const SizedBox(height: 18),
          PillButton('Save',
              onTap: () => Navigator.of(sheetContext).pop(true)),
        ],
      ),
    );

    if (saved == true && name.trim().isNotEmpty) {
      final ok = await store.updateGoal(goalId: goal.id, name: name.trim());
      _toast(ok ? 'Goal updated' : store.error ?? 'Could not save');
    }
  }

  Future<void> _editExamDate() async {
    final store = context.read<ProfileStore>();
    final goal = store.activeGoal;
    if (goal == null) {
      // No goal to edit a date on — send them to the one screen that helps.
      await _manageGoals();
      return;
    }

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: goal.examDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: 'Exam date',
    );
    if (picked == null) return;

    final ok = await store.updateGoal(examDate: picked);
    _toast(ok ? 'Exam date updated' : store.error ?? 'Could not save');
  }

  Future<void> _editPace() async {
    final store = context.read<ProfileStore>();
    final goal = store.activeGoal;
    if (goal == null) {
      await _manageGoals();
      return;
    }

    final picked = await _showSheet<Pace>(
      title: 'Study pace',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final pace in Pace.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Symbols.speed, color: context.p.primary),
              title: Text(pace.label,
                  style: TextStyle(
                      color: context.p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              trailing: goal.pace == pace
                  ? Icon(Symbols.check, color: context.p.primary)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(pace),
            ),
        ],
      ),
    );
    if (picked == null) return;

    final ok = await store.updateGoal(pace: picked);
    _toast(ok ? 'Pace updated' : store.error ?? 'Could not save');
  }

  Future<void> _exportCalendar() async {
    _toast('Putting your calendar together…');
    try {
      final events = await CalendarExport.collectAndShare();
      if (events == 0) {
        _toast('Nothing to add yet — set an exam date or plan a roadmap first.');
      }
    } catch (_) {
      _toast("Couldn't build your calendar. Check your connection.");
    }
  }

  Future<void> _pickLanguage() async {
    final store = context.read<ProfileStore>();
    final current = store.profile?.answerLanguage ?? AnswerLanguage.english;
    final picked = await _showSheet<AnswerLanguage>(
      title: 'Explain things in',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Chat answers, summaries and answer feedback. Questions and '
              'technical terms stay in English, like the exam.',
              style: TextStyle(
                  color: context.p.ink3, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 6),
          for (final language in AnswerLanguage.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Symbols.translate, color: context.p.primary),
              title: Text(language.label,
                  style: TextStyle(
                      color: context.p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              trailing: current == language
                  ? Icon(Symbols.check, color: context.p.primary)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(language),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    final ok = await store.setAnswerLanguage(picked);
    _toast(ok
        ? 'Explanations will come in ${picked.label}.'
        : store.error ?? 'Could not save');
  }

  /// Joining a class is what puts the student on the leaderboard.
  Future<void> _pickClass() async {
    final store = context.read<ProfileStore>();
    if (store.classes.isEmpty) await store.loadClasses();
    if (!mounted) return;

    if (store.classes.isEmpty) {
      _toast('No classes are set up yet.');
      return;
    }

    final currentId = store.profile?.classId;
    final picked = await _showSheet<String>(
      title: 'Your class',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in store.classes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Symbols.groups, color: context.p.primary),
              title: Text((c['name'] as String?) ?? 'Class',
                  style: TextStyle(
                      color: context.p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              trailing: currentId == c['id']
                  ? Icon(Symbols.check, color: context.p.primary)
                  : null,
              onTap: () =>
                  Navigator.of(sheetContext).pop(c['id'] as String),
            ),
          if (currentId != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Symbols.logout, color: context.p.error),
              title: Text('Leave class',
                  style: TextStyle(
                      color: context.p.error,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              onTap: () => Navigator.of(sheetContext).pop('__leave__'),
            ),
        ],
      ),
    );
    if (picked == null) return;

    final ok = picked == '__leave__'
        ? await store.leaveClass()
        : await store.joinClass(picked);
    _toast(ok ? 'Class updated' : store.error ?? 'Could not save');
  }

  Future<void> _logout() async {
    final p = context.p;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Log out?',
            style: TextStyle(
                color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        content: Text('Your progress stays saved to your account.',
            style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: TextStyle(color: p.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Log out',
                style:
                    TextStyle(color: p.error, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    await context.read<AuthStore>().signOut();
  }

  /// Permanently deletes the account and all data. Two-step confirmation:
  /// first a warning dialog, then a text-entry gate.
  Future<void> _deleteAccount() async {
    final p = context.p;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: p.card,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Delete your account?',
                style: TextStyle(
                    color: p.error, fontSize: 18, fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'This permanently deletes your profile, study goals, '
                    'materials, quizzes, flashcards, chat history, and all '
                    'progress. This cannot be undone.',
                    style:
                        TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
                const SizedBox(height: 16),
                Text('Type DELETE to confirm:',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  onChanged: (_) => setDialogState(() {}),
                  style: TextStyle(color: p.ink, fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: 'DELETE',
                    hintStyle: TextStyle(color: p.ink3),
                    filled: true,
                    fillColor: p.card2,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: p.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: p.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: p.error, width: 1.6),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text('Cancel', style: TextStyle(color: p.ink3)),
              ),
              TextButton(
                onPressed: controller.text.trim() == 'DELETE'
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: Text('Delete forever',
                    style: TextStyle(
                        color: controller.text.trim() == 'DELETE'
                            ? p.error
                            : p.ink3,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          );
        });
      },
    );
    if (confirmed != true || !mounted) return;

    _toast('Deleting your account…');
    final ok = await context.read<AuthStore>().deleteAccount();
    if (!mounted) return;
    if (!ok) {
      _toast(context.read<AuthStore>().error ?? 'Could not delete account');
    }
  }

  /// Shared bottom-sheet chrome for the editors above.
  Future<T?> _showSheet<T>({
    required String title,
    required WidgetBuilder builder,
  }) {
    final p = context.p;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              builder(sheetContext),
            ],
          ),
        ),
      ),
    );
  }

  String _dateLabel(DateTime? d) =>
      d == null ? 'Not set' : '${_months[d.month - 1]} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final theme = context.watch<ThemeController>();
    final store = context.watch<ProfileStore>();
    final profile = store.profile;
    final goal = store.activeGoal;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 6),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back, onTap: widget.onBack),
                const SizedBox(width: 8),
                Text('Settings',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (store.error != null)
                  ErrorNotice(
                    message: store.error!,
                    onRetry: () => context.read<ProfileStore>().load(),
                  ),

                // profile summary
                if (profile == null)
                  const LoadingBlock(height: 92)
                else
                  AppCard(
                    onTap: store.busy ? null : _editProfile,
                    child: Row(
                      children: [
                        GradAvatar(profile.initial, size: 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  profile.fullName.isEmpty
                                      ? 'Add your name'
                                      : profile.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800)),
                              Text(profile.email ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: p.ink3, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        SoftChip('Edit',
                            icon: Symbols.edit,
                            tone: ChipTone.primary,
                            small: true,
                            onTap: store.busy ? null : _editProfile),
                      ],
                    ),
                  ),
                const SizedBox(height: 22),

                _GroupLabel('Preferences'),
                _Group(children: [
                  _Row(Symbols.dark_mode, 'Dark mode', p.primary,
                      trailing: Switch(
                        value: theme.isDark,
                        onChanged: (v) =>
                            context.read<ThemeController>().set(v),
                      )),
                  // "Sound effects" used to sit here too, a switch wired to
                  // nothing — the app plays no sounds.
                  _Row(Symbols.notifications, 'Daily study reminder', p.coral,
                      value: '6:00 PM',
                      trailing: Switch(
                        value: _notifications,
                        onChanged: _setReminders,
                      )),
                  _Row(Symbols.translate, 'Explanations in', p.green,
                      value: (profile?.answerLanguage ?? AnswerLanguage.english)
                          .label
                          .split(' ')
                          .first,
                      trailing: _chev(p),
                      onTap: _pickLanguage),
                ]),
                _GroupLabel('Academic Profile'),
                _Group(children: [
                  _Row(Symbols.school, 'College / University', p.primary,
                      value: (profile?.college ?? '').isNotEmpty
                          ? profile!.college!
                          : 'Set college',
                      trailing: _chev(p),
                      onTap: _editProfile),
                  _Row(Symbols.architecture, 'Program & Branch', p.primary2,
                      value: (profile?.branch ?? '').isNotEmpty
                          ? profile!.branch!
                          : 'Set program',
                      trailing: _chev(p),
                      onTap: _editProfile),
                  _Row(Symbols.badge, 'Student ID / Roll No', p.coral,
                      value: (profile?.enrollmentId ?? '').isNotEmpty
                          ? profile!.enrollmentId!
                          : 'Set ID / Roll no',
                      trailing: _chev(p),
                      onTap: _editProfile),
                ]),
                const SizedBox(height: 20),

                _GroupLabel('Study'),
                _Group(children: [
                  _Row(Symbols.flag, 'Study goals', p.primary,
                      value: store.allGoals.isEmpty
                          ? 'Create your first'
                          : '${store.allGoals.length} goal'
                              '${store.allGoals.length == 1 ? '' : 's'}',
                      trailing: _chev(p),
                      onTap: _manageGoals),
                  _Row(Symbols.target, 'Active goal', p.primary2,
                      value: goal?.name ?? 'Not set',
                      trailing: _chev(p),
                      onTap: _editGoalName),
                  _Row(Symbols.event, 'Exam date', p.coral,
                      value: _dateLabel(goal?.examDate),
                      trailing: _chev(p),
                      onTap: _editExamDate),
                  _Row(Symbols.speed, 'Pace', p.amber,
                      value: goal?.pace.label ?? '—',
                      trailing: _chev(p),
                      onTap: _editPace),
                  _Row(Symbols.calendar_add_on, 'Add to my calendar', p.green,
                      value: 'Exams & plan',
                      trailing: _chev(p),
                      onTap: _exportCalendar),
                ]),
                const SizedBox(height: 20),

                _GroupLabel('Account'),
                _Group(children: [
                  _Row(Symbols.groups, 'Class', p.primary,
                      value: store.className ?? 'Not joined',
                      trailing: _chev(p),
                      onTap: _pickClass),
                  _Row(Symbols.lock, 'Privacy & security', p.green,
                      trailing: _chev(p),
                      onTap: () => _toast(
                          'Your data is private to your account and protected by row-level security.')),
                  _Row(Symbols.help, 'Help & support', p.coral,
                      trailing: _chev(p),
                      onTap: () => _toast('Reach out at yash@charusat.edu.in')),
                ]),
                const SizedBox(height: 22),

                PillButton('Log out',
                    icon: Symbols.logout,
                    variant: PillVariant.danger,
                    onTap: context.watch<AuthStore>().busy ? null : _logout),
                const SizedBox(height: 12),
                PillButton('Delete account',
                    icon: Symbols.delete_forever,
                    variant: PillVariant.danger,
                    onTap: context.watch<AuthStore>().busy
                        ? null
                        : _deleteAccount),
                const SizedBox(height: 12),
                Center(
                  child: Text('StudyTrail v1.0 · SGP · CSPIT',
                      style: TextStyle(color: p.ink3, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chev(AppPalette p) =>
      Icon(Symbols.chevron_right, color: p.ink3, size: 22);
}

/// Labelled text field used inside the editor sheets.
///
/// A [TextFormField] with an initial value owns its controller and disposes it
/// with itself. The caller used to own one and dispose it as soon as the
/// sheet's future completed — which happens when the sheet *starts* closing,
/// with the field still on screen — and that crashed debug builds with
/// `'_dependents.isEmpty': is not true`.
class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.initialValue,
    required this.label,
    required this.onChanged,
  });

  final String initialValue;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: initialValue,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.words,
        style: TextStyle(color: p.ink, fontSize: 14.5),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: p.ink3, fontSize: 13.5),
          filled: true,
          fillColor: p.card2,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: p.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: p.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: p.primary, width: 1.6),
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: context.p.ink3,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(color: p.line, height: 1, indent: 60, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.color,
      {this.value, required this.trailing, this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final String? value;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            IconTile(icon,
                bg: color.withValues(alpha: 0.14),
                fg: color,
                size: 34,
                radius: 11),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
            ),
            if (value != null) ...[
              Flexible(
                child: Text(value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: p.ink3,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
            ],
            trailing,
          ],
        ),
      ),
    );
  }
}
