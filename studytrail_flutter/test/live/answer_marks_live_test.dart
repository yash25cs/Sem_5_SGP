// Generated answer-practice questions are short-answer: theory 3, 4 or 6
// marks, NEP case questions 3–6 in two or three parts. Checked against the
// deployed grade-answer function with a throwaway account that deletes
// itself.
//
//   STUDYTRAIL_LIVE=1 flutter test test/live

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _live = Platform.environment['STUDYTRAIL_LIVE'] == '1' &&
    File('dart_define.json').existsSync();

void main() {
  test(
    'generated questions are worth at most 6 marks',
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
          email: 'live.marks.$stamp@studytrail.test',
          password: 'Live-$stamp-x!');
      try {
        final uid = c.auth.currentUser!.id;
        final path = '$uid/${stamp}_dbms.txt';
        await c.storage.from('materials').uploadBinary(
            path,
            utf8.encode('Unit 1: Normalisation\nFirst normal form removes '
                'repeating groups. Second normal form removes partial '
                'dependencies on a composite key. Third normal form removes '
                'transitive dependencies. BCNF requires every determinant to '
                'be a candidate key.\n\nUnit 2: Transactions\nA transaction is '
                'atomic, consistent, isolated and durable. Locks and two-phase '
                'locking keep concurrent schedules serialisable; deadlocks are '
                'detected with a wait-for graph.'),
            fileOptions: const FileOptions(contentType: 'text/plain'));
        final mat = await c
            .from('materials')
            .insert({
              'user_id': uid,
              'source_type': 'notes',
              'title': 'DBMS',
              'storage_path': path,
            })
            .select()
            .single();
        await c.functions
            .invoke('embed-material', body: {'materialId': mat['id']});

        for (final kind in ['theory', 'nep']) {
          final res = await c.functions.invoke('grade-answer', body: {
            'action': 'question',
            'count': 4,
            'kind': kind,
          });
          final qs = (res.data as Map)['questions'] as List;
          // ignore: avoid_print
          print('$kind: ${[for (final q in qs) q['marks']]}');
          expect(qs, isNotEmpty);
          for (final q in qs) {
            final marks = (q['marks'] as num).toDouble();
            expect(marks, lessThanOrEqualTo(6), reason: '$kind: $q');
            if (kind == 'theory') expect([3, 4, 6], contains(marks));
            if (kind == 'nep') expect(marks, greaterThanOrEqualTo(3));
          }
        }
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
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
