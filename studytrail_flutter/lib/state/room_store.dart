import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// State store managing the Study Buddy Room lobby and the active room session.
class RoomStore extends AsyncStore {
  RoomStore({
    RoomRepository? roomRepo,
    ProfileRepository? profileRepo,
  })  : _roomRepo = roomRepo ?? const RoomRepository(),
        _profileRepo = profileRepo ?? const ProfileRepository();

  final RoomRepository _roomRepo;
  final ProfileRepository _profileRepo;

  // ── Lobby State ──
  List<StudyRoom> _activeRooms = const [];
  List<StudyRoom> get activeRooms => _activeRooms;

  // ── Active Room State ──
  StudyRoom? _currentRoom;
  StudyRoom? get currentRoom => _currentRoom;
  bool get inRoom => _currentRoom != null;
  bool get isHost => _currentRoom != null && _currentRoom!.createdBy == currentUserId;

  List<RoomMember> _members = const [];
  List<RoomMember> get members => _members;

  final Map<String, RoomPresence> _onlinePresence = {};
  List<RoomPresence> get onlinePresence => _onlinePresence.values.toList();
  int get onlineCount => _onlinePresence.length;

  List<RoomMessage> _messages = [];
  List<RoomMessage> get messages => _messages;

  // ── Shared Timer State ──
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

  double get timerProgress {
    if (_totalSeconds == 0) return 0;
    return (_totalSeconds - _secondsLeft) / _totalSeconds;
  }

  RealtimeChannel? _channel;

  // ───────────────────────────────────────────────────────────────────────────
  // Lobby Actions
  // ───────────────────────────────────────────────────────────────────────────

  /// Loads available active rooms for the lobby.
  Future<void> loadLobby({String? classId}) => runLoad(() async {
        _activeRooms = await _roomRepo.getActiveRooms(classId: classId);
      });

  /// Creates a new study room and sets it as the active room.
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

    if (ok && created != null) {
      await enterRoom(created!);
      return created;
    }
    return null;
  }

  /// Joins a room using an invite code.
  Future<StudyRoom?> joinByCode(String code) async {
    StudyRoom? joined;
    final ok = await runMutation(() async {
      joined = await _roomRepo.joinRoomByCode(code);
    });

    if (ok && joined != null) {
      await enterRoom(joined!);
      return joined;
    }
    return null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Room Session Actions
  // ───────────────────────────────────────────────────────────────────────────

  /// Enters a room: loads members, chat history, subscribes to Realtime channel.
  Future<void> enterRoom(StudyRoom room) async {
    // If already in a different room, leave it first
    if (_currentRoom != null && _currentRoom!.id != room.id) {
      await leaveCurrentRoom();
    }

    _currentRoom = room;
    _totalSeconds = room.timerDurationMin * 60;
    _secondsLeft = _totalSeconds;
    _timerPhase = 'focus';
    _timerRunning = false;
    _onlinePresence.clear();
    notifyListeners();

    // 1. Fetch initial members and messages
    try {
      _members = await _roomRepo.getMembers(room.id);
      _messages = await _roomRepo.getMessages(room.id);
      notifyListeners();
    } catch (_) {}

    // 2. Setup Realtime Channel
    await _setupRealtime(room);
  }

  Future<void> _setupRealtime(StudyRoom room) async {
    try {
      final channel = _roomRepo.createRoomChannel(room.id);
      _channel = channel;

      // ── Broadcast: Synchronized Timer ──
      channel.onBroadcast(
        event: 'timer',
        callback: (payload) {
          _handleTimerBroadcast(payload);
        },
      );

      // ── Broadcast: Peer Chat Messages (Realtime fallback) ──
      channel.onBroadcast(
        event: 'chat',
        callback: (payload) {
          final msg = RoomMessage.fromMap(payload);
          if (!_messages.any((m) => m.id == msg.id)) {
            _messages = [..._messages, msg];
            notifyListeners();
          }
        },
      );

      // ── Postgres Changes: Message Inserts ──
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'room_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: room.id,
        ),
        callback: (payload) {
          final record = payload.newRecord;
          final msg = RoomMessage.fromMap(record);
          if (!_messages.any((m) => m.id == msg.id)) {
            _messages = [..._messages, msg];
            notifyListeners();
          }
        },
      );

      // ── Presence: Online peers ──
      channel.onPresenceSync((_) {
        final state = channel.presenceState();
        _onlinePresence.clear();
        for (final item in state) {
          for (final p in item.presences) {
            final payload = p.payload;
            final uid = payload['user_id'] as String?;
            if (uid != null && uid.isNotEmpty) {
              _onlinePresence[uid] = RoomPresence.fromMap(payload);
            }
          }
        }
        notifyListeners();
      });

      channel.subscribe();

      // Track self in presence
      final profile = await _profileRepo.getMyProfile();
      await channel.track({
        'user_id': currentUserId ?? '',
        'full_name': profile?.fullName ?? 'Student',
        'avatar_initial': profile?.initial ?? 'S',
        'study_status': 'focusing',
      });
    } catch (_) {
      // If realtime setup fails, app remains usable offline
    }
  }

  void _handleTimerBroadcast(Map<String, dynamic> payload) {
    final action = payload['action'] as String?;
    final phase = payload['phase'] as String? ?? 'focus';
    final remaining = (payload['remaining_secs'] as num?)?.toInt() ?? 0;

    _timerPhase = phase;
    _secondsLeft = remaining;

    switch (action) {
      case 'start':
      case 'resume':
        _timerRunning = true;
        _startTicker();
      case 'pause':
        _timerRunning = false;
        _ticker?.cancel();
      case 'reset':
        _timerRunning = false;
        _ticker?.cancel();
        _secondsLeft = (_timerPhase == 'focus'
                ? (_currentRoom?.timerDurationMin ?? 25)
                : (_currentRoom?.breakDurationMin ?? 5)) *
            60;
        _totalSeconds = _secondsLeft;
      case 'switch_phase':
        _timerRunning = false;
        _ticker?.cancel();
        _totalSeconds = (_timerPhase == 'focus'
                ? (_currentRoom?.timerDurationMin ?? 25)
                : (_currentRoom?.breakDurationMin ?? 5)) *
            60;
        _secondsLeft = _totalSeconds;
    }
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Timer Controls (Host Only)
  // ───────────────────────────────────────────────────────────────────────────

  void startTimer() {
    if (!isHost && _currentRoom != null) return;
    _timerRunning = true;
    _startTicker();
    notifyListeners();
    _broadcastTimer('start');
  }

  void pauseTimer() {
    if (!isHost && _currentRoom != null) return;
    _timerRunning = false;
    _ticker?.cancel();
    notifyListeners();
    _broadcastTimer('pause');
  }

  void toggleTimer() => _timerRunning ? pauseTimer() : startTimer();

  void resetTimer() {
    if (!isHost && _currentRoom != null) return;
    _ticker?.cancel();
    _timerRunning = false;
    _totalSeconds = (_timerPhase == 'focus'
            ? (_currentRoom?.timerDurationMin ?? 25)
            : (_currentRoom?.breakDurationMin ?? 5)) *
        60;
    _secondsLeft = _totalSeconds;
    notifyListeners();
    _broadcastTimer('reset');
  }

  void switchPhase(String phase) {
    if (!isHost && _currentRoom != null) return;
    _ticker?.cancel();
    _timerRunning = false;
    _timerPhase = phase;
    _totalSeconds = (_timerPhase == 'focus'
            ? (_currentRoom?.timerDurationMin ?? 25)
            : (_currentRoom?.breakDurationMin ?? 5)) *
        60;
    _secondsLeft = _totalSeconds;
    notifyListeners();
    _broadcastTimer('switch_phase');
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) {
        _secondsLeft--;
        notifyListeners();
      } else {
        // Timer completed! Hand over to next phase
        _ticker?.cancel();
        _timerRunning = false;
        _timerPhase = _timerPhase == 'focus' ? 'break' : 'focus';
        _totalSeconds = (_timerPhase == 'focus'
                ? (_currentRoom?.timerDurationMin ?? 25)
                : (_currentRoom?.breakDurationMin ?? 5)) *
            60;
        _secondsLeft = _totalSeconds;
        notifyListeners();
        if (isHost) _broadcastTimer('switch_phase');
      }
    });
  }

  void _broadcastTimer(String action) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sendBroadcastMessage(
        event: 'timer',
        payload: {
          'action': action,
          'phase': _timerPhase,
          'remaining_secs': _secondsLeft,
        },
      );
    } catch (_) {}
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Chat Actions
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    final room = _currentRoom;
    if (room == null || text.trim().isEmpty) return;

    final body = text.trim();
    final profile = await _profileRepo.getMyProfile();

    // Optimistic message
    final tempMsg = RoomMessage(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      roomId: room.id,
      userId: currentUserId ?? '',
      body: body,
      createdAt: DateTime.now(),
      senderName: profile?.fullName ?? 'You',
      senderInitial: profile?.initial ?? 'Y',
    );
    _messages = [..._messages, tempMsg];
    notifyListeners();

    // Broadcast immediately so peers receive it with low latency
    _channel?.sendBroadcastMessage(
      event: 'chat',
      payload: {
        'id': tempMsg.id,
        'room_id': room.id,
        'user_id': tempMsg.userId,
        'body': tempMsg.body,
        'created_at': tempMsg.createdAt.toIso8601String(),
        'profiles': {
          'full_name': tempMsg.senderName,
          'avatar_initial': tempMsg.senderInitial,
        }
      },
    );

    // Persist to database
    try {
      final saved = await _roomRepo.sendMessage(room.id, body);
      _messages = [
        for (final m in _messages) m.id == tempMsg.id ? saved : m,
      ];
      notifyListeners();
    } catch (_) {
      // Kept in optimistic local list
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Leaving Room
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> leaveCurrentRoom() async {
    _ticker?.cancel();
    _timerRunning = false;

    final room = _currentRoom;
    final ch = _channel;

    if (ch != null) {
      try {
        await _roomRepo.removeRoomChannel(ch);
      } catch (_) {}
      _channel = null;
    }

    if (room != null) {
      try {
        await _roomRepo.leaveRoom(room.id);
      } catch (_) {}
    }

    _currentRoom = null;
    _members = const [];
    _onlinePresence.clear();
    _messages = [];
    notifyListeners();
  }

  Future<void> closeCurrentRoom() async {
    final room = _currentRoom;
    if (room != null && isHost) {
      await _roomRepo.closeRoom(room.id);
      await leaveCurrentRoom();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_channel != null) {
      _roomRepo.removeRoomChannel(_channel!);
    }
    super.dispose();
  }
}
