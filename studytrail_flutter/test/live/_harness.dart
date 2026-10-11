// Shared set-up for the live end-to-end tests: throwaway students on the
// hosted project, signed up through the real auth API and deleted (through
// the app's own delete-account function) when the file finishes.
//
// [Student.use] points the app's `db` at that student's client, so the real
// repositories — the same code the app runs — do the work.
//
// Skipped unless asked for:  STUDYTRAIL_LIVE=1 flutter test test/live

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:studytrail_flutter/data/supabase_client.dart';

final bool liveEnabled = Platform.environment['STUDYTRAIL_LIVE'] == '1' &&
    File('dart_define.json').existsSync();

/// Pass to `skip:` on every live test.
final Object liveSkip = liveEnabled
    ? false
    : 'Live: run with STUDYTRAIL_LIVE=1 (needs dart_define.json).';

late final String _url;
late final String _key;
var _configured = false;

void _configure() {
  if (_configured) return;
  final cfg = jsonDecode(File('dart_define.json').readAsStringSync()) as Map;
  _url = (cfg['SUPABASE_URL'] as String).replaceAll(RegExp(r'/+$'), '');
  _key = cfg['SUPABASE_ANON_KEY'] as String;
  _configured = true;
}

final _students = <Student>[];

class Student {
  Student._(this.client, this.email, this.password);

  final SupabaseClient client;
  final String email;
  final String password;

  String get id => client.auth.currentUser!.id;

  /// A fresh account with a session (email confirmation is off on the
  /// project). [name] goes to the profile the signup trigger creates.
  static Future<Student> create(String tag, {String? name}) async {
    _configure();
    final c = SupabaseClient(_url, _key,
        authOptions:
            const AuthClientOptions(authFlowType: AuthFlowType.implicit));
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final email = 'live.e2e.$tag.$stamp@studytrail.test';
    final password = 'Live-$stamp-x!';
    final res = await c.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name ?? 'Live ${tag[0].toUpperCase()}${tag.substring(1)}'},
    );
    if (res.session == null) {
      throw StateError('No session from sign-up: is email confirmation on?');
    }
    final s = Student._(c, email, password);
    _students.add(s);
    return s;
  }

  /// The app's repositories now act as this student.
  void use() => debugClientOverride = client;

  /// A client with no session at all — what an attacker without an account has.
  static SupabaseClient anonymous() {
    _configure();
    return SupabaseClient(_url, _key);
  }
}

/// Deletes every student this file created (their data cascades). Call from
/// `tearDownAll`.
Future<void> deleteStudents() async {
  for (final s in _students) {
    try {
      await s.client.functions.invoke('delete-account');
    } catch (_) {}
    await s.client.dispose();
  }
  _students.clear();
  debugClientOverride = null;
}

/// Notes with clear unit headings, so chunks get unit labels.
const dbmsNotes = '''Unit 1: Normalisation
Normalisation organises a relational database to reduce redundancy and update
anomalies. First normal form (1NF) requires atomic values and no repeating
groups. Second normal form (2NF) removes partial dependencies of non-key
attributes on part of a composite key. Third normal form (3NF) removes
transitive dependencies: a non-key attribute must not depend on another
non-key attribute. Boyce-Codd normal form (BCNF) requires that every
determinant is a candidate key.

Unit 2: Transactions
A transaction is a unit of work that is atomic, consistent, isolated and
durable (ACID). Concurrent schedules must be serialisable. Two-phase locking
has a growing phase and a shrinking phase and guarantees conflict
serialisability. A deadlock happens when transactions wait on each other in a
cycle; it is detected with a wait-for graph and broken by aborting a victim.

Unit 3: Indexing
An index speeds up lookups at the cost of extra storage and slower writes. A
B+ tree index keeps keys sorted in balanced leaf pages linked for range scans.
A hash index gives constant-time equality lookups but cannot do range queries.
''';

/// Writes [text] to a temp file and returns it, for the upload paths that take
/// a `File` (as the app's picker hands them one).
Future<File> tempFile(String name, List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('studytrail_live');
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  await f.writeAsBytes(bytes);
  return f;
}

/// A minimal, valid one-page PDF with [lines] of text — enough for Gemini to
/// read, and the real file type the app's PDF paths expect.
Uint8List simplePdf(List<String> lines) {
  String esc(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
  final content = StringBuffer('BT /F1 11 Tf 50 790 Td 14 TL\n');
  for (final l in lines) {
    content.write('(${esc(l)}) Tj T*\n');
  }
  content.write('ET');
  final stream = content.toString();
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${latin1.encode(stream).length} >>\nstream\n$stream\nendstream',
  ];
  final out = BytesBuilder();
  void w(String s) => out.add(latin1.encode(s));
  w('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    w('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  w('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    w('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  w('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return out.toBytes();
}

/// Expects [call] to fail; returns the error text for asserting on.
Future<String> refused(Future<Object?> Function() call) async {
  try {
    final r = await call();
    throw _NotRefused('Expected a refusal, got: $r');
  } on _NotRefused {
    rethrow;
  } catch (e) {
    return e.toString();
  }
}

class _NotRefused implements Exception {
  _NotRefused(this.message);
  final String message;
  @override
  String toString() => message;
}
