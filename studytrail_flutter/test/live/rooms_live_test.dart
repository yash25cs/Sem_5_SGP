// Two real accounts in one study room, against the hosted project — the part
// of rooms a widget test can't reach: the private Realtime channel, presence,
// broadcasts and the chat echo travelling from one client to another.
//
// Skipped unless asked for, because it signs up throwaway accounts on the live
// project (they delete themselves at the end):
//
//   STUDYTRAIL_LIVE=1 flutter test test/live
//
// Reads the project URL and anon key from the gitignored dart_define.json.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _live = Platform.environment['STUDYTRAIL_LIVE'] == '1' &&
    File('dart_define.json').existsSync();

void main() {
  late String url;
  late String key;
  final clients = <SupabaseClient>[];

  Future<SupabaseClient> account(String tag) async {
    // Implicit flow: a bare client has no storage for a PKCE verifier.
    final c = SupabaseClient(url, key,
        authOptions:
            const AuthClientOptions(authFlowType: AuthFlowType.implicit));
    clients.add(c);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final res = await c.auth.signUp(
      email: 'live.$tag.$stamp@studytrail.test',
      password: 'Live-$stamp-x!',
      data: {'full_name': 'Live $tag'},
    );
    expect(res.session, isNotNull,
        reason: 'Email confirmation must be off for the live test.');
    return c;
  }

  /// Subscribes the way RoomRepository.createRoomChannel does, and reports
  /// how the join ended.
  Future<(RealtimeChannel, RealtimeSubscribeStatus)> join(
    SupabaseClient c,
    String roomId, {
    void Function(RealtimeChannel)? listen,
    bool private = true,
  }) async {
    final ch = c.channel('room:$roomId',
        opts: RealtimeChannelConfig(private: private));
    listen?.call(ch);
    final done = Completer<RealtimeSubscribeStatus>();
    ch.subscribe((status, _) {
      if (status != RealtimeSubscribeStatus.subscribed &&
          status != RealtimeSubscribeStatus.channelError &&
          status != RealtimeSubscribeStatus.timedOut) {
        return;
      }
      if (!done.isCompleted) done.complete(status);
    });
    final status =
        await done.future.timeout(const Duration(seconds: 15), onTimeout: () {
      return RealtimeSubscribeStatus.timedOut;
    });
    return (ch, status);
  }

  Map<String, dynamic> unwrap(Map<String, dynamic> m) =>
      m['payload'] is Map ? Map<String, dynamic>.from(m['payload']) : m;

  setUpAll(() {
    if (!_live) return;
    final cfg = jsonDecode(File('dart_define.json').readAsStringSync()) as Map;
    url = (cfg['SUPABASE_URL'] as String).replaceAll(RegExp(r'/+$'), '');
    key = cfg['SUPABASE_ANON_KEY'] as String;
  });

  tearDownAll(() async {
    for (final c in clients) {
      try {
        await c.functions.invoke('delete-account');
      } catch (_) {}
      await c.dispose();
    }
  });

  test(
    'two phones share one room: private channel, timer, presence, chat, quiz ping',
    () async {
      final host = await account('host');
      final member = await account('member');
      final outsider = await account('out');

      final room = await host.rpc('create_study_room',
          params: {'p_name': 'Live test', 'p_max_members': 2}) as Map;
      final roomId = room['id'] as String;
      await member
          .rpc('join_room_by_code', params: {'p_code': room['invite_code']});

      final timer = Completer<Map<String, dynamic>>();
      final quizPing = Completer<Map<String, dynamic>>();
      final chat = Completer<Map<String, dynamic>>();
      final hostSeen = Completer<void>();

      final (memberCh, memberStatus) = await join(member, roomId, listen: (ch) {
        ch
          ..onBroadcast(
              event: 'timer',
              callback: (m) {
                if (!timer.isCompleted) timer.complete(unwrap(m));
              })
          ..onBroadcast(
              event: 'quiz',
              callback: (m) {
                if (!quizPing.isCompleted) quizPing.complete(unwrap(m));
              })
          ..onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'room_messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'room_id',
                value: roomId,
              ),
              callback: (p) {
                if (!chat.isCompleted) chat.complete(p.newRecord);
              })
          ..onPresenceSync((_) {
            final present = ch
                .presenceState()
                .expand((s) => s.presences)
                .any((p) => p.payload['user_id'] == host.auth.currentUser!.id);
            if (present && !hostSeen.isCompleted) hostSeen.complete();
          });
      });
      expect(memberStatus, RealtimeSubscribeStatus.subscribed,
          reason: 'a member joins the private room channel');

      final (hostCh, hostStatus) = await join(host, roomId);
      expect(hostStatus, RealtimeSubscribeStatus.subscribed);

      final (_, outsiderStatus) = await join(outsider, roomId);
      expect(outsiderStatus, isNot(RealtimeSubscribeStatus.subscribed),
          reason: 'someone not in the room is refused the private channel');

      // The same name as a public channel must not be a way in.
      var overheard = false;
      final (snoop, _) = await join(outsider, roomId,
          private: false,
          listen: (ch) => ch.onBroadcast(
              event: 'timer', callback: (_) => overheard = true));

      await hostCh.track({
        'user_id': host.auth.currentUser!.id,
        'full_name': 'Live host',
        'study_status': 'focusing',
      });
      await hostSeen.future.timeout(const Duration(seconds: 15));

      await hostCh.sendBroadcastMessage(event: 'timer', payload: {
        'action': 'start',
        'phase': 'focus',
        'remaining_secs': 1500,
        'total_secs': 1500,
        'running': true,
      });
      final t = await timer.future.timeout(const Duration(seconds: 15));
      expect(t['action'], 'start');
      expect(t['remaining_secs'], 1500);
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(overheard, isFalse,
          reason: "a public channel of the same name doesn't hear the room");
      await outsider.removeChannel(snoop);

      await host.from('room_messages').insert({
        'room_id': roomId,
        'user_id': host.auth.currentUser!.id,
        'body': 'Hello from the live test',
      });
      final msg = await chat.future.timeout(const Duration(seconds: 15));
      expect(msg['body'], 'Hello from the live test');

      await hostCh
          .sendBroadcastMessage(event: 'quiz', payload: {'quiz_id': 'ping'});
      final q = await quizPing.future.timeout(const Duration(seconds: 15));
      expect(q['quiz_id'], 'ping');

      await member.removeChannel(memberCh);
      await host.removeChannel(hostCh);
      await host.rpc('close_study_room', params: {'p_room_id': roomId});
    },
    skip: _live
        ? false
        : 'Live: run with STUDYTRAIL_LIVE=1 (needs dart_define.json).',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a shared material reaches the other member, who can save a copy',
    () async {
      final host = await account('sharer');
      final member = await account('saver');
      final hostId = host.auth.currentUser!.id;
      final memberId = member.auth.currentUser!.id;

      // A small ready material on the host's side, the way the app makes one.
      final path = '$hostId/${DateTime.now().millisecondsSinceEpoch}_notes.txt';
      await host.storage.from('materials').uploadBinary(
          path,
          utf8.encode('Unit 1: Optics\nA convex lens converges light to a '
              'focal point. Refraction bends light at a boundary.'),
          fileOptions: const FileOptions(contentType: 'text/plain'));
      final mat = await host
          .from('materials')
          .insert({
            'user_id': hostId,
            'source_type': 'notes',
            'title': 'Live optics notes',
            'storage_path': path,
          })
          .select()
          .single();
      await host.functions
          .invoke('embed-material', body: {'materialId': mat['id']});

      final room = await host.rpc('create_study_room',
          params: {'p_name': 'Live share', 'p_max_members': 2}) as Map;
      final roomId = room['id'] as String;
      await member
          .rpc('join_room_by_code', params: {'p_code': room['invite_code']});

      final ping = Completer<void>();
      final (memberCh, _) = await join(member, roomId,
          listen: (ch) => ch.onBroadcast(
              event: 'materials',
              callback: (_) {
                if (!ping.isCompleted) ping.complete();
              }));
      final (hostCh, _) = await join(host, roomId);

      await host.rpc('share_room_material',
          params: {'p_room': roomId, 'p_material': mat['id']});
      // Exactly what RoomStore._pingMaterials sends.
      await hostCh.sendBroadcastMessage(
          event: 'materials', payload: {'room_id': roomId});
      await ping.future.timeout(const Duration(seconds: 15));

      final list = await member
          .rpc('get_room_materials', params: {'p_room': roomId}) as List;
      expect(list, hasLength(1));
      expect(list.first['title'], 'Live optics notes');
      expect(list.first['saved'], isFalse);

      final bytes =
          await member.storage.from('materials').download(path);
      final copyPath = '$memberId/${DateTime.now().millisecondsSinceEpoch}_notes.txt';
      await member.storage.from('materials').uploadBinary(copyPath, bytes);
      final copy = await member.rpc('save_room_material',
          params: {'p_share': list.first['id'], 'p_path': copyPath}) as Map;
      expect(copy['status'], 'embedded');

      await member.removeChannel(memberCh);
      await host.removeChannel(hostCh);
      await host.rpc('close_study_room', params: {'p_room_id': roomId});
    },
    skip: _live
        ? false
        : 'Live: run with STUDYTRAIL_LIVE=1 (needs dart_define.json).',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
