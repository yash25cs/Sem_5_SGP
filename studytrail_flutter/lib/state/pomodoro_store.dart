import 'dart:async';

import '../data/local_prefs.dart';
import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Which half of the timer is running.
///
/// Two phases only: a focus block and the break after it. The long break and the
/// rounds-per-cycle bookkeeping are gone — the student switches phase by hand
/// (or lets a finished block hand over), which is what the screen now offers.
enum PomodoroPhase { focus, shortBreak }

/// Backs the Pomodoro screen and the global focus bar. The timer is local (a
/// 1-second `Timer.periodic`); only completed focus blocks are persisted, so a
/// paused or abandoned session never inflates the study log.
///
/// The countdown deliberately lives here rather than in the screen, so leaving
/// the screen doesn't cancel the block — which is what lets `PomodoroOverlay`
/// keep showing it from anywhere in the app.
class PomodoroStore extends AsyncStore {
  PomodoroStore({GamificationRepository? game, GoalRepository? goals})
      : _game = game ?? const GamificationRepository(),
        _goals = goals ?? const GoalRepository();

  final GamificationRepository _game;
  final GoalRepository _goals;

  Timer? _ticker;

  TimerPreset _preset = TimerPreset.fallback;
  List<TimerPreset> _customPresets = const [];
  bool _presetsLoaded = false;

  PomodoroPhase _phase = PomodoroPhase.focus;
  int _secondsLeft = TimerPreset.fallback.focusMinutes * 60;

  /// Length the *current* phase started with.
  ///
  /// [progress] divides by this rather than by the live preset, so switching
  /// preset mid-block can't make the ring jump — it used to compare the old
  /// seconds-left against the new duration.
  int _phaseTotalSeconds = TimerPreset.fallback.focusMinutes * 60;

  bool _running = false;
  String? _subjectId;
  bool _onTimerScreen = false;

  int _completionTick = 0;
  PomodoroPhase? _lastCompletedPhase;
  int? _lastCompletedMinutes;
  PomodoroPhase? _startedPhase;

  List<Subject> _subjects = const [];
  int _sessionsToday = 0;
  int _minutesToday = 0;

  TimerPreset get preset => _preset;

  /// Built-ins first, then whatever the student saved.
  List<TimerPreset> get savedPresets =>
      [...TimerPreset.builtIns, ..._customPresets];

  int get focusMinutes => _preset.focusMinutes;
  int get breakMinutes => _preset.breakMinutes;

  PomodoroPhase get phase => _phase;
  int get secondsLeft => _secondsLeft;
  bool get running => _running;
  bool get isFocus => _phase == PomodoroPhase.focus;

  /// Changing durations is only allowed between blocks. Doing it mid-run was the
  /// reported bug: the dial no longer described the block actually being timed.
  bool get canConfigure => !_running;

  /// True once a block has been started and not yet finished or reset — what the
  /// global bar keys off. A freshly loaded dial that nobody touched isn't
  /// "in progress" and shouldn't follow the student around the app.
  bool get inProgress => _running || _secondsLeft < _phaseTotalSeconds;

  String? get subjectId => _subjectId;

  /// Subjects of the active goal, for the "what are you focusing on?" chip.
  List<Subject> get subjects => _subjects;

  Subject? get selectedSubject =>
      _subjects.where((s) => s.id == _subjectId).firstOrNull;

  /// Set by the Pomodoro screen while it's on top, so the global bar doesn't
  /// duplicate the dial the student is already looking at.
  bool get onTimerScreen => _onTimerScreen;

  /// Bumped once per phase that runs to completion.
  ///
  /// A counter rather than a stream or a callback: `ChangeNotifier` has no
  /// one-shot channel, and a listener that rebuilds late still sees the new
  /// value, so the completion popup can't be missed just because the overlay
  /// happened to be busy.
  int get completionTick => _completionTick;
  PomodoroPhase? get lastCompletedPhase => _lastCompletedPhase;

  /// Minutes logged by the phase that just completed — null for breaks, which
  /// aren't logged.
  int? get lastCompletedMinutes => _lastCompletedMinutes;

  /// The phase that started as a result, for the "…and X has begun" line.
  PomodoroPhase? get startedPhase => _startedPhase;

  /// Blocks logged today, across app runs — the footer tiles.
  int get sessionsToday => _sessionsToday;

  /// "1h 15m" / "50m" for the focused-time tile.
  String get minutesTodayLabel {
    final h = _minutesToday ~/ 60;
    final m = _minutesToday % 60;
    return h == 0 ? '${m}m' : (m == 0 ? '${h}h' : '${h}h ${m}m');
  }

  /// "24:05" for the big dial.
  String get display {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 0–1 elapsed fraction, for the ring around the dial.
  double get progress {
    if (_phaseTotalSeconds == 0) return 0;
    return (_phaseTotalSeconds - _secondsLeft) / _phaseTotalSeconds;
  }

  String get phaseLabel => labelFor(_phase);

  static String labelFor(PomodoroPhase phase) => switch (phase) {
        PomodoroPhase.focus => 'Focus',
        PomodoroPhase.shortBreak => 'Short break',
      };

  /// Minutes the given phase runs for under the active preset.
  int minutesFor(PomodoroPhase phase) => switch (phase) {
        PomodoroPhase.focus => _preset.focusMinutes,
        PomodoroPhase.shortBreak => _preset.breakMinutes,
      };

  /// What a finished block hands over to, for the caption under the dial.
  String get nextUpLabel => isFocus ? 'Short break next' : 'Focus next';

  /// Today's totals, the subject list, and the saved presets. Safe to call on
  /// every screen open — it never touches a running timer.
  Future<void> load() => runLoad(() async {
        // Presets are device-local, so they load even when the network is down.
        // Done before the awaits below for that reason.
        await _loadPresets();

        final sessions = await _game.getStudySessions();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        var count = 0, minutes = 0;
        for (final s in sessions) {
          final d = s.sessionDate;
          if (DateTime(d.year, d.month, d.day) != today) continue;
          count += s.sessionsCount ?? 1;
          minutes += s.focusedMin ?? s.lengthMin ?? 0;
        }
        _sessionsToday = count;
        _minutesToday = minutes;

        final goal = await _goals.getActiveGoal();
        _subjects =
            goal == null ? const [] : await _goals.getSubjects(goal.id);
      });

  /// Restores the saved presets and the last-used choice. Only applies that
  /// choice to an untouched, idle dial, so reopening the screen mid-block can't
  /// reset the block being timed.
  Future<void> _loadPresets() async {
    if (_presetsLoaded) return;
    _presetsLoaded = true;

    _customPresets = await LocalPrefs.getTimerPresets();
    final activeId = await LocalPrefs.getActiveTimerId();
    if (activeId == null || _running || inProgress) return;

    final match = savedPresets.where((p) => p.id == activeId).firstOrNull;
    if (match != null) _adoptPreset(match);
  }

  void selectSubject(String? subjectId) {
    _subjectId = subjectId;
    notifyListeners();
  }

  void setOnTimerScreen(bool value) {
    if (_onTimerScreen == value) return;
    _onTimerScreen = value;
    notifyListeners();
  }

  /// Switches the timer to [preset] and remembers the choice.
  ///
  /// Rejected while the timer runs — see [canConfigure]. The dial resets to the
  /// new focus length, which is the point: the student is choosing how the next
  /// block should look.
  Future<bool> applyPreset(TimerPreset preset) async {
    if (!canConfigure) return false;
    _adoptPreset(preset.sanitized());
    notifyListeners();
    await LocalPrefs.setActiveTimerId(_preset.id);
    return true;
  }

  /// Saves a preset of the student's own and switches to it.
  ///
  /// Editing an existing custom preset means passing its id back; anything else
  /// is appended.
  Future<bool> saveCustomPreset(TimerPreset preset) async {
    final clean = preset.sanitized();
    final index = _customPresets.indexWhere((p) => p.id == clean.id);
    _customPresets = [
      if (index < 0) ...[..._customPresets, clean],
      if (index >= 0)
        for (final p in _customPresets) p.id == clean.id ? clean : p,
    ];
    await LocalPrefs.setTimerPresets(_customPresets);
    // Saving while a block runs keeps the preset but leaves the block alone.
    if (!canConfigure) {
      notifyListeners();
      return false;
    }
    return applyPreset(clean);
  }

  Future<void> deleteCustomPreset(String id) async {
    _customPresets = _customPresets.where((p) => p.id != id).toList();
    await LocalPrefs.setTimerPresets(_customPresets);
    // Deleting the preset in use falls back to the default rather than leaving
    // the dial describing something that no longer exists.
    if (_preset.id == id && canConfigure) {
      _adoptPreset(TimerPreset.fallback);
      await LocalPrefs.setActiveTimerId(_preset.id);
    }
    notifyListeners();
  }

  /// Adopts [preset] and rebuilds the dial from it. Callers notify.
  void _adoptPreset(TimerPreset preset) {
    _preset = preset;
    _phase = PomodoroPhase.focus;
    _setPhaseDuration();
  }

  void start() {
    if (_running) return;
    _running = true;
    _startTicker();
    notifyListeners();
  }

  void pause() {
    if (!_running) return;
    _running = false;
    _ticker?.cancel();
    notifyListeners();
  }

  void toggle() => _running ? pause() : start();

  /// Restarts the block on screen from its full length, without logging it.
  void reset() {
    _ticker?.cancel();
    _running = false;
    _setPhaseDuration();
    notifyListeners();
  }

  /// Ends the session: back to an untouched focus block, nothing logged.
  ///
  /// Distinct from [reset], which keeps the current phase — stopping during a
  /// break shouldn't leave the student on a break.
  void stop() {
    _ticker?.cancel();
    _running = false;
    _phase = PomodoroPhase.focus;
    _setPhaseDuration();
    notifyListeners();
  }

  /// Switches between focus and break — what the toggle and the swipe on the
  /// dial both call.
  ///
  /// Returns false, and changes nothing, while the timer runs: swapping the
  /// phase mid-block would leave the dial describing something other than what
  /// is being timed. The caller says so rather than silently ignoring the
  /// gesture. Switching discards the elapsed part of a paused block, which is
  /// the point — it's a different block now.
  bool switchTo(PomodoroPhase phase) {
    if (_phase == phase) return true;
    if (_running) return false;
    _phase = phase;
    _setPhaseDuration();
    notifyListeners();
    return true;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_secondsLeft > 0) _secondsLeft--;
    if (_secondsLeft > 0) {
      notifyListeners();
      return;
    }
    // Hit zero. Record what just finished for the completion popup, then chain
    // straight into the next block — leaving it paused was the reported
    // "changing to next session timer is not working" bug.
    final finishedFocus = isFocus;

    _lastCompletedPhase = _phase;
    _lastCompletedMinutes = finishedFocus ? _preset.focusMinutes : null;

    _phase = finishedFocus ? PomodoroPhase.shortBreak : PomodoroPhase.focus;
    _setPhaseDuration();
    _running = true;
    _startTicker();

    _startedPhase = _phase;
    _completionTick++;
    notifyListeners();

    if (finishedFocus) {
      // Fire-and-forget: the timer shouldn't stall on a network write.
      unawaited(_logSession(_preset.focusMinutes));
    }
  }

  /// Loads the current phase's length and freezes it as the denominator for
  /// [progress].
  void _setPhaseDuration() {
    _phaseTotalSeconds = minutesFor(_phase) * 60;
    _secondsLeft = _phaseTotalSeconds;
  }

  /// One completed focus block. `recordSession` derives the XP from the minutes
  /// server-side, so the store never names an amount.
  Future<void> _logSession(int minutes) async {
    final ok = await runMutation(() async {
      await _game.recordSession(
        subjectId: _subjectId,
        lengthMin: minutes,
        focusedMin: minutes,
      );
    });
    // Keep today's tiles honest without a refetch. Only on a successful write,
    // so the count can't claim a block the server never got.
    if (!ok) return;
    _sessionsToday++;
    _minutesToday += minutes;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
