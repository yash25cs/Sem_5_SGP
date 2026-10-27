import 'dart:async';
import 'dart:math' as math;

import '../data/local_prefs.dart';
import '../data/repositories.dart';
import '../models/models.dart';
import '../services/notification_service.dart';
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
  PomodoroStore({
    GamificationRepository? game,
    GoalRepository? goals,
    NotificationService? notifications,
  })  : _game = game ?? const GamificationRepository(),
        _goals = goals ?? const GoalRepository(),
        _notifications = notifications ?? NotificationService();

  final GamificationRepository _game;
  final GoalRepository _goals;
  final NotificationService _notifications;

  /// What the ongoing notice last showed, so a tick that changes nothing the
  /// notice displays doesn't repost it. Null while no notice is up.
  String? _noticeKey;

  /// Notice calls run one after another: a cancel overtaking the show before
  /// it would leave a notice up for a session that already ended.
  Future<void> _noticeQueue = Future.value();
  bool _askedNoticePermission = false;

  /// Set on dispose; a late write finishing afterwards must not repost the
  /// notice.
  bool _closed = false;

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
  /// Timer screens currently mounted. A count, not a flag: a screen popped by
  /// `popUntil` is disposed only after its exit animation, which can be after
  /// a new one has mounted, and a flag would then read "off screen".
  int _timerScreens = 0;

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
  /// Also refused while a focus block is [locked] but paused: applying a
  /// preset resets the dial, which would end the block without the terminate
  /// confirmation.
  bool get canConfigure => !_running && !locked;

  /// True once a block has been started and not yet finished or reset — what the
  /// global bar keys off. A freshly loaded dial that nobody touched isn't
  /// "in progress" and shouldn't follow the student around the app.
  bool get inProgress => _running || _secondsLeft < _phaseTotalSeconds;

  /// A focus block has been started and is neither finished nor ended — paused
  /// counts. While locked the student can't leave the timer screen, the
  /// ongoing notice is up, and the only way out before the block finishes is
  /// [endEarly]: stop, reset, switching mode and changing the preset all
  /// refuse, since each of them would end the block too.
  bool get locked => isFocus && inProgress;

  String? get subjectId => _subjectId;

  /// Subjects of the active goal, for the "what are you focusing on?" chip.
  List<Subject> get subjects => _subjects;

  Subject? get selectedSubject =>
      _subjects.where((s) => s.id == _subjectId).firstOrNull;

  /// Set by the Pomodoro screen while it's on top, so the global bar doesn't
  /// duplicate the dial the student is already looking at.
  bool get onTimerScreen => _timerScreens > 0;

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

  /// Called with true as a timer screen mounts and false as it goes.
  void setOnTimerScreen(bool value) {
    final before = onTimerScreen;
    _timerScreens = value ? _timerScreens + 1 : math.max(0, _timerScreens - 1);
    if (onTimerScreen != before) notifyListeners();
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
  /// Refused while [locked] — see there.
  void reset() {
    if (locked) return;
    _ticker?.cancel();
    _running = false;
    _setPhaseDuration();
    notifyListeners();
  }

  /// Ends the session: back to an untouched focus block, nothing logged.
  ///
  /// Distinct from [reset], which keeps the current phase — stopping during a
  /// break shouldn't leave the student on a break. Refused while [locked]: a
  /// focus block ends early only through [endEarly].
  void stop() {
    if (locked) return;
    _end();
  }

  /// The terminate option, once the student has ticked that the block won't
  /// count. Nothing is logged — no XP, no focused minutes, no streak — since
  /// [_logSession] is only ever reached from [_tick] hitting zero. Ending also
  /// takes the ongoing notice down, through [notifyListeners].
  void endEarly() => _end();

  void _end() {
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
    if (_running || locked) return false;
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

  /// Every state change passes through here, so the ongoing notice follows
  /// the timer without each mutator having to remember it.
  @override
  void notifyListeners() {
    super.notifyListeners();
    _syncNotice();
  }

  /// Shows, updates or clears the ongoing notice to match [locked].
  void _syncNotice() {
    if (_closed) return;
    final subject = selectedSubject?.name;
    final String? key = !locked
        ? null
        // Running: the notice counts itself down, so only a change of what it
        // says reposts it. Paused: it shows the frozen time left.
        : _running
            ? 'run|$subject'
            : 'pause|$_secondsLeft|$subject';
    if (key == _noticeKey) return;
    _noticeKey = key;

    if (key == null) {
      _enqueueNotice(_notifications.cancelFocusSession);
      return;
    }
    final what = subject ?? '${_preset.focusMinutes}-min focus block';
    final title = _running ? 'Focus session running' : 'Focus session paused';
    final body = _running
        ? "$what · ending early won't count"
        : '$what · $display left';
    final endsAt =
        _running ? DateTime.now().add(Duration(seconds: _secondsLeft)) : null;
    final askFirst = !_askedNoticePermission;
    _askedNoticePermission = true;
    _enqueueNotice(() async {
      // Android 13+ hides the notice until notifications are allowed; reminders
      // only ask when the student turns them on, so the first block asks too.
      if (askFirst) {
        try {
          await _notifications.requestPermissions();
        } catch (_) {}
      }
      await _notifications.showFocusSession(
          title: title, body: body, endsAt: endsAt);
    });
  }

  void _enqueueNotice(Future<void> Function() action) {
    _noticeQueue = _noticeQueue.then((_) => action());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _closed = true;
    // A store dropped mid-block (signing out) takes its timer with it.
    if (_noticeKey != null) {
      _noticeKey = null;
      _enqueueNotice(_notifications.cancelFocusSession);
    }
    super.dispose();
  }
}
