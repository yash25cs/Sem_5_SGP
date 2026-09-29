import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/models.dart';
import '../supabase_client.dart';

/// Manages database access and realtime channels for Study Buddy Rooms.
class RoomRepository {
  const RoomRepository();

  /// Fetches active rooms, prioritizing class rooms if [classId] is provided.
  Future<List<StudyRoom>> getActiveRooms({String? classId}) async {
    try {
      var query = db
          .from('study_rooms')
          .select('*, room_members(id)')
          .eq('status', 'active');

      if (classId != null) {
        query = query.or('class_id.eq.$classId,class_id.is.null');
      }

      final rows = await query.order('created_at', ascending: false);
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(StudyRoom.fromMap)
          .toList();
    } catch (_) {
      // Fallback: If table doesn't exist yet or query fails, return empty list
      return const [];
    }
  }

  /// Creates a study room and automatically enrolls the creator as host.
  Future<StudyRoom> createRoom({
    required String name,
    String? classId,
    int timerMin = 25,
    int breakMin = 5,
    int maxMembers = 10,
  }) async {
    final uid = requireUserId;

    // Try calling the RPC first for atomic creation + host assignment
    try {
      final res = await db.rpc('create_study_room', params: {
        'p_name': name.trim(),
        'p_class_id': classId,
        'p_timer_min': timerMin,
        'p_break_min': breakMin,
        'p_max_members': maxMembers,
      });
      if (res is Map<String, dynamic>) {
        return StudyRoom.fromMap(res);
      }
    } catch (e) {
      // If RPC doesn't exist, fallback to direct table inserts
      final row = await db
          .from('study_rooms')
          .insert({
            'name': name.trim(),
            'created_by': uid,
            'class_id': classId,
            'timer_duration_min': timerMin,
            'break_duration_min': breakMin,
            'max_members': maxMembers,
          })
          .select('*, room_members(id)')
          .single();

      final room = StudyRoom.fromMap(row);

      // Add self as host
      await db.from('room_members').insert({
        'room_id': room.id,
        'user_id': uid,
        'role': 'host',
      });

      return room;
    }

    throw StateError('Failed to create room.');
  }

  /// Joins an existing active room via its 6-character invite code.
  Future<StudyRoom> joinRoomByCode(String code) async {
    final cleanCode = code.trim().toUpperCase();

    try {
      final res = await db.rpc('join_room_by_code', params: {
        'p_code': cleanCode,
      });
      if (res is Map<String, dynamic>) {
        return StudyRoom.fromMap(res);
      }
    } catch (e) {
      // Direct query fallback
      final roomRow = await db
          .from('study_rooms')
          .select('*, room_members(id)')
          .ilike('invite_code', cleanCode)
          .eq('status', 'active')
          .single();

      final room = StudyRoom.fromMap(roomRow);
      await joinRoom(room.id);
      return room;
    }

    throw StateError('Could not join room with code $cleanCode');
  }

  /// Joins a room by its unique ID.
  Future<void> joinRoom(String roomId) async {
    final uid = requireUserId;
    await db.from('room_members').upsert({
      'room_id': roomId,
      'user_id': uid,
      'role': 'member',
    }, onConflict: 'room_id,user_id');
  }

  /// Leaves a room (removes user from `room_members`).
  Future<void> leaveRoom(String roomId) async {
    final uid = currentUserId;
    if (uid == null) return;
    await db
        .from('room_members')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', uid);
  }

  /// Host closes the study room.
  Future<void> closeRoom(String roomId) async {
    try {
      await db.rpc('close_study_room', params: {'p_room_id': roomId});
    } catch (_) {
      await db
          .from('study_rooms')
          .update({'status': 'closed'})
          .eq('id', roomId)
          .eq('created_by', requireUserId);
    }
  }

  /// Gets members in a room with their profile details.
  Future<List<RoomMember>> getMembers(String roomId) async {
    try {
      final rows = await db
          .from('room_members')
          .select('*, profiles(full_name, avatar_initial)')
          .eq('room_id', roomId)
          .order('joined_at', ascending: true);

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(RoomMember.fromMap)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetches recent chat messages for a room.
  Future<List<RoomMessage>> getMessages(String roomId, {int limit = 50}) async {
    try {
      final rows = await db
          .from('room_messages')
          .select('*, profiles(full_name, avatar_initial)')
          .eq('room_id', roomId)
          .order('created_at', ascending: false)
          .limit(limit);

      final list = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(RoomMessage.fromMap)
          .toList();

      // Return chronological order
      return list.reversed.toList();
    } catch (_) {
      return const [];
    }
  }

  /// Sends a text message to the room.
  Future<RoomMessage> sendMessage(String roomId, String body) async {
    final uid = requireUserId;
    final row = await db
        .from('room_messages')
        .insert({
          'room_id': roomId,
          'user_id': uid,
          'body': body.trim(),
        })
        .select('*, profiles(full_name, avatar_initial)')
        .single();

    return RoomMessage.fromMap(row);
  }

  /// Creates and connects a RealtimeChannel for the specified room.
  RealtimeChannel createRoomChannel(String roomId) {
    return db.channel('room:$roomId');
  }

  /// Drops and unsubscribes a RealtimeChannel.
  Future<void> removeRoomChannel(RealtimeChannel channel) async {
    await db.removeChannel(channel);
  }
}
