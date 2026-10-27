import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../theme/subject_style.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';

/// Two-mode focus timer: a **Focus** block and a **Short break**, swapped by
/// swiping the dial (or tapping the toggle above it), with stop / reset / change
/// under the play button.
///
/// The countdown itself lives in [PomodoroStore] rather than this widget, so
/// leaving the screen mid-block doesn't cancel the session.
///
/// While a focus block is locked ([PomodoroStore.locked]) the screen can't be
/// left: system and predictive back and the back button all open the end-early
/// sheet instead, which only ends the block once the student ticks that it
/// won't count.
///
/// The body scrolls. Every earlier version laid the dial, the controls and the
/// footer tiles out with `Spacer`s in a fixed-height `Column`, which is what put
/// "BOTTOM OVERFLOWED BY 2.0 PIXELS" across the middle of the screen on a short
/// display; a scroll view can't overflow.
class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  /// Held in a field because [dispose] runs after the element is detached, when
  /// `context.read` is no longer legal.
  PomodoroStore? _store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _store = context.read<PomodoroStore>()
        ..load()
        // Suppresses the global focus bar while the full dial is on screen.
        ..setOnTimerScreen(true);
    });
  }

  @override
  void dispose() {
    final store = _store;
    if (store != null) {
      // Deferred: notifying listeners during this frame's teardown would mark
      // the overlay dirty while the tree is being unmounted.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => store.setOnTimerScreen(false));
    }
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Back while a block is locked opens the end-early sheet, and leaves only
  /// if the student goes through with it.
  void _onBack() {
    if (context.read<PomodoroStore>().locked) {
      _confirmEndEarly(leave: true);
      return;
    }
    _leave();
  }

  void _leave() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// The terminate option. "End session" stays disabled until the student
  /// ticks that the block won't count, so it can't be ended by a stray tap.
  Future<void> _confirmEndEarly({required bool leave}) async {
    final store = context.read<PomodoroStore>();
    final p = context.p;

    final end = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const _EndEarlySheet(),
    );

    // The block may have finished on its own while the sheet was up; it
    // counted, and there's nothing left to end.
    if (end != true || !mounted || !store.locked) return;
    store.endEarly();
    _toast('Focus block ended early — not counted.');
    if (leave) _leave();
  }

  /// Lets the student tag the block with a subject, so the logged session
  /// shows up under the right subject in Progress.
  Future<void> _pickSubject() async {
    final store = context.read<PomodoroStore>();
    final p = context.p;

    if (store.subjects.isEmpty) {
      _toast('Add subjects to your goal to tag focus sessions.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text('Focus on',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              ListTile(
                leading: Icon(Symbols.blur_on, color: p.ink3),
                title: Text('No subject',
                    style: TextStyle(color: p.ink2, fontSize: 14.5)),
                trailing: store.subjectId == null
                    ? Icon(Symbols.check, color: p.primary)
                    : null,
                onTap: () {
                  store.selectSubject(null);
                  Navigator.of(sheetContext).pop();
                },
              ),
              for (final s in store.subjects)
                Builder(builder: (_) {
                  final style = SubjectStyle.of(context, name: s.name);
                  return ListTile(
                    leading: Icon(style.icon, color: style.color),
                    title: Text(s.name,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600)),
                    trailing: store.subjectId == s.id
                        ? Icon(Symbols.check, color: p.primary)
                        : null,
                    onTap: () {
                      store.selectSubject(s.id);
                      Navigator.of(sheetContext).pop();
                    },
                  );
                }),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Focus ↔ break, from the toggle or the swipe.
  void _switchTo(PomodoroPhase phase) {
    final store = context.read<PomodoroStore>();
    if (store.phase == phase) return;
    if (!store.switchTo(phase)) {
      _toast(store.locked
          ? 'Finish or end this focus block to switch modes.'
          : 'Pause the timer to switch modes.');
    }
  }

  /// A flick across the dial means "the other mode". Focus sits on the left of
  /// the toggle and the break on the right, so the directions match it.
  void _onDialSwipe(DragEndDetails details) {
    final vx = details.velocity.pixelsPerSecond.dx;
    // Ignore a slow drag: it's usually a stray touch while scrolling.
    if (vx.abs() < 80) return;
    _switchTo(vx < 0 ? PomodoroPhase.shortBreak : PomodoroPhase.focus);
  }

  /// The preset list — the **Change** button.
  ///
  /// Only reachable between blocks: changing the length of a block already
  /// running left the dial describing something other than what was being timed.
  Future<void> _configure() async {
    final store = context.read<PomodoroStore>();
    final p = context.p;

    if (!store.canConfigure) {
      _toast(store.locked
          ? 'Finish or end this focus block to change its length.'
          : 'Pause the timer to change its length.');
      return;
    }

    final choice = await showModalBottomSheet<_PresetChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text('Session length',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text('How long a focus block and its break run for.',
                    style: TextStyle(color: p.ink3, fontSize: 12.5)),
              ),
              for (final preset in store.savedPresets)
                ListTile(
                  leading: Icon(
                      preset.isBuiltIn ? Symbols.timer : Symbols.tune,
                      color: p.primary),
                  title: Text(preset.label,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      preset.description == null
                          ? preset.summary
                          : '${preset.summary} · ${preset.description}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink3, fontSize: 12)),
                  trailing: store.preset.id == preset.id
                      ? Icon(Symbols.check, color: p.primary)
                      : null,
                  onTap: () => Navigator.of(sheetContext)
                      .pop((action: _PresetAction.apply, preset: preset)),
                  // Long-press to delete keeps the row a single tap target for
                  // the common case; built-ins ship with the app and stay.
                  onLongPress: preset.isBuiltIn
                      ? null
                      : () => Navigator.of(sheetContext)
                          .pop((action: _PresetAction.delete, preset: preset)),
                ),
              ListTile(
                leading: Icon(Symbols.add, color: p.coral),
                title: Text('Custom timer…',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
                subtitle: Text('Your own durations, with an optional note',
                    style: TextStyle(color: p.ink3, fontSize: 12)),
                onTap: () => Navigator.of(sheetContext)
                    .pop((action: _PresetAction.custom, preset: null)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    switch (choice) {
      case (action: _PresetAction.custom, preset: _):
        await _createCustomPreset();
      case (action: _PresetAction.delete, preset: final picked?):
        await store.deleteCustomPreset(picked.id);
        _toast('Timer deleted');
      case (action: _PresetAction.apply, preset: final picked?):
        final applied = await store.applyPreset(picked);
        if (!applied) _toast('Pause the timer to change its length.');
      // A delete or apply with no preset can't be produced by the sheet above.
      case _:
        break;
    }
  }

  /// The custom-timer form. The description is genuinely optional — no
  /// validator — so a student who just wants 40/8 isn't made to name it.
  Future<void> _createCustomPreset() async {
    final store = context.read<PomodoroStore>();
    final p = context.p;

    final preset = await showModalBottomSheet<TimerPreset>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _CustomTimerSheet(initial: store.preset),
    );

    if (preset == null || !mounted) return;

    final applied = await store.saveCustomPreset(preset);
    _toast(applied
        ? 'Timer saved'
        : 'Timer saved — it applies from the next block.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<PomodoroStore>();

    final subject = store.selectedSubject;
    final subjectStyle =
        subject == null ? null : SubjectStyle.of(context, name: subject.name);

    // Breaks get the coral accent so a glance at the ring says which mode is
    // running.
    final accent = store.isFocus ? p.primary : p.coral;

    // Big enough to read across a room, but never wider than the screen.
    final dial =
        math.min(260.0, MediaQuery.sizeOf(context).width - 96).clamp(180.0, 260.0);

    // Back is refused while the block is locked; the attempt opens the
    // end-early sheet, which pops the screen itself if the block is ended.
    return PopScope(
      canPop: !store.locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmEndEarly(leave: true);
      },
      child: Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 6),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back, onTap: _onBack),
                const SizedBox(width: 8),
                Text('Focus session',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 28),
              child: Column(
                children: [
                  // subject chip
                  SoftChip(subject?.name ?? 'Pick a subject',
                      icon: subjectStyle?.icon ?? Symbols.add,
                      tone:
                          subject == null ? ChipTone.neutral : ChipTone.primary,
                      onTap: _pickSubject),
                  const SizedBox(height: 18),

                  // mode toggle — the same switch the swipe performs
                  _PhaseToggle(
                    phase: store.phase,
                    accent: accent,
                    focusMinutes: store.focusMinutes,
                    breakMinutes: store.breakMinutes,
                    onPick: _switchTo,
                  ),
                  const SizedBox(height: 22),

                  // timer ring — swipe across it to change mode
                  GestureDetector(
                    onHorizontalDragEnd: _onDialSwipe,
                    child: SizedBox(
                      width: dial,
                      height: dial,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: dial,
                            height: dial,
                            child: TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOut,
                              tween: Tween(begin: 0, end: store.progress),
                              builder: (context, value, _) =>
                                  CircularProgressIndicator(
                                value: value,
                                strokeWidth: 14,
                                strokeCap: StrokeCap.round,
                                backgroundColor: p.card3,
                                valueColor: AlwaysStoppedAnimation(accent),
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(store.display,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 56,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ])),
                              const SizedBox(height: 4),
                              Text(store.phaseLabel,
                                  style: TextStyle(
                                      color: p.ink3,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Symbols.swipe, color: p.ink3, size: 16),
                      const SizedBox(width: 6),
                      Text('Swipe the dial to switch · ${store.nextUpLabel}',
                          style: TextStyle(color: p.ink3, fontSize: 12.5)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                      store.preset.description == null
                          ? '${store.preset.label} · ${store.preset.summary}'
                          : '${store.preset.label} · ${store.preset.description}',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink3, fontSize: 11.5)),
                  const SizedBox(height: 22),

                  // primary control
                  _CircleControl(
                      store.running ? Symbols.pause : Symbols.play_arrow,
                      accent,
                      p.onPrimary,
                      size: 82,
                      glow: true,
                      onTap: store.toggle),
                  const SizedBox(height: 18),

                  // stop / reset / change
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // A locked focus block ends only through the confirm
                      // sheet; a break still stops straight away.
                      _ControlButton(
                        icon: Symbols.stop,
                        label: store.locked ? 'End' : 'Stop',
                        // Nothing to stop on an untouched focus dial.
                        onTap: store.locked
                            ? () => _confirmEndEarly(leave: false)
                            : store.inProgress
                                ? store.stop
                                : null,
                      ),
                      const SizedBox(width: 10),
                      _ControlButton(
                          icon: Symbols.refresh,
                          label: 'Reset',
                          // Restarting a locked block would end it unconfirmed.
                          onTap: store.locked
                              ? () => _toast(
                                  'Use End to stop this focus block early.')
                              : store.reset,
                          dimmed: store.locked),
                      const SizedBox(width: 10),
                      _ControlButton(
                          icon: Symbols.tune,
                          label: 'Change',
                          onTap: _configure,
                          // Greyed rather than hidden, so the button doesn't
                          // vanish mid-session — tapping it explains why.
                          dimmed: !store.canConfigure),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                          child: _MiniInfo(
                              Symbols.timer,
                              '${store.sessionsToday}',
                              'Sessions today',
                              p.primary)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _MiniInfo(Symbols.hourglass_bottom,
                              store.minutesTodayLabel, 'Focused', p.coral)),
                    ],
                  ),
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

/// The end-early confirmation: what ending costs, a tick to confirm it, and the
/// button that only works once ticked. Pops true to end the block.
class _EndEarlySheet extends StatefulWidget {
  const _EndEarlySheet();

  @override
  State<_EndEarlySheet> createState() => _EndEarlySheetState();
}

class _EndEarlySheetState extends State<_EndEarlySheet> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('End this focus block?',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                "A block ended early isn't counted: no XP, no focused "
                'minutes, and nothing towards your streak.',
                style: TextStyle(color: p.ink2, fontSize: 13.5, height: 1.45)),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _understood,
              onChanged: (v) => setState(() => _understood = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: p.error,
              title: Text("I understand this session won't be counted",
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            // Faded until ticked: the pill itself looks the same either way.
            AnimatedOpacity(
              opacity: _understood ? 1 : 0.45,
              duration: const Duration(milliseconds: 150),
              child: PillButton('End session',
                  icon: Symbols.stop,
                  variant: PillVariant.danger,
                  onTap: _understood
                      ? () => Navigator.of(context).pop(true)
                      : null),
            ),
            const SizedBox(height: 8),
            PillButton('Keep focusing',
                variant: PillVariant.outline,
                onTap: () => Navigator.of(context).pop(false)),
          ],
        ),
      ),
    );
  }
}

/// What the preset sheet came back with. A record rather than the sentinel
/// presets this used to pop: "delete" and "custom" aren't timers, and dressing
/// them up as ones meant every caller had to know the fake ids.
enum _PresetAction { apply, delete, custom }

typedef _PresetChoice = ({_PresetAction action, TimerPreset? preset});

/// Focus | Short break, with each side's length under its name.
class _PhaseToggle extends StatelessWidget {
  const _PhaseToggle({
    required this.phase,
    required this.accent,
    required this.focusMinutes,
    required this.breakMinutes,
    required this.onPick,
  });

  final PomodoroPhase phase;
  final Color accent;
  final int focusMinutes, breakMinutes;
  final ValueChanged<PomodoroPhase> onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          for (final option in PomodoroPhase.values)
            Expanded(
              child: _PhaseTab(
                label: PomodoroStore.labelFor(option),
                minutes: option == PomodoroPhase.focus
                    ? focusMinutes
                    : breakMinutes,
                selected: option == phase,
                accent: accent,
                onTap: () => onPick(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhaseTab extends StatelessWidget {
  const _PhaseTab({
    required this.label,
    required this.minutes,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final int minutes;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? p.onPrimary : p.ink2,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800)),
            Text('$minutes min',
                style: TextStyle(
                    color: selected
                        ? p.onPrimary.withValues(alpha: 0.85)
                        : p.ink3,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// The custom-timer form, as a widget so its controllers are disposed by the
/// element that uses them.
///
/// `showModalBottomSheet` returns as soon as the route pops — while the sheet is
/// still mounted for its exit animation — so controllers created by the caller
/// and disposed after the `await` were being used after disposal, which took the
/// screen down with a red error page.
class _CustomTimerSheet extends StatefulWidget {
  const _CustomTimerSheet({required this.initial});

  /// Prefills the durations from the timer currently in use.
  final TimerPreset initial;

  @override
  State<_CustomTimerSheet> createState() => _CustomTimerSheetState();
}

class _CustomTimerSheetState extends State<_CustomTimerSheet> {
  late final TextEditingController _label;
  late final TextEditingController _note;
  late final TextEditingController _focus;
  late final TextEditingController _break;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController();
    _note = TextEditingController();
    _focus = TextEditingController(text: '${widget.initial.focusMinutes}');
    _break = TextEditingController(text: '${widget.initial.breakMinutes}');
  }

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    _focus.dispose();
    _break.dispose();
    super.dispose();
  }

  /// Builds the preset here, inside the sheet, so nothing reads a controller
  /// after the route is gone. `sanitized()` in the store clamps the numbers, so
  /// a blank or nonsense field can't produce an unrunnable timer.
  void _save() {
    final label = _label.text.trim();
    final note = _note.text.trim();
    Navigator.of(context).pop(TimerPreset(
      // A fresh id each time, so saving twice gives two presets rather than
      // silently overwriting the first.
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      label: label.isEmpty ? 'My timer' : label,
      description: note.isEmpty ? null : note,
      focusMinutes: int.tryParse(_focus.text) ?? widget.initial.focusMinutes,
      breakMinutes: int.tryParse(_break.text) ?? widget.initial.breakMinutes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Custom timer',
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  'Minutes between ${TimerPreset.minMinutes} and '
                  '${TimerPreset.maxMinutes}.',
                  style: TextStyle(color: p.ink3, fontSize: 12.5)),
              const SizedBox(height: 14),
              _TimerField(controller: _label, label: 'Name'),
              _TimerField(
                  controller: _note,
                  label: 'Description (optional)',
                  maxLines: 2),
              Row(
                children: [
                  Expanded(
                      child: _TimerField(
                          controller: _focus, label: 'Focus', numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _TimerField(
                          controller: _break, label: 'Break', numeric: true)),
                ],
              ),
              const SizedBox(height: 8),
              PillButton('Save timer', onTap: _save),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labelled field for the custom-timer form. Numeric fields get the number
/// keyboard; the name and description are plain text.
class _TimerField extends StatelessWidget {
  const _TimerField({
    required this.controller,
    required this.label,
    this.numeric = false,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool numeric;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: p.line),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        textCapitalization:
            numeric ? TextCapitalization.none : TextCapitalization.sentences,
        style: TextStyle(color: p.ink, fontSize: 14.5),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: p.ink3, fontSize: 13.5),
          filled: true,
          fillColor: p.card2,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: p.primary, width: 1.6),
          ),
        ),
      ),
    );
  }
}

class _CircleControl extends StatelessWidget {
  const _CircleControl(this.icon, this.bg, this.fg,
      {required this.size, this.glow = false, this.onTap});
  final IconData icon;
  final Color bg, fg;
  final double size;
  final bool glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          boxShadow: glow ? p.glow : p.shadowSm,
          border: glow ? null : Border.all(color: p.line),
        ),
        child: Icon(icon, color: fg, size: size * 0.42, fill: 1),
      ),
    );
  }
}

/// Icon-over-label pill: the stop / reset / change row under the play button.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.dimmed = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Reads as unavailable but stays tappable, so the tap can explain itself.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final faded = dimmed || onTap == null;
    final fg = faded ? p.ink3.withValues(alpha: 0.55) : p.ink2;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 88,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.line),
          boxShadow: p.shadowSm,
        ),
        child: Column(
          children: [
            Icon(icon, color: fg, size: 22, fill: 1),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo(this.icon, this.value, this.label, this.color);
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
          Icon(icon, color: color, size: 24),
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
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink3, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
