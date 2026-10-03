import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// The Study Buddy Room lobby and the room the student is currently in.
///
/// Three realtime paths share one channel per room:
/// * **broadcast `timer`** — the host is the only writer; members mirror it.
///   Payloads carry the seconds left rather than a wall-clock end time, so two
///   phones with different clocks still agree.
/// * **broadcast `room`** — the host announces a close, so members are told
///   instead of sitting in a dead room.
/// * **broadcast `quiz`** — whoever changes a group quiz (proposes, votes,
///   hands in, ends it) pings the room, and everyone re-reads it from the
///   server. The payload is only the quiz id: answers and scores never travel
///   over the channel, and a short poll covers a missed ping.
/// * **postgres_changes on `room_messages`** — chat. The sender picks the row
///   id up front, so its optimistic bubble and the realtime echo de-duplicate.
///
/// Presence says who is on screen right now; the member list says who has
/// joined. A late joiner's presence arriving is the host's cue to re-send the
/// timer, which is how someone who walks in mid-session sees the right time.
class RoomStore extends AsyncStore {
  RoomStore({
    RoomRepository? roomRepo,
    ProfileRepository? profileRepo,
    GamificationRepository? game,
    this.quizPollInterval = const Duration(seconds: 15),
  })  : _roomRepo = roomRepo ?? const RoomRepository(),
        _profileRepo = profileRepo ?? const ProfileRepository(),
        _game = game ?? const GamificationRepository();

  final RoomRepository _roomRepo;
  final ProfileRepository _profileRepo;
  final GamificationRepository _game;

  /// How often an open quiz is re-read in case a ping was missed. Null turns
  /// polling off (tests).
  final Duration? quizPollInterval;

  /// Room sizes the create sheet offers; `create_study_room` allows 2 to 6.
  static const roomSizes = [2, 3, 4, 5, 6];

  /// Lengths the host can pick inside the room (`set_room_timer` allows focus
  /// 5–120 and break 1–60 minutes).
  static const focusChoices = [15, 25, 45, 50];
  static const breakChoices = [5, 10, 15];

  /// Question counts a group quiz can have (`room-quiz` accepts these).
  static const quizSizes = [5, 10, 15];

  /// Seconds per question a speed round can have.
  static const speedSeconds = [10, 20, 30];

  // ── Lobby ──
  List<StudyRoom> _activeRooms = const [];
  List<StudyRoom> get activeRooms => _activeRooms;

  // ── Current room ──
  StudyRoom? _currentRoom;
  StudyRoom? get currentRoom => _currentRoom;
  bool get inRoom => _currentRoom != null;
  bool get isHost =>
      _currentRoom != null && _currentRoom!.createdBy == _me;

  /// Stands in for the signed-in user in tests, where there is no session.
  @visibleForTesting
  String? debugUserId;
  String? get _me => debugUserId ?? currentUserId;
  String? get myUserId => _me;

  List<RoomMember> _members = const [];
  List<RoomMember> get members => _members;

  final Map<String, RoomPresence> _onlinePresence = {};
  List<RoomPresence> get onlinePresence => _onlinePresence.values.toList();
  int get onlineCount => _onlinePresence.length;

  List<RoomMessage> _messages = const [];

  /// People this student blocked. Their messages are hidden in every room;
  /// nobody else's view changes.
  Set<String> _blocked = const {};
  bool isBlocked(String userId) => _blocked.contains(userId);

  /// Oldest first, with sender names filled in from the member list or
  /// presence — neither the table rows nor the realtime payloads carry names.
  List<RoomMessage> get messages => [
        for (final m in _messages)
          if (!_blocked.contains(m.userId))
          m.senderName != null
              ? m
              : m.copyWithSender(
                  name: _nameFor(m.userId),
                  initial: _initialFor(m.userId),
                ),
      ];

  /// Set when the host closes the room while this student is in it.
  String? _closedNotice;
  String? get closedNotice => _closedNotice;

  /// Seconds of the current focus block this device watched running. A late
  /// joiner is credited for what they sat through, not the whole block.
  int _focusSeen = 0;

  /// One-shot message after a completed block was logged; the screen shows it
  /// and calls [clearFocusReward].
  String? _focusReward;
  String? get focusReward => _focusReward;
  void clearFocusReward() => _focusReward = null;

  // ── Shared timer ──
  int _secondsLeft = 25 * 60;
  int _totalSeconds = 25 * 60;
  bool _timerRunning = false;
  String _timerPhase = 'focus'; // 'focus' | 'break'
  Timer? _ticker;

  int get secondsLeft => _secondsLeft;
  int get totalSeconds => _totalSeconds;
  bool get timerRunning => _timerRunning;
  String get timerPhase => _timerPhase;
  bool get isFocus => _timerPhase == 'focus';

  String get timerDisplay {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get timerProgress =>
      _totalSeconds == 0 ? 0 : (_totalSeconds - _secondsLeft) / _totalSeconds;

  // ── Group quiz ──
  RoomQuiz? _quiz;

  /// The room's quiz: being voted on, running, or just finished. Null when
  /// there is none, or the student closed the last one's results.
  RoomQuiz? get quiz => _quiz;

  /// True while the host's quiz is being written (up to a couple of minutes).
  bool _quizWorking = false;
  bool get quizWorking => _quizWorking;

  /// This student's answers so far, question id to option index. Kept here so
  /// leaving the quiz screen and coming back doesn't lose them.
  Map<String, int> _draftPicks = {};
  Map<String, int> get draftPicks => Map.unmodifiable(_draftPicks);

  /// Results the student closed; the server still offers them for an hour.
  final Set<String> _dismissedQuizzes = {};
  Timer? _quizPoll;

  RealtimeChannel? _channel;
  Map<String, dynamic>? _myPresence;

  // ───────────────────────────────────────────────────────────────────────────
  // Lobby
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> loadLobby({String? classId}) => runLoad(() async {
        _activeRooms = await _roomRepo.getActiveRooms(classId: classId);
      });

  /// Creates a room, joins it as host, and enters it.
  Future<StudyRoom?> createRoom({
    required String name,
    String? classId,
    int timerMin = 25,
    int breakMin = 5,
    int maxMembers = 4,
  }) async {
    StudyRoom? created;
    final ok = await runMutation(() async {
      created = await _roomRepo.createRoom(
        name: name,
        classId: classId,
        timerMin: timerMin,
        breakMin: breakMin,
        maxMembers: maxMembers,
      );
    });
    if (!ok || created == null) return null;
    await _enterRoom(created!);
    return created;
  }

  /// Joins by invite code and enters. The lobby's Join button comes through
  /// here too (with the room's own code) — entering without joining would
  /// leave the student unable to read or send chat.
  Future<StudyRoom?> joinByCode(String code) async {
    StudyRoom? joined;
    final ok = await runMutation(() async {
      joined = await _roomRepo.joinRoomByCode(code);
    });
    if (!ok || joined == null) return null;
    await _enterRoom(joined!);
    return joined;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Entering
  // ───────────────────────────────────────────────────────────────────────────

  /// Puts the store in [room] without a channel or network, for tests of the
  /// timer and crediting logic.
  @visibleForTesting
  void debugEnterRoomOffline(StudyRoom room) {
    _currentRoom = room;
    _totalSeconds = room.timerDurationMin * 60;
    _secondsLeft = _totalSeconds;
  }

  /// Puts the store in [room] with its repository but no channel, for tests
  /// of the quiz flow.
  @visibleForTesting
  Future<void> debugEnterRoomWithoutChannel(StudyRoom room) async {
    debugEnterRoomOffline(room);
    await _loadQuiz(room.id);
  }

  Future<void> _enterRoom(StudyRoom room) async {
    if (_currentRoom != null && _currentRoom!.id != room.id) {
      await leaveCurrentRoom();
    }

    _currentRoom = room;
    _closedNotice = null;
    _timerPhase = 'focus';
    _totalSeconds = room.timerDurationMin * 60;
    _secondsLeft = _totalSeconds;
    _timerRunning = false;
    _members = const [];
    _messages = const [];
    _onlinePresence.clear();
    _setQuiz(null);
    notifyListeners();

    // A quiz already going on (or just finished) shows up straight away.
    _loadQuiz(room.id).ignore();

    try {
      final results = await Future.wait([
        _roomRepo.getMembers(room.id),
        _roomRepo.getMessages(room.id),
        // A failed read only means blocked messages show; not worth failing
        // the whole room over.
        _roomRepo.getBlockedIds().catchError((_) => <String>{}),
      ]);
      _members = results[0] as List<RoomMember>;
      final history = results[1] as List<RoomMessage>;
      _blocked = results[2] as Set<String>;
      // Anything the realtime channel delivered while history was loading
      // stays; history fills in behind it.
      final seen = {for (final m in _messages) m.id};
      _messages = [...history.where((m) => !seen.contains(m.id)), ..._messages];
      notifyListeners();
    } catch (e) {
      setError(e);
    }

    await _setupRealtime(room);
  }

  Future<void> _setupRealtime(StudyRoom room) async {
    final channel = _roomRepo.createRoomChannel(room.id);
    _channel = channel;

    channel
      ..onBroadcast(event: 'timer', callback: _onTimerMessage)
      ..onBroadcast(event: 'room', callback: _onRoomMessage)
      ..onBroadcast(event: 'quiz', callback: _onQuizMessage)
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'room_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: room.id,
        ),
        callback: (payload) {
          try {
            _upsertMessage(RoomMessage.fromMap(payload.newRecord));
          } catch (_) {
            // A malformed echo is not worth losing the channel over.
          }
        },
      )
      ..onPresenceSync((_) => _syncPresence(channel))
      ..onPresenceJoin((payload) {
        final newcomers = payload.newPresences
            .map((p) => p.payload['user_id'] as String?)
            .whereType<String>()
            .where((id) => id != _me);
        if (newcomers.isEmpty) return;
        // Someone walked in: they need the current time, and their name.
        if (isHost) _broadcastTimer('sync');
        if (newcomers.any((id) => !_members.any((m) => m.userId == id))) {
          _refreshMembers();
        }
      });

    final profile = await _profileRepo.getMyProfile().catchError((_) => null);
    _myPresence = {
      'user_id': _me ?? '',
      'full_name': (profile?.fullName ?? '').trim().isEmpty
          ? 'Student'
          : profile!.fullName,
      'avatar_initial': profile?.initial ?? 'S',
    };

    // Left (or switched rooms) while the profile was loading.
    if (!identical(_channel, channel)) return;

    channel.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _trackPresence();
      }
    });
  }

  Future<void> _refreshMembers() async {
    final room = _currentRoom;
    if (room == null) return;
    try {
      final fresh = await _roomRepo.getMembers(room.id);
      if (_currentRoom?.id != room.id) return;
      _members = fresh;
      notifyListeners();
    } catch (_) {
      // Names fall back to presence; nothing the student needs to see.
    }
  }

  void _syncPresence(RealtimeChannel channel) {
    _onlinePresence.clear();
    for (final state in channel.presenceState()) {
      for (final p in state.presences) {
        final uid = p.payload['user_id'] as String?;
        if (uid != null && uid.isNotEmpty) {
          _onlinePresence[uid] = RoomPresence.fromMap(p.payload);
        }
      }
    }
    notifyListeners();
  }

  /// Presence carries what this student is doing, so buddies see "focusing"
  /// or "on break" rather than a status that never changes.
  void _trackPresence() {
    final ch = _channel;
    final base = _myPresence;
    if (ch == null || base == null) return;
    ch.track({
      ...base,
      'study_status': !_timerRunning
          ? 'idle'
          : isFocus
              ? 'focusing'
              : 'on_break',
    }).ignore();
  }

  String? _nameFor(String userId) {
    for (final m in _members) {
      if (m.userId == userId) return m.displayName;
    }
    final p = _onlinePresence[userId];
    if (p != null && p.fullName.isNotEmpty) return p.fullName;
    return null;
  }

  String? _initialFor(String userId) {
    for (final m in _members) {
      if (m.userId == userId) return m.initial;
    }
    return _onlinePresence[userId]?.avatarInitial;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Timer
  // ───────────────────────────────────────────────────────────────────────────

  /// Broadcast messages arrive as `{type, event, payload}`; the data this app
  /// sent is under `payload`. Reading the top level instead is what used to
  /// zero every member's timer on each host command.
  @visibleForTesting
  static Map<String, dynamic> unwrapBroadcast(Map<String, dynamic> message) {
    final inner = message['payload'];
    return inner is Map ? Map<String, dynamic>.from(inner) : message;
  }

  void _onTimerMessage(Map<String, dynamic> message) {
    if (isHost) return; // The host is the source of truth, not a follower.
    applyTimerCommand(unwrapBroadcast(message));
  }

  /// Applies one host command to this device's timer. Public for tests.
  @visibleForTesting
  void applyTimerCommand(Map<String, dynamic> data) {
    final action = data['action'] as String?;
    if (action == null) return;

    // The host's end-of-block broadcast can land a moment before this
    // device's own countdown reaches zero; that still counts as finishing.
    // The host's focus and break lengths ride along, so a change made inside
    // the room reaches everyone's next phase too.
    final focusMin = (data['focus_min'] as num?)?.toInt();
    final breakMin = (data['break_min'] as num?)?.toInt();
    final room = _currentRoom;
    if (room != null &&
        focusMin != null &&
        breakMin != null &&
        (focusMin != room.timerDurationMin ||
            breakMin != room.breakDurationMin)) {
      _currentRoom = room.withTimer(focusMin: focusMin, breakMin: breakMin);
    }

    final wasFocus = isFocus;
    final nearlyDone = _secondsLeft <= 5;
    _timerPhase = data['phase'] == 'break' ? 'break' : 'focus';
    if (wasFocus && !isFocus && action == 'switch_phase' && nearlyDone) {
      _creditFocus();
    } else if (isFocus && (action == 'reset' || action == 'switch_phase')) {
      _focusSeen = 0;
    }
    final total = (data['total_secs'] as num?)?.toInt();
    _totalSeconds = total != null && total > 0 ? total : _phaseSeconds();
    final remaining = (data['remaining_secs'] as num?)?.toInt();
    _secondsLeft = (remaining ?? _totalSeconds).clamp(0, _totalSeconds);

    final running = switch (action) {
      'start' || 'resume' => true,
      'sync' => data['running'] == true,
      _ => false, // pause, reset, switch_phase
    };
    _timerRunning = running;
    if (running) {
      _startTicker();
    } else {
      _ticker?.cancel();
    }
    _trackPresence();
    notifyListeners();
  }

  int _phaseSeconds() =>
      (isFocus
          ? (_currentRoom?.timerDurationMin ?? 25)
          : (_currentRoom?.breakDurationMin ?? 5)) *
      60;

  void startTimer() {
    if (!isHost) return;
    if (_secondsLeft <= 0) _secondsLeft = _totalSeconds;
    _timerRunning = true;
    _startTicker();
    _afterHostChange('start');
  }

  void pauseTimer() {
    if (!isHost) return;
    _timerRunning = false;
    _ticker?.cancel();
    _afterHostChange('pause');
  }

  void toggleTimer() => _timerRunning ? pauseTimer() : startTimer();

  /// Host only, while the clock is stopped: sets how long a focus block and a
  /// break last for everyone in the room, and resets the clock to the new
  /// length. Saved on the room, so people who join later get it too.
  Future<bool> setTimerLengths({
    required int focusMin,
    required int breakMin,
  }) async {
    final room = _currentRoom;
    if (room == null || !isHost || _timerRunning) return false;
    if (focusMin == room.timerDurationMin &&
        breakMin == room.breakDurationMin) {
      return true;
    }
    final ok = await runMutation(() => _roomRepo.setTimer(
          room.id,
          focusMin: focusMin,
          breakMin: breakMin,
        ));
    if (!ok || _currentRoom?.id != room.id) return false;
    _currentRoom =
        _currentRoom!.withTimer(focusMin: focusMin, breakMin: breakMin);
    // A new length means a fresh block; resuming part-way through the old one
    // would be a confusing number to show.
    if (isFocus) _focusSeen = 0;
    _totalSeconds = _phaseSeconds();
    _secondsLeft = _totalSeconds;
    _afterHostChange('reset');
    return true;
  }

  void resetTimer() {
    if (!isHost) return;
    _ticker?.cancel();
    _timerRunning = false;
    if (isFocus) _focusSeen = 0;
    _totalSeconds = _phaseSeconds();
    _secondsLeft = _totalSeconds;
    _afterHostChange('reset');
  }

  void switchPhase(String phase) {
    if (!isHost) return;
    _ticker?.cancel();
    _timerRunning = false;
    _timerPhase = phase == 'break' ? 'break' : 'focus';
    // Skipping ahead isn't finishing: a block cut short earns nothing, the same
    // rule as the solo Pomodoro timer.
    _focusSeen = 0;
    _totalSeconds = _phaseSeconds();
    _secondsLeft = _totalSeconds;
    _afterHostChange('switch_phase');
  }

  void _afterHostChange(String action) {
    _trackPresence();
    notifyListeners();
    _broadcastTimer(action);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) {
        _secondsLeft--;
        if (isFocus) _focusSeen++;
        notifyListeners();
        return;
      }
      // Phase over. Everyone flips locally, and the host re-announces so any
      // drift is corrected at the boundary.
      _ticker?.cancel();
      _timerRunning = false;
      if (isFocus) {
        _creditFocus();
      } else {
        _focusSeen = 0;
      }
      _timerPhase = isFocus ? 'break' : 'focus';
      _totalSeconds = _phaseSeconds();
      _secondsLeft = _totalSeconds;
      _trackPresence();
      notifyListeners();
      if (isHost) _broadcastTimer('switch_phase');
    });
  }

  /// Logs a finished focus block for this student through
  /// `record_focus_session` — the same path, daily cap and XP rate as the solo
  /// timer. Studying in a room used to earn nothing.
  Future<void> _creditFocus() async {
    final room = _currentRoom;
    final seen = _focusSeen;
    _focusSeen = 0;
    if (room == null) return;
    final minutes = (seen ~/ 60).clamp(0, room.timerDurationMin);
    if (minutes < 1) return;
    try {
      await _game.recordSession(
        lengthMin: room.timerDurationMin,
        focusedMin: minutes,
      );
      _focusReward = 'Focus block done — $minutes min logged, XP earned.';
    } catch (_) {
      // Most likely the daily focus cap. The block still happened; there's
      // nothing the student can do about a refused credit mid-session.
      _focusReward = null;
    }
    notifyListeners();
  }

  void _broadcastTimer(String action) {
    _channel?.sendBroadcastMessage(
      event: 'timer',
      payload: {
        'action': action,
        'phase': _timerPhase,
        'remaining_secs': _secondsLeft,
        'total_secs': _totalSeconds,
        'running': _timerRunning,
        if (_currentRoom != null) ...{
          'focus_min': _currentRoom!.timerDurationMin,
          'break_min': _currentRoom!.breakDurationMin,
        },
      },
    ).ignore();
  }

  void _onRoomMessage(Map<String, dynamic> message) {
    if (isHost) return;
    final data = unwrapBroadcast(message);
    switch (data['action']) {
      case 'closed':
        _closedNotice = 'The host closed this room.';
      case 'removed' when data['user_id'] == _me:
        _closedNotice = 'The host removed you from this room.';
      case 'removed':
        _members = [
          for (final m in _members)
            if (m.userId != data['user_id']) m,
        ];
        notifyListeners();
        return;
      default:
        return;
    }
    _ticker?.cancel();
    _timerRunning = false;
    _setQuiz(null);
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Group quiz
  // ───────────────────────────────────────────────────────────────────────────

  /// Host only: writes [count] questions from one of the host's own materials
  /// and asks everyone in the room to agree. Nobody sees a question until all
  /// of them have.
  Future<bool> proposeQuiz({
    required String materialId,
    required int count,
    bool speed = false,
    int seconds = 20,
  }) async {
    final room = _currentRoom;
    if (room == null || !isHost || _quizWorking) return false;
    // Through runMutation so the shared generate sheet can read [busy] and
    // [error] off this store, the same as it does for solo quizzes.
    _quizWorking = true;
    RoomQuiz? made;
    final ok = await runMutation(() async {
      final id = await _roomRepo.proposeQuiz(
        roomId: room.id,
        materialId: materialId,
        count: count,
        speed: speed,
        seconds: seconds,
      );
      made = await _roomRepo.getQuiz(id);
    });
    _quizWorking = false;
    final quiz = made;
    if (!ok || quiz == null || _currentRoom?.id != room.id) {
      notifyListeners();
      return false;
    }
    _dismissedQuizzes.remove(quiz.id);
    _setQuiz(quiz);
    _pingQuiz(quiz.id);
    notifyListeners();
    return true;
  }

  /// Agree to take the quiz, or decline it. One "no" cancels it for the whole
  /// room, and the last "yes" starts it.
  Future<bool> voteQuiz(bool agree) =>
      _quizMutation((q) => _roomRepo.voteQuiz(q.id, agree));

  /// Picks [option] for [questionId], until the student hands in.
  void pickAnswer(String questionId, int option) {
    final q = _quiz;
    if (q == null || !q.running || _iSubmitted) return;
    _draftPicks = {..._draftPicks, questionId: option};
    notifyListeners();
  }

  /// Hands in this student's answers. The server marks them; everyone's
  /// scores show once the last person hands in or the host ends the quiz.
  Future<bool> submitQuiz() =>
      _quizMutation((q) => _roomRepo.submitQuiz(q.id, _draftPicks));

  /// Host only: cancels a quiz still being voted on, or ends a running one
  /// for whoever has handed in.
  Future<bool> endQuiz() async {
    if (!isHost) return false;
    return _quizMutation((q) => _roomRepo.endQuiz(q.id));
  }

  /// Speed round: locks in [option] for [questionId] while its window is
  /// open. The server times it, so a late tap is refused there.
  Future<bool> answerSpeed(String questionId, int option) =>
      _quizMutation((q) => _roomRepo.answerSpeed(q.id, questionId, option));

  /// Speed round: asks the server to close it once the clock has run out.
  /// Quiet: whichever phone gets there first closes it.
  Future<void> tickQuiz() async {
    final q = _quiz;
    if (q == null || !q.speed || !q.running) return;
    try {
      final fresh = await _roomRepo.tickQuiz(q.id);
      if (_currentRoom?.id != fresh.roomId) return;
      final ended = fresh.finished && !q.finished;
      _setQuiz(fresh);
      if (ended) _pingQuiz(fresh.id);
      notifyListeners();
    } catch (_) {}
  }

  /// Hides a finished or cancelled quiz's card.
  void dismissQuiz() {
    final q = _quiz;
    if (q == null || q.open) return;
    _dismissedQuizzes.add(q.id);
    _setQuiz(null);
    notifyListeners();
  }

  bool get _iSubmitted => _quiz?.player(_me)?.submitted ?? false;

  Future<bool> _quizMutation(
      Future<RoomQuiz> Function(RoomQuiz q) call) async {
    final q = _quiz;
    if (q == null) return false;
    RoomQuiz? fresh;
    final ok = await runMutation(() async => fresh = await call(q));
    final got = fresh;
    if (got != null && _currentRoom?.id == got.roomId) {
      _setQuiz(got);
      _pingQuiz(got.id);
      notifyListeners();
    } else if (!ok) {
      // Most likely the quiz moved on meanwhile (someone declined, the host
      // ended it). Show where it actually is.
      refreshQuiz().ignore();
    }
    return ok;
  }

  /// Re-reads the quiz from the server.
  Future<void> refreshQuiz() async {
    final q = _quiz;
    final room = _currentRoom;
    if (room == null) return;
    try {
      final fresh = q != null
          ? await _roomRepo.getQuiz(q.id)
          : await _roomRepo.getActiveQuiz(room.id);
      if (_currentRoom?.id != room.id) return;
      if (fresh == null || _dismissedQuizzes.contains(fresh.id)) {
        if (q == null) return;
        _setQuiz(null);
      } else {
        _setQuiz(fresh);
      }
      notifyListeners();
    } catch (_) {
      // The next ping or poll tries again; nothing for the student to do.
    }
  }

  Future<void> _loadQuiz(String roomId) async {
    try {
      final quiz = await _roomRepo.getActiveQuiz(roomId);
      if (_currentRoom?.id != roomId) return;
      if (quiz != null && !_dismissedQuizzes.contains(quiz.id)) {
        _setQuiz(quiz);
        notifyListeners();
      }
    } catch (_) {
      // No card is the same as no quiz; the next ping brings it.
    }
  }

  void _onQuizMessage(Map<String, dynamic> message) {
    final id = unwrapBroadcast(message)['quiz_id'];
    final room = _currentRoom;
    if (id is! String || room == null) return;
    if (_quiz?.id == id) {
      refreshQuiz().ignore();
    } else {
      // A new quiz was proposed.
      _loadQuiz(room.id).ignore();
    }
  }

  void _pingQuiz(String quizId) {
    _channel?.sendBroadcastMessage(
      event: 'quiz',
      payload: {'quiz_id': quizId},
    ).ignore();
  }

  /// Swaps in [quiz], clearing answers when it's a different quiz, and polls
  /// while it's open: a missed ping would otherwise leave someone stuck on
  /// "waiting for votes".
  void _setQuiz(RoomQuiz? quiz) {
    if (quiz?.id != _quiz?.id) _draftPicks = {};
    _quiz = quiz;
    final every = quizPollInterval;
    if (quiz != null && quiz.open && every != null) {
      _quizPoll ??= Timer.periodic(every, (_) => refreshQuiz().ignore());
    } else {
      _quizPoll?.cancel();
      _quizPoll = null;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Moderation
  // ───────────────────────────────────────────────────────────────────────────

  Future<bool> blockUser(String userId) => runMutation(() async {
        await _roomRepo.block(userId);
        _blocked = {..._blocked, userId};
      });

  Future<bool> unblockUser(String userId) => runMutation(() async {
        await _roomRepo.unblock(userId);
        _blocked = {..._blocked}..remove(userId);
      });

  /// Files a report about [userId], optionally about one message.
  Future<bool> report({
    required String userId,
    required String reason,
    String? messageId,
  }) async {
    final room = _currentRoom;
    if (room == null) return false;
    return runMutation(() => _roomRepo.report(
          roomId: room.id,
          userId: userId,
          reason: reason,
          messageId: messageId,
        ));
  }

  /// Host only. The removed student is told over the channel, and the server
  /// stops them rejoining with the code.
  Future<bool> removeMember(String userId) async {
    final room = _currentRoom;
    if (room == null || !isHost) return false;
    final ok = await runMutation(() => _roomRepo.removeMember(room.id, userId));
    if (ok) {
      _channel?.sendBroadcastMessage(
        event: 'room',
        payload: {'action': 'removed', 'user_id': userId},
      ).ignore();
      _members = [
        for (final m in _members)
          if (m.userId != userId) m,
      ];
      notifyListeners();
    }
    return ok;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Chat
  // ───────────────────────────────────────────────────────────────────────────

  /// Inserts or replaces by id, so an echo that beats the insert's own
  /// response (or arrives after it) never doubles a bubble.
  void _upsertMessage(RoomMessage msg) {
    if (msg.roomId != _currentRoom?.id) return;
    final i = _messages.indexWhere((m) => m.id == msg.id);
    _messages = i < 0
        ? [..._messages, msg]
        : [
            for (var j = 0; j < _messages.length; j++)
              j == i ? msg : _messages[j],
          ];
    notifyListeners();
  }

  /// Returns false if the message couldn't be saved; the bubble is withdrawn
  /// and [error] says why, so the screen can hand the text back.
  Future<bool> sendMessage(String text) async {
    final room = _currentRoom;
    final body = text.trim();
    if (room == null || body.isEmpty) return false;
    if (body.length > 500) {
      setError('Messages can be up to 500 characters.');
      return false;
    }

    final id = RoomRepository.newMessageId();
    _upsertMessage(
      RoomMessage(
        id: id,
        roomId: room.id,
        userId: _me ?? '',
        body: body,
        createdAt: DateTime.now(),
        pending: true,
      ),
    );

    try {
      _upsertMessage(await _roomRepo.sendMessage(room.id, body, id: id));
      return true;
    } catch (e) {
      _messages = _messages.where((m) => m.id != id).toList();
      setError(e);
      return false;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Leaving
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _dropChannel() async {
    final ch = _channel;
    _channel = null;
    _myPresence = null;
    if (ch == null) return;
    try {
      await ch.untrack();
    } catch (_) {}
    try {
      await _roomRepo.removeRoomChannel(ch);
    } catch (_) {}
  }

  Future<void> leaveCurrentRoom() async {
    _ticker?.cancel();
    _timerRunning = false;
    _focusSeen = 0;
    final room = _currentRoom;

    await _dropChannel();
    if (room != null) {
      try {
        await _roomRepo.leaveRoom(room.id);
      } catch (_) {
        // Leaving is best effort: the trigger closes an abandoned room and the
        // lobby hides stale ones, so a failed delete costs nothing visible.
      }
    }

    _currentRoom = null;
    _closedNotice = null;
    _members = const [];
    _onlinePresence.clear();
    _messages = const [];
    _setQuiz(null);
    _dismissedQuizzes.clear();
    notifyListeners();
  }

  /// Host only: tells everyone, closes the room, and leaves it.
  Future<bool> closeCurrentRoom() async {
    final room = _currentRoom;
    if (room == null || !isHost) return false;
    _channel?.sendBroadcastMessage(
        event: 'room', payload: {'action': 'closed'}).ignore();
    final ok = await runMutation(() => _roomRepo.closeRoom(room.id));
    if (ok) await leaveCurrentRoom();
    return ok;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _quizPoll?.cancel();
    final ch = _channel;
    if (ch != null) _roomRepo.removeRoomChannel(ch).ignore();
    super.dispose();
  }
}
