// The chat's starter questions read the student's ready files and their unit
// headings through the same queries as ChatRepository.getStarterSources —
// checked here against the hosted project with a throwaway account that
// deletes itself.
//
//   STUDYTRAIL_LIVE=1 flutter test test/live

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/state/chat_starters.dart';

final _live = Platform.environment['STUDYTRAIL_LIVE'] == '1' &&
    File('dart_define.json').existsSync();

void main() {
  test(
    'starters come from the uploaded file and its units',
    () async {
      final cfg =
          jsonDecode(File('dart_define.json').readAsStringSync()) as Map;
      final c = SupabaseClient(
          (cfg['SUPABASE_URL'] as String).replaceAll(RegExp(r'/+$'), ''),
          cfg['SUPABASE_ANON_KEY'] as String,
          authOptions:
              const AuthClientOptions(authFlowType: AuthFlowType.implicit));
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await c.auth.signUp(
          email: 'live.starters.$stamp@studytrail.test',
          password: 'Live-$stamp-x!');
      try {
        final uid = c.auth.currentUser!.id;
        final path = '$uid/${stamp}_DBMS_notes.txt';
        await c.storage.from('materials').uploadBinary(
            path,
            utf8.encode('Unit 1: Normalisation\nFirst normal form removes '
                'repeating groups. Second normal form removes partial '
                'dependencies.\n\nUnit 2: Transactions\nA transaction is atomic, '
                'consistent, isolated and durable.'),
            fileOptions: const FileOptions(contentType: 'text/plain'));
        final mat = await c
            .from('materials')
            .insert({
              'user_id': uid,
              'source_type': 'notes',
              'title': 'DBMS_notes.txt',
              'storage_path': path,
            })
            .select()
            .single();
        await c.functions
            .invoke('embed-material', body: {'materialId': mat['id']});

        // The same two reads as ChatRepository.getStarterSources.
        final mats = await c
            .from('materials')
            .select('id, title, storage_path, external_url')
            .eq('status', 'embedded')
            .order('created_at', ascending: false)
            .limit(20);
        final chunks = await c
            .from('material_chunks')
            .select('material_id, unit_label')
            .not('unit_label', 'is', null)
            .order('chunk_index', ascending: true)
            .limit(1000);
        expect(mats, hasLength(1));
        final units = [for (final r in chunks) r['unit_label'] as String];
        expect(units.join(' '), contains('Normalisation'));

        final starters = buildChatStarters(sources: [
          StarterSource(title: mats.first['title'] as String, units: units),
        ]);
        final prompts = starters.map((s) => s.prompt).join('\n');
        // ignore: avoid_print
        print(starters.map((s) => '${s.label}  →  ${s.prompt}').join('\n'));
        expect(prompts, contains('DBMS notes'));
        expect(prompts, anyOf(contains('Normalisation'), contains('Transactions')));
      } finally {
        try {
          await c.functions.invoke('delete-account');
        } catch (_) {}
        await c.dispose();
      }
    },
    skip: _live
        ? false
        : 'Live: run with STUDYTRAIL_LIVE=1 (needs dart_define.json).',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
