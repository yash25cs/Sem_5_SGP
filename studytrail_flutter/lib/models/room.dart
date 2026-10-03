/// Models for the Study Buddy Room feature: rooms, members, and chat.
library;

/// A study room where classmates focus together with a shared timer.
class StudyRoom {
  const StudyRoom({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.createdBy,
    this.classId,
    this.maxMembers = 10,
    this.timerDurationMin = 25,
    this.breakDurationMin = 5,
    this.status = 'active',
    required this.createdAt,
    this.memberCount = 0,
  });

  final String id;
  final String name;
  final String inviteCode;
  final String createdBy;
  final String? classId;
  final int maxMembers;
  final int timerDurationMin;
  final int breakDurationMin;
  final String status;
  final DateTime createdAt;

  /// Populated from a joined count query or room_members embed.
  final int memberCount;

  bool get isActive => status == 'active';
  bool get isFull => memberCount >= maxMembers;

  /// The same room with the host's new focus/break lengths.
  StudyRoom withTimer({required int focusMin, required int breakMin}) =>
      StudyRoom(
        id: id,
        name: name,
        inviteCode: inviteCode,
        createdBy: createdBy,
        classId: classId,
        maxMembers: maxMembers,
        timerDurationMin: focusMin,
        breakDurationMin: breakMin,
        status: status,
        createdAt: createdAt,
        memberCount: memberCount,
      );

  factory StudyRoom.fromMap(Map<String, dynamic> m) {
    // memberCount can come from an aggregate or a nested list length.
    int members = 0;
    final raw = m['room_members'];
    if (raw is List) {
      members = raw.length;
    } else if (m['member_count'] is num) {
      members = (m['member_count'] as num).toInt();
    }

    return StudyRoom(
      id: m['id'] as String,
      name: (m['name'] as String?) ?? '',
      inviteCode: (m['invite_code'] as String?) ?? '',
      createdBy: m['created_by'] as String,
      classId: m['class_id'] as String?,
      maxMembers: (m['max_members'] as num?)?.toInt() ?? 10,
      timerDurationMin: (m['timer_duration_min'] as num?)?.toInt() ?? 25,
      breakDurationMin: (m['break_duration_min'] as num?)?.toInt() ?? 5,
      status: (m['status'] as String?) ?? 'active',
      createdAt: DateTime.parse(m['created_at'] as String),
      memberCount: members,
    );
  }
}

/// A member of a study room, as returned by the `get_room_members` RPC.
class RoomMember {
  const RoomMember({
    required this.roomId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.fullName,
    this.avatarInitial,
  });

  final String roomId;
  final String userId;
  final String role; // 'host' | 'member'
  final DateTime joinedAt;

  /// From profiles, which the RPC reads past the owner-only policy.
  final String? fullName;
  final String? avatarInitial;

  bool get isHost => role == 'host';

  String get displayName {
    final n = fullName?.trim() ?? '';
    return n.isEmpty ? 'Student' : n;
  }

  String get initial {
    final a = avatarInitial?.trim() ?? '';
    if (a.isNotEmpty) return a[0].toUpperCase();
    return displayName[0].toUpperCase();
  }

  factory RoomMember.fromMap(
    Map<String, dynamic> m, {
    required String roomId,
  }) =>
      RoomMember(
        roomId: (m['room_id'] as String?) ?? roomId,
        userId: m['user_id'] as String,
        role: (m['role'] as String?) ?? 'member',
        joinedAt: DateTime.parse(m['joined_at'] as String),
        fullName: m['full_name'] as String?,
        avatarInitial: m['avatar_initial'] as String?,
      );
}

/// A chat message in a study room.
class RoomMessage {
  const RoomMessage({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.senderName,
    this.senderInitial,
    this.pending = false,
  });

  final String id;
  final String roomId;
  final String userId;
  final String body;
  final DateTime createdAt;

  /// Resolved by the store from the member list and presence — rows and
  /// realtime payloads carry only `user_id`.
  final String? senderName;
  final String? senderInitial;

  /// True for an optimistic bubble whose insert hasn't been confirmed.
  final bool pending;

  factory RoomMessage.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'];
    return RoomMessage(
      id: m['id'] as String,
      roomId: m['room_id'] as String,
      userId: m['user_id'] as String,
      body: (m['body'] as String?) ?? '',
      createdAt: DateTime.parse(m['created_at'] as String),
      senderName: profile is Map<String, dynamic>
          ? profile['full_name'] as String?
          : null,
      senderInitial: profile is Map<String, dynamic>
          ? profile['avatar_initial'] as String?
          : null,
    );
  }

  RoomMessage copyWithSender({String? name, String? initial}) => RoomMessage(
        id: id,
        roomId: roomId,
        userId: userId,
        body: body,
        createdAt: createdAt,
        senderName: name ?? senderName,
        senderInitial: initial ?? senderInitial,
        pending: pending,
      );
}

/// A peer's presence state inside a room channel.
class RoomPresence {
  const RoomPresence({
    required this.userId,
    required this.fullName,
    required this.avatarInitial,
    this.studyStatus = 'idle',
  });

  final String userId;
  final String fullName;
  final String avatarInitial;

  /// 'idle' | 'focusing' | 'on_break'
  final String studyStatus;

  factory RoomPresence.fromMap(Map<String, dynamic> m) => RoomPresence(
        userId: m['user_id'] as String? ?? '',
        fullName: m['full_name'] as String? ?? '',
        avatarInitial: m['avatar_initial'] as String? ?? '?',
        studyStatus: m['study_status'] as String? ?? 'idle',
      );
}

/// Timer state broadcast payload.
class TimerSync {
  const TimerSync({
    required this.action,
    required this.remainingSecs,
    this.startedAt,
  });

  /// 'start' | 'pause' | 'resume' | 'reset' | 'break'
  final String action;
  final int remainingSecs;
  final DateTime? startedAt;

  factory TimerSync.fromMap(Map<String, dynamic> m) => TimerSync(
        action: m['action'] as String? ?? 'reset',
        remainingSecs: (m['remaining_secs'] as num?)?.toInt() ?? 0,
        startedAt: m['started_at'] != null
            ? DateTime.tryParse(m['started_at'] as String)
            : null,
      );

  Map<String, dynamic> toMap() => {
        'action': action,
        'remaining_secs': remainingSecs,
        if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
      };
}

/// One player in a group quiz, as `get_room_quiz` reports them.
class RoomQuizPlayer {
  const RoomQuizPlayer({
    required this.userId,
    required this.name,
    required this.initial,
    this.vote,
    this.submitted = false,
    this.score,
    this.rank,
    this.xpAwarded = 0,
    this.answeredCurrent = false,
  });

  final String userId;
  final String name;
  final String initial;

  /// Speed round: has answered the question that's open now.
  final bool answeredCurrent;

  /// null until they answer the invitation.
  final bool? vote;
  final bool submitted;

  /// Everyone's once the quiz is finished; only your own before that.
  final int? score;
  final int? rank;
  final int xpAwarded;

  factory RoomQuizPlayer.fromMap(Map<String, dynamic> m) {
    final name = ((m['full_name'] as String?) ?? '').trim();
    final initial = ((m['avatar_initial'] as String?) ?? '').trim();
    return RoomQuizPlayer(
      userId: m['user_id'] as String,
      name: name.isEmpty ? 'Student' : name,
      initial: initial.isNotEmpty
          ? initial[0].toUpperCase()
          : (name.isEmpty ? 'S' : name[0].toUpperCase()),
      vote: m['vote'] as bool?,
      submitted: m['submitted'] == true,
      score: (m['score'] as num?)?.toInt(),
      rank: (m['rank'] as num?)?.toInt(),
      xpAwarded: (m['xp_awarded'] as num?)?.toInt() ?? 0,
      answeredCurrent: m['answered_current'] == true,
    );
  }
}

/// Where a speed round is right now, by the server's clock
/// (`app_private.speed_clock`, `0022_speed_quiz.sql`): a 5 s lead, then each
/// question gets its answering window and a 4 s reveal.
class SpeedClock {
  const SpeedClock({
    required this.index,
    required this.inSlot,
    required this.seconds,
  });

  static const leadSeconds = 5;
  static const revealSeconds = 4;

  /// The question in play; -1 during the lead.
  final int index;

  /// Seconds into this question's slot (or, during the lead, into the lead).
  final double inSlot;
  final int seconds;

  bool get lead => index < 0;
  bool get answering => !lead && inSlot < seconds;
  bool get revealing => !lead && inSlot >= seconds;

  /// Seconds left in whatever is happening now.
  double get secondsLeft => lead
      ? (seconds + revealSeconds) - inSlot
      : answering
          ? seconds - inSlot
          : (seconds + revealSeconds) - inSlot;

  factory SpeedClock.at(DateTime serverNow, DateTime startedAt, int seconds) {
    final e = serverNow.difference(startedAt).inMilliseconds / 1000 -
        leadSeconds;
    final slot = seconds + revealSeconds;
    final index = (e / slot).floor();
    return SpeedClock(index: index, inSlot: e - index * slot, seconds: seconds);
  }
}

/// A question in a group quiz. [correctIndex] and [explanation] stay null
/// until the quiz is finished: the server doesn't send them before that.
class RoomQuizQuestion {
  const RoomQuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    this.correctIndex,
    this.explanation,
  });

  final String id;
  final String question;
  final List<String> options;
  final int? correctIndex;
  final String? explanation;

  factory RoomQuizQuestion.fromMap(Map<String, dynamic> m) => RoomQuizQuestion(
        id: m['id'] as String,
        question: (m['question'] as String?) ?? '',
        options: [for (final o in (m['options'] as List? ?? const [])) '$o'],
        correctIndex: (m['correct_index'] as num?)?.toInt(),
        explanation: m['explanation'] as String?,
      );
}

/// A quiz the whole room takes together (0019_room_quiz.sql).
class RoomQuiz {
  const RoomQuiz({
    required this.id,
    required this.roomId,
    required this.createdBy,
    required this.title,
    required this.questionCount,
    required this.status,
    this.players = const [],
    this.questions = const [],
    this.myPicks = const {},
    this.mode = 'standard',
    this.secondsPerQuestion,
    this.startedAt,
    this.clockOffset = Duration.zero,
  });

  final String id;
  final String roomId;
  final String createdBy;
  final String title;
  final int questionCount;

  /// 'voting' | 'running' | 'finished' | 'cancelled'
  final String status;

  /// Ranked once the quiz is finished.
  final List<RoomQuizPlayer> players;

  /// Empty while voting; the same list for every player once it runs.
  final List<RoomQuizQuestion> questions;

  /// Question id to option index, once this student has handed in — or, in a
  /// speed round, as they answer.
  final Map<String, int> myPicks;

  /// 'standard' (everyone at their own pace) or 'speed'.
  final String mode;
  final int? secondsPerQuestion;
  final DateTime? startedAt;

  /// The server's clock minus this phone's, when this was read. A speed round
  /// is timed on the server, so the countdown is drawn on its clock.
  final Duration clockOffset;

  bool get speed => mode == 'speed';

  /// Null unless this is a speed round that has started.
  SpeedClock? clockAt(DateTime localNow) {
    final started = startedAt;
    final secs = secondsPerQuestion;
    if (!speed || started == null || secs == null) return null;
    return SpeedClock.at(localNow.add(clockOffset), started, secs);
  }

  bool get voting => status == 'voting';
  bool get running => status == 'running';
  bool get finished => status == 'finished';
  bool get cancelled => status == 'cancelled';
  bool get open => voting || running;

  RoomQuizPlayer? player(String? userId) {
    for (final p in players) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  int get agreedCount => players.where((p) => p.vote == true).length;
  int get submittedCount => players.where((p) => p.submitted).length;

  factory RoomQuiz.fromMap(Map<String, dynamic> m) {
    final picks = m['my_picks'];
    final serverNow = m['server_now'] is String
        ? DateTime.tryParse(m['server_now'] as String)
        : null;
    return RoomQuiz(
      mode: (m['mode'] as String?) ?? 'standard',
      secondsPerQuestion: (m['seconds_per_question'] as num?)?.toInt(),
      startedAt: m['started_at'] is String
          ? DateTime.tryParse(m['started_at'] as String)
          : null,
      clockOffset: serverNow == null
          ? Duration.zero
          : serverNow.difference(DateTime.now()),
      id: m['id'] as String,
      roomId: m['room_id'] as String,
      createdBy: m['created_by'] as String,
      title: (m['title'] as String?) ?? 'Group quiz',
      questionCount: (m['question_count'] as num?)?.toInt() ?? 0,
      status: (m['status'] as String?) ?? 'voting',
      players: [
        for (final p in (m['players'] as List? ?? const []))
          RoomQuizPlayer.fromMap(Map<String, dynamic>.from(p as Map)),
      ],
      questions: [
        for (final q in (m['questions'] as List? ?? const []))
          RoomQuizQuestion.fromMap(Map<String, dynamic>.from(q as Map)),
      ],
      myPicks: picks is Map
          ? {
              for (final e in picks.entries)
                if (e.value is num) '${e.key}': (e.value as num).toInt(),
            }
          : const {},
    );
  }
}
