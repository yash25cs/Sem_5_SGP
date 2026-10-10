import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../models/models.dart';
import '../supabase_client.dart';

/// Database access and realtime channels for Study Buddy Rooms.
///
/// Creating, joining and closing a room are RPCs only — `0011_study_rooms_fix`
/// revokes the direct writes, because each one has a check the client can't be
/// trusted with (capacity, open-room, host-only). Errors are allowed to
/// propagate: the old version caught them and returned empty lists, which is
/// how a recursive RLS policy went unnoticed while the lobby sat empty.
class RoomRepository {
  const RoomRepository();

  /// A room nobody closed (the host's app died) still reads as active until
  /// the host opens another. Past this age the lobby stops offering it.
  static const staleAfter = Duration(hours: 12);

  /// Every open room, newest first — rooms are open to all students (0029).
  Future<List<StudyRoom>> getActiveRooms() async {
    final since = DateTime.now().toUtc().subtract(staleAfter).toIso8601String();
    final rows = await db
        .from('study_rooms')
        .select('*, room_members(user_id)')
        .eq('status', 'active')
        .gte('created_at', since)
        .order('created_at', ascending: false);
    return rows.map(StudyRoom.fromMap).toList();
  }

  /// Creates a room and enrols the caller as host, atomically.
  Future<StudyRoom> createRoom({
    required String name,
    String? classId,
    int timerMin = 25,
    int breakMin = 5,
    int maxMembers = 4,
  }) async {
    final res = await db.rpc(
      'create_study_room',
      params: {
        'p_name': name.trim(),
        'p_class_id': classId,
        'p_timer_min': timerMin,
        'p_break_min': breakMin,
        'p_max_members': maxMembers,
      },
    );
    return StudyRoom.fromMap(res as Map<String, dynamic>);
  }

  /// Joins an open room by its 6-character code. Joining a room you're already
  /// in is a no-op that returns the room, so the lobby's Join button uses this
  /// too.
  Future<StudyRoom> joinRoomByCode(String code) async {
    final res = await db.rpc(
      'join_room_by_code',
      params: {'p_code': code.trim().toUpperCase()},
    );
    return StudyRoom.fromMap(res as Map<String, dynamic>);
  }

  /// Leaves a room. When the host leaves, or the last member does, a trigger
  /// closes the room.
  Future<void> leaveRoom(String roomId) async {
    final uid = currentUserId;
    if (uid == null) return;
    await db
        .from('room_members')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', uid);
  }

  /// Host closes the room.
  Future<void> closeRoom(String roomId) async {
    await db.rpc('close_study_room', params: {'p_room_id': roomId});
  }

  /// Members with display names. Profiles are owner-only, so names come from
  /// `get_room_members`, which checks the caller is in the room.
  Future<List<RoomMember>> getMembers(String roomId) async {
    final rows = await db.rpc(
      'get_room_members',
      params: {'p_room_id': roomId},
    );
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((m) => RoomMember.fromMap(m, roomId: roomId))
        .toList();
  }

  /// The most recent [limit] messages, oldest first.
  Future<List<RoomMessage>> getMessages(String roomId, {int limit = 50}) async {
    final rows = await db
        .from('room_messages')
        .select('id, room_id, user_id, body, created_at')
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(RoomMessage.fromMap).toList().reversed.toList();
  }

  /// Saves a message under a client-chosen [id], so the optimistic bubble and
  /// the realtime echo of this insert carry the same id and de-duplicate.
  Future<RoomMessage> sendMessage(
    String roomId,
    String body, {
    required String id,
  }) async {
    final row = await db
        .from('room_messages')
        .insert({
          'id': id,
          'room_id': roomId,
          'user_id': requireUserId,
          'body': body.trim(),
        })
        .select('id, room_id, user_id, body, created_at')
        .single();
    return RoomMessage.fromMap(row);
  }

  // ── Focus length and group quizzes (0019_room_quiz.sql) ──

  /// Host only: the room's focus and break lengths. They live on the room, so
  /// someone who joins later gets the same ones.
  Future<void> setTimer(
    String roomId, {
    required int focusMin,
    required int breakMin,
  }) async {
    await db.rpc('set_room_timer', params: {
      'p_room': roomId,
      'p_focus_min': focusMin,
      'p_break_min': breakMin,
    });
  }

  /// Host only: writes the questions from one of the host's materials and
  /// invites everyone in the room. Returns the new quiz's id.
  Future<String> proposeQuiz({
    required String roomId,
    required String materialId,
    required int count,
    bool speed = false,
    int seconds = 20,
  }) async {
    // A FunctionException carries the function's own message ("Only the host
    // can start a group quiz."); friendlyError reads it out.
    final res = await db.functions.invoke('room-quiz', body: {
      'roomId': roomId,
      'materialId': materialId,
      'count': count,
      if (speed) ...{'mode': 'speed', 'seconds': seconds},
    });
    final data = res.data;
    if (data is Map && data['quizId'] is String) return data['quizId'] as String;
    throw "Couldn't start the quiz. Try again.";
  }

  /// The quiz going on in a room, or one that ended in the last hour.
  Future<RoomQuiz?> getActiveQuiz(String roomId) async {
    final res = await db.rpc('get_active_room_quiz', params: {'p_room': roomId});
    return res is Map ? RoomQuiz.fromMap(Map<String, dynamic>.from(res)) : null;
  }

  Future<RoomQuiz> getQuiz(String quizId) =>
      _quizCall('get_room_quiz', {'p_quiz': quizId});

  /// One "no" cancels the quiz; the last "yes" starts it.
  Future<RoomQuiz> voteQuiz(String quizId, bool agree) =>
      _quizCall('vote_room_quiz', {'p_quiz': quizId, 'p_agree': agree});

  /// Hands in [picks] (question id → option index). Marked on the server.
  Future<RoomQuiz> submitQuiz(String quizId, Map<String, int> picks) =>
      _quizCall('submit_room_quiz', {'p_quiz': quizId, 'p_picks': picks});

  /// Speed round: one answer, inside that question's window.
  Future<RoomQuiz> answerSpeed(String quizId, String questionId, int pick) =>
      _quizCall('answer_room_quiz_question', {
        'p_quiz': quizId,
        'p_question': questionId,
        'p_pick': pick,
      });

  /// Speed round: closes it once its clock has run out. Harmless too early.
  Future<RoomQuiz> tickQuiz(String quizId) =>
      _quizCall('tick_room_quiz', {'p_quiz': quizId});

  /// Host only: cancels a vote, or finishes a running quiz for whoever has
  /// handed in.
  Future<RoomQuiz> endQuiz(String quizId) =>
      _quizCall('end_room_quiz', {'p_quiz': quizId});

  Future<RoomQuiz> _quizCall(String fn, Map<String, dynamic> params) async {
    final res = await db.rpc(fn, params: params);
    return RoomQuiz.fromMap(Map<String, dynamic>.from(res as Map));
  }

  // ── Shared materials and history (0030_room_materials_history.sql) ──

  /// What members have shared into [roomId], newest first.
  Future<List<RoomSharedMaterial>> getSharedMaterials(String roomId) async {
    final rows = await db.rpc('get_room_materials', params: {'p_room': roomId});
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(RoomSharedMaterial.fromMap)
        .toList();
  }

  /// Shares one of the caller's own ready materials into the room.
  Future<void> shareMaterial(String roomId, String materialId) async {
    await db.rpc('share_room_material', params: {
      'p_room': roomId,
      'p_material': materialId,
    });
  }

  /// Whoever shared it, or the host, takes it out of the room.
  Future<void> unshareMaterial(String shareId) async {
    await db.rpc('unshare_room_material', params: {'p_share': shareId});
  }

  /// Copies a shared material into the caller's library: the file into their
  /// own folder here (`0030` lets room-mates read it), then the row and its
  /// already-embedded chunks on the server, so it's ready without another
  /// Gemini pass. If the server refuses, the copied file is removed again,
  /// like [MaterialRepository.uploadFile]'s cleanup.
  Future<StudyMaterial> saveSharedMaterial(RoomSharedMaterial share) async {
    final source = share.storagePath;
    if (source == null) throw "That material has no file to copy.";
    final bucket = db.storage.from(SupabaseConfig.materialsBucket);
    final bytes = await bucket.download(source);
    final name = source.split('/').last.replaceFirst(RegExp(r'^\d+_'), '');
    final path =
        '$requireUserId/${DateTime.now().millisecondsSinceEpoch}_$name';
    await bucket.uploadBinary(path, bytes);
    try {
      final row = await db.rpc('save_room_material', params: {
        'p_share': share.id,
        'p_path': path,
      });
      return StudyMaterial.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (_) {
      try {
        await bucket.remove([path]);
      } catch (_) {
        // Swallowed deliberately — the save error is the one worth seeing.
      }
      rethrow;
    }
  }

  /// Rooms the caller created or joined, most recent first.
  Future<List<RoomHistoryEntry>> getHistory({int limit = 50}) async {
    final rows = await db.rpc('get_room_history', params: {'p_limit': limit});
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(RoomHistoryEntry.fromMap)
        .toList();
  }

  /// The group quizzes the caller finished in [roomId].
  Future<List<RoomQuizResult>> getQuizHistory(String roomId) async {
    final rows =
        await db.rpc('get_room_quiz_history', params: {'p_room': roomId});
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(RoomQuizResult.fromMap)
        .toList();
  }

  /// Takes a room out of the caller's history, and with it their access to
  /// what was shared there once they've left. Joining again brings it back.
  Future<void> removeFromHistory(String roomId) async {
    await db
        .from('room_history')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', requireUserId);
  }

  // ── Moderation (0013_room_moderation.sql) ──

  /// Everyone this student has blocked. Their messages are hidden everywhere.
  Future<Set<String>> getBlockedIds() async {
    final rows = await db.from('user_blocks').select('blocked_id');
    return {for (final r in rows) r['blocked_id'] as String};
  }

  Future<void> block(String userId) async {
    await db.from('user_blocks').upsert(
      {'blocker_id': requireUserId, 'blocked_id': userId},
      onConflict: 'blocker_id,blocked_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> unblock(String userId) async {
    await db
        .from('user_blocks')
        .delete()
        .eq('blocker_id', requireUserId)
        .eq('blocked_id', userId);
  }

  /// Files a report for review in the dashboard. [reason] is one of `spam`,
  /// `harassment`, `inappropriate`, `other`.
  Future<void> report({
    required String roomId,
    required String userId,
    required String reason,
    String? messageId,
    String? details,
  }) async {
    await db.rpc('report_room_user', params: {
      'p_room_id': roomId,
      'p_reported_id': userId,
      'p_reason': reason,
      'p_message_id': messageId,
      'p_details': details,
    });
  }

  /// Host only: takes [userId] out of the room; they can't rejoin it.
  Future<void> removeMember(String roomId, String userId) async {
    await db.rpc('remove_room_member', params: {
      'p_room_id': roomId,
      'p_user_id': userId,
    });
  }

  /// A private channel: `0020_hardening.sql` lets only the room's members join
  /// it, hear its broadcasts and presence, or send on it.
  RealtimeChannel createRoomChannel(String roomId) => db.channel(
        'room:$roomId',
        opts: const RealtimeChannelConfig(private: true),
      );

  Future<void> removeRoomChannel(RealtimeChannel channel) =>
      db.removeChannel(channel);

  /// Random (v4) UUID for a message id. No uuid package in this app, and this
  /// is the only place that needs one.
  static String newMessageId() {
    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}
