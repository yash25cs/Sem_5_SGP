import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Open rooms, newest first: the caller's class rooms plus unscoped ones.
  Future<List<StudyRoom>> getActiveRooms({String? classId}) async {
    final since = DateTime.now().toUtc().subtract(staleAfter).toIso8601String();
    var query = db
        .from('study_rooms')
        .select('*, room_members(user_id)')
        .eq('status', 'active')
        .gte('created_at', since);

    query = classId != null
        ? query.or('class_id.eq.$classId,class_id.is.null')
        : query.isFilter('class_id', null);

    final rows = await query.order('created_at', ascending: false);
    return rows.map(StudyRoom.fromMap).toList();
  }

  /// Creates a room and enrols the caller as host, atomically.
  Future<StudyRoom> createRoom({
    required String name,
    String? classId,
    int timerMin = 25,
    int breakMin = 5,
    int maxMembers = 10,
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

  RealtimeChannel createRoomChannel(String roomId) =>
      db.channel('room:$roomId');

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
