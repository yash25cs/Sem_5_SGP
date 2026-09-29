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

/// A member of a study room.
class RoomMember {
  const RoomMember({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.fullName,
    this.avatarInitial,
  });

  final String id;
  final String roomId;
  final String userId;
  final String role; // 'host' | 'member'
  final DateTime joinedAt;

  /// Joined from profiles when the query embeds it.
  final String? fullName;
  final String? avatarInitial;

  bool get isHost => role == 'host';

  factory RoomMember.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'];
    return RoomMember(
      id: m['id'] as String,
      roomId: m['room_id'] as String,
      userId: m['user_id'] as String,
      role: (m['role'] as String?) ?? 'member',
      joinedAt: DateTime.parse(m['joined_at'] as String),
      fullName: profile is Map<String, dynamic>
          ? profile['full_name'] as String?
          : null,
      avatarInitial: profile is Map<String, dynamic>
          ? profile['avatar_initial'] as String?
          : null,
    );
  }
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
  });

  final String id;
  final String roomId;
  final String userId;
  final String body;
  final DateTime createdAt;

  /// Filled from presence or a local cache — not always from the DB query.
  final String? senderName;
  final String? senderInitial;

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
