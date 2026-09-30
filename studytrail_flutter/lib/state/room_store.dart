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
/// * **postgres_changes on `room_messages`** — chat. The sender picks the row
///   id up front, so its optimistic bubble and the realtime echo de-duplicate.
///
/// Presence says who is on screen right now; the member list says who has
/// joined. A late joiner's presence arriving is the host's cue to re-send the
/// timer, which is how someone who walks in mid-session sees the right time.
class RoomStore extends AsyncStore {
  RoomStore({RoomRepository? roomRepo, ProfileRepository? profileRepo})
      : _roomRepo = roomRepo ?? const RoomRepository(),
        _profileRepo = profileRepo ?? const ProfileRepository();

  final RoomRepository _roomRepo;
  final ProfileRepository _profileRepo;

  // ── Lobby ──
  List<StudyRoom> _activeRooms = const [];
  List<StudyRoom> get activeRooms => _activeRooms;

  // ── Current room ──
  StudyRoom? _currentRoom;
  StudyRoom? get currentRoom => _currentRoom;
  bool get inRoom => _currentRoom != null;
  bool get isHost =>
      _currentRoom != null && _currentRoom!.createdBy == currentUserId;

  List<RoomMember> _members = const [];
  List<RoomMember> get members => _members;

  final Map<String, RoomPresence> _onlinePresence = {};
  List<RoomPresence> get onlinePresence => _onlinePresence.values.toList();
  int get onlineCount => _onlinePresence.length;

  List<RoomMessage> _messages = const [];

  /// Oldest first, with sender names filled in from the member list or
  /// presence — neither the table rows nor the realtime payloads carry names.
  List<RoomMessage> get messages => [
        for (final m in _messages)
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
    int maxMembers = 10,
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
    notifyListeners();

    try {
      final results = await Future.wait([
        _roomRepo.getMembers(room.id),
        _roomRepo.getMessages(room.id),
      ]);
      _members = results[0] as List<RoomMember>;
      final history = results[1] as List<RoomMessage>;
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
            .where((id) => id != currentUserId);
        if (newcomers.isEmpty) return;
        // Someone walked in: they need the current time, and their name.
        if (isHost) _broadcastTimer('sync');
        if (newcomers.any((id) => !_members.any((m) => m.userId == id))) {
          _refreshMembers();
        }
      });

    final profile = await _profileRepo.getMyProfile().catchError((_) => null);
    _myPresence = {
      'user_id': currentUserId ?? '',
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

    _timerPhase = data['phase'] == 'break' ? 'break' : 'focus';
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

  void resetTimer() {
    if (!isHost) return;
    _ticker?.cancel();
    _timerRunning = false;
    _totalSeconds = _phaseSeconds();
    _secondsLeft = _totalSeconds;
    _afterHostChange('reset');
  }

  void switchPhase(String phase) {
    if (!isHost) return;
    _ticker?.cancel();
    _timerRunning = false;
    _timerPhase = phase == 'break' ? 'break' : 'focus';
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
        notifyListeners();
        return;
      }
      // Phase over. Everyone flips locally, and the host re-announces so any
      // drift is corrected at the boundary.
      _ticker?.cancel();
      _timerRunning = false;
      _timerPhase = isFocus ? 'break' : 'focus';
      _totalSeconds = _phaseSeconds();
      _secondsLeft = _totalSeconds;
      _trackPresence();
      notifyListeners();
      if (isHost) _broadcastTimer('switch_phase');
    });
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
      },
    ).ignore();
  }

  void _onRoomMessage(Map<String, dynamic> message) {
    if (isHost) return;
    if (unwrapBroadcast(message)['action'] == 'closed') {
      _closedNotice = 'The host closed this room.';
      _ticker?.cancel();
      _timerRunning = false;
      notifyListeners();
    }
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
        userId: currentUserId ?? '',
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
    final ch = _channel;
    if (ch != null) _roomRepo.removeRoomChannel(ch).ignore();
    super.dispose();
  }
}
