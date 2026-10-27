import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../screens/pomodoro_screen.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';

/// Wraps the app's [Navigator] with the focus-session bar and the completion
/// popup, so a running timer stays visible and self-announcing no matter which
/// screen the student walks to.
///
/// Mounted from `MaterialApp.builder`, which puts it *above* the navigator —
/// that's what makes it cover pushed routes (Quiz, Achievements, Analytics) and
/// not just the shell's tabs. Two consequences that shape the code below:
///
/// * the bar is laid out in a [Column] above the page rather than stacked over
///   it, so it pushes headers down instead of hiding them;
/// * the completion popup is an in-tree [Stack] child, not a `showDialog` route,
///   because `Navigator.of` from here reaches past the app's own navigator;
/// * nothing here may need an [Overlay] — no tooltips, no menus. The only one
///   is the navigator's, below this widget, and a tooltip in the bar is what
///   put "No Overlay widget found" on screen.
///
/// It also keeps a locked focus block (see [PomodoroStore.locked]) on its own
/// screen: whenever one is running and no timer screen is mounted — a break
/// handing over to focus while the student is elsewhere, or a `popUntil` that
/// skipped the screen's back guard — the screen is pushed again through
/// [navigatorKey].
class PomodoroOverlay extends StatefulWidget {
  const PomodoroOverlay({super.key, required this.child, this.navigatorKey});

  final Widget child;

  /// The app's navigator, for opening the timer screen from up here.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<PomodoroOverlay> createState() => _PomodoroOverlayState();
}

class _PomodoroOverlayState extends State<PomodoroOverlay> {
  /// Auto-dismiss window for the completion popup — long enough to notice
  /// after stepping away, short enough not to sit over the app.
  static const int _autoCloseSeconds = 30;

  /// Last tick this overlay has already shown a popup for, so a rebuild for any
  /// other reason (a tab change, a theme switch) doesn't reopen it.
  int _seenTick = 0;

  _Completion? _completion;
  Timer? _countdown;
  int _secondsToClose = _autoCloseSeconds;

  /// A timer screen has been pushed and hasn't mounted yet, so the rebuild
  /// every tick brings doesn't push a second one.
  bool _openingTimer = false;

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  void _onTick(PomodoroStore store) {
    if (store.completionTick == _seenTick) return;
    _seenTick = store.completionTick;

    final finished = store.lastCompletedPhase;
    if (finished == null) return;

    _countdown?.cancel();
    setState(() {
      _completion = _Completion(
        finished: finished,
        started: store.startedPhase,
        loggedMinutes: store.lastCompletedMinutes,
      );
      _secondsToClose = _autoCloseSeconds;
    });

    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsToClose <= 1) {
        timer.cancel();
        _dismiss();
        return;
      }
      setState(() => _secondsToClose--);
    });
  }

  void _dismiss() {
    _countdown?.cancel();
    if (!mounted) return;
    setState(() => _completion = null);
  }

  void _openTimer() {
    final navigator = widget.navigatorKey?.currentState;
    if (navigator == null || _openingTimer) return;
    _openingTimer = true;
    navigator.push(MaterialPageRoute(
        builder: (_) => PomodoroScreen(onBack: navigator.pop)));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PomodoroStore>();

    // Reading during build; the actual state change is deferred to after the
    // frame so this build stays side-effect free.
    if (store.completionTick != _seenTick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onTick(store);
      });
    }

    if (store.onTimerScreen) {
      _openingTimer = false;
    } else if (store.locked && !_openingTimer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && store.locked && !store.onTimerScreen) _openTimer();
      });
    }

    // The Pomodoro screen already shows the dial full size; duplicating it in a
    // bar above would just be noise.
    final showBar = store.inProgress && !store.onTimerScreen;
    final completion = _completion;

    return Stack(
      children: [
        Column(
          children: [
            if (showBar) _TimerBanner(onOpen: _openTimer),
            Expanded(
              // The bar has already paid the status-bar inset, so the page's own
              // `TopInset` must collapse or the content sits too low.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: showBar,
                child: widget.child,
              ),
            ),
          ],
        ),
        if (completion != null)
          _CompletionPopup(
            completion: completion,
            secondsToClose: _secondsToClose,
            onDismiss: _dismiss,
          ),
      ],
    );
  }
}

/// What just finished, and what it handed off to.
class _Completion {
  const _Completion({
    required this.finished,
    required this.started,
    required this.loggedMinutes,
  });

  final PomodoroPhase finished;
  final PomodoroPhase? started;

  /// Null for breaks, which aren't logged.
  final int? loggedMinutes;
}

/// The slim bar at the top of every page while a block is in progress. Tapping
/// it opens the timer screen.
class _TimerBanner extends StatelessWidget {
  const _TimerBanner({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<PomodoroStore>();

    // Same accent rule as the dial: indigo on focus, coral on breaks.
    final accent = store.isFocus ? p.primary : p.coral;
    final subject = store.selectedSubject;

    return Material(
      color: p.card,
      child: InkWell(
        onTap: onOpen,
        child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.line)),
        ),
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
              ),
              const SizedBox(width: 10),
              Text(store.display,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    subject == null
                        ? store.phaseLabel
                        : '${store.phaseLabel} · ${subject.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink3,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
              // No `tooltip:` — a tooltip needs an Overlay, and this bar sits
              // above the navigator's. The label goes to screen readers via
              // the icon instead.
              IconButton(
                onPressed: store.toggle,
                visualDensity: VisualDensity.compact,
                icon: Icon(store.running ? Symbols.pause : Symbols.play_arrow,
                    color: accent,
                    size: 24,
                    fill: 1,
                    semanticLabel: store.running ? 'Pause' : 'Resume'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Scrim + card announcing a completed phase. Self-closes on a countdown so it
/// can't be left sitting over the app.
class _CompletionPopup extends StatefulWidget {
  const _CompletionPopup({
    required this.completion,
    required this.secondsToClose,
    required this.onDismiss,
  });

  final _Completion completion;
  final int secondsToClose;
  final VoidCallback onDismiss;

  @override
  State<_CompletionPopup> createState() => _CompletionPopupState();
}

class _CompletionPopupState extends State<_CompletionPopup> {
  /// Drives the entry animation. Flipped after the first frame so the implicit
  /// animations have a value to animate *from*.
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = widget.completion;
    final focusDone = c.finished == PomodoroPhase.focus;
    final accent = focusDone ? p.primary : p.coral;

    final headline = focusDone ? 'Focus block done' : 'Break over';
    final detail = switch ((c.loggedMinutes, c.started)) {
      (final int minutes, final PomodoroPhase started) =>
        '$minutes min logged · ${PomodoroStore.labelFor(started)} has started.',
      (final int minutes, null) => '$minutes min logged.',
      (null, final PomodoroPhase started) =>
        '${PomodoroStore.labelFor(started)} has started.',
      _ => 'Ready for the next block.',
    };

    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: AnimatedScale(
              scale: _shown ? 1 : 0.88,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutBack,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Material(
                  color: p.card,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.14),
                          ),
                          child: Icon(
                              focusDone
                                  ? Symbols.check_circle
                                  : Symbols.local_cafe,
                              color: accent,
                              size: 36,
                              fill: 1),
                        ),
                        const SizedBox(height: 16),
                        Text(headline,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(detail,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: p.ink2, fontSize: 14, height: 1.45)),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: 180,
                          child: FilledButton(
                            onPressed: widget.onDismiss,
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: const StadiumBorder(),
                            ),
                            child: const Text('OK',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text('Closing in ${widget.secondsToClose}s',
                            style: TextStyle(color: p.ink3, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
