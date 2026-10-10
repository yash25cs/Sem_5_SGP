import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../models/models.dart';
import '../supabase_client.dart';

/// Uploads syllabi/notes to private Storage and tracks them in `materials`.
class MaterialRepository {
  const MaterialRepository();

  Future<List<StudyMaterial>> getMaterials({String? goalId}) async {
    var query = db.from('materials').select();
    if (goalId != null) query = query.eq('goal_id', goalId);
    final rows = await query.order('created_at', ascending: false);
    return rows.map(StudyMaterial.fromMap).toList();
  }

  Future<StudyMaterial?> getMaterial(String id) async {
    final row =
        await db.from('materials').select().eq('id', id).maybeSingle();
    return row == null ? null : StudyMaterial.fromMap(row);
  }

  /// Uploads a picked file and records it. The object key is always
  /// `{uid}/{timestamp}_{filename}` — the Storage policies key off that first
  /// segment, so it must stay the user's id.
  ///
  /// Storage and Postgres can't share a transaction, so the row insert is
  /// wrapped in compensating cleanup: if it fails, the object just written is
  /// removed again. Without it every failed upload left a paid-for object in the
  /// bucket that nothing referenced and no screen could ever show (docs/REVIEW.md P1).
  Future<StudyMaterial> uploadFile({
    required File file,
    required String fileName,
    String? goalId,
    MaterialType sourceType = MaterialType.syllabusPdf,
    String? subjectId,
  }) async {
    final uid = requireUserId;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$uid/${stamp}_$safeName';

    await db.storage.from(SupabaseConfig.materialsBucket).upload(path, file);

    try {
      final row = await db
          .from('materials')
          .insert({
            'user_id': uid,
            'source_type': sourceType.db,
            'title': fileName,
            'storage_path': path,
            'status': IngestStatus.uploaded.db,
            'goal_id': ?goalId,
            'subject_id': ?subjectId,
          })
          .select()
          .single();
      return StudyMaterial.fromMap(row);
    } catch (_) {
      // Best-effort: if the cleanup itself fails there is nothing further the
      // client can do, and the insert error is the one worth surfacing.
      try {
        await db.storage.from(SupabaseConfig.materialsBucket).remove([path]);
      } catch (_) {
        // Swallowed deliberately — see above.
      }
      rethrow;
    }
  }

  /// Stores a YouTube video's transcript as a text file and records the video,
  /// ready for `embed-material` to read.
  ///
  /// The phone fetched the transcript because YouTube won't give captions to a
  /// server (D-037). The row is still a `video_link` — `external_url` keeps the
  /// video itself — but now with a file behind it, so retry, summarize and
  /// remove all work the way they do for notes. Same compensating cleanup as
  /// [uploadFile].
  Future<StudyMaterial> addVideoTranscript({
    required String videoId,
    required String title,
    required String transcript,
    String? playlistId,
    String? goalId,
  }) async {
    final uid = requireUserId;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$uid/${stamp}_youtube_$videoId.txt';

    await db.storage.from(SupabaseConfig.materialsBucket).uploadBinary(
          path,
          Uint8List.fromList(utf8.encode(transcript)),
          fileOptions:
              const FileOptions(contentType: 'text/plain; charset=utf-8'),
        );

    try {
      final row = await db
          .from('materials')
          .insert({
            'user_id': uid,
            'source_type': MaterialType.videoLink.db,
            'title': title,
            'storage_path': path,
            'external_url': 'https://www.youtube.com/watch?v=$videoId',
            'status': IngestStatus.uploaded.db,
            'playlist_id': ?playlistId,
            'goal_id': ?goalId,
          })
          .select()
          .single();
      return StudyMaterial.fromMap(row);
    } catch (_) {
      try {
        await db.storage.from(SupabaseConfig.materialsBucket).remove([path]);
      } catch (_) {
        // Swallowed deliberately — the insert error is the one worth seeing.
      }
      rethrow;
    }
  }

  /// Saves a syllabus typed or pasted in as a text file on [subjectId], ready
  /// for `embed-material` — which reads a `.txt` as text, splitting it at its
  /// unit headings. Same compensating cleanup as [uploadFile].
  Future<StudyMaterial> addSyllabusText({
    required String subjectId,
    required String title,
    required String text,
    String? goalId,
  }) async {
    final uid = requireUserId;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$uid/${stamp}_syllabus.txt';

    await db.storage.from(SupabaseConfig.materialsBucket).uploadBinary(
          path,
          Uint8List.fromList(utf8.encode(text)),
          fileOptions:
              const FileOptions(contentType: 'text/plain; charset=utf-8'),
        );

    try {
      final row = await db
          .from('materials')
          .insert({
            'user_id': uid,
            'source_type': MaterialType.syllabusPdf.db,
            'title': title,
            'storage_path': path,
            'status': IngestStatus.uploaded.db,
            'subject_id': subjectId,
            'goal_id': ?goalId,
          })
          .select()
          .single();
      return StudyMaterial.fromMap(row);
    } catch (_) {
      try {
        await db.storage.from(SupabaseConfig.materialsBucket).remove([path]);
      } catch (_) {
        // Swallowed deliberately — the insert error is the one worth seeing.
      }
      rethrow;
    }
  }

  /// Each subject's syllabus, by subject id — the newest one where a subject
  /// somehow has two.
  Future<Map<String, StudyMaterial>> getSyllabi() async {
    final rows = await db
        .from('materials')
        .select()
        .not('subject_id', 'is', null)
        .order('created_at', ascending: false);
    final bySubject = <String, StudyMaterial>{};
    for (final m in rows.map(StudyMaterial.fromMap)) {
      bySubject.putIfAbsent(m.subjectId!, () => m);
    }
    return bySubject;
  }

  /// The student's YouTube playlists, newest first.
  Future<List<MaterialPlaylist>> getPlaylists() async {
    final rows = await db
        .from('material_playlists')
        .select()
        .order('created_at', ascending: false);
    return rows.map(MaterialPlaylist.fromMap).toList();
  }

  /// Records a playlist and the videos it will be read from (0024, D-038).
  Future<MaterialPlaylist> createPlaylist({
    required String youtubeId,
    required String title,
    required List<String> videoIds,
  }) async {
    final row = await db
        .from('material_playlists')
        .insert({
          'user_id': requireUserId,
          'youtube_id': youtubeId,
          'title': title,
          'video_ids': videoIds,
        })
        .select()
        .single();
    return MaterialPlaylist.fromMap(row);
  }

  /// Puts every failed video of a playlist back to `uploaded` in one write, for
  /// the reader to pick up again.
  Future<void> resetFailed(String playlistId) => db
      .from('materials')
      .update({'status': IngestStatus.uploaded.db})
      .eq('playlist_id', playlistId)
      .eq('status', IngestStatus.failed.db);

  /// Replaces the playlist's skip list — the only column a student may change.
  Future<void> setSkipped(String playlistId, Set<String> skipped) =>
      db.from('material_playlists').update(
          {'skipped_ids': skipped.toList()}).eq('id', playlistId);

  /// Deletes the playlist — its video rows and their chunks go with it, by
  /// cascade — then the transcript files, which no cascade reaches. Same order
  /// and reasoning as [deleteMaterial].
  Future<void> deletePlaylist(
    MaterialPlaylist playlist,
    List<String> storagePaths,
  ) async {
    await db.from('material_playlists').delete().eq('id', playlist.id);
    for (var i = 0; i < storagePaths.length; i += 100) {
      final end = i + 100 < storagePaths.length ? i + 100 : storagePaths.length;
      await db.storage
          .from(SupabaseConfig.materialsBucket)
          .remove(storagePaths.sublist(i, end));
    }
  }

  /// Records a link with nothing behind it — an article or a lecture page the
  /// app has no way to read, kept as a bookmark.
  Future<StudyMaterial> addLink({
    required String url,
    String? title,
    String? goalId,
  }) async {
    final row = await db
        .from('materials')
        .insert({
          'user_id': requireUserId,
          'source_type': MaterialType.videoLink.db,
          'title': title ?? url,
          'external_url': url,
          'status': IngestStatus.uploaded.db,
          'goal_id': ?goalId,
        })
        .select()
        .single();
    return StudyMaterial.fromMap(row);
  }

  /// Emits whenever this material's row changes.
  ///
  /// Unused: no migration adds `materials` to the `supabase_realtime`
  /// publication, so this stream would never emit a change. [requestIngest]
  /// awaits the function and the caller refetches instead. Kept because turning
  /// it on is one line of SQL away.
  Stream<StudyMaterial> watchMaterial(String id) {
    return db
        .from('materials')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) => StudyMaterial.fromMap(rows.first));
  }

  /// Asks the `embed-material` Edge Function to read this material and store its
  /// embedded chunks. Returns how many chunks it wrote.
  ///
  /// Awaited rather than fired and forgotten: a syllabus PDF takes a few seconds
  /// and the caller needs the final status to show. The function itself sets
  /// `processing` → `embedded`/`failed`, so this only has to handle the cases it
  /// couldn't reach.
  Future<int> requestIngest(String materialId) async {
    try {
      final res = await db.functions.invoke(
        'embed-material',
        body: {'materialId': materialId},
      );
      final data = res.data;
      if (data is Map && data['chunks'] is int) return data['chunks'] as int;
      return 0;
    } on FunctionException catch (e) {
      // A 404 is almost always "not deployed yet" — nothing ran, so nothing
      // marked the row. Any other status means the function answered: a 4xx is
      // it refusing the material and deliberately leaving `status` alone, a 5xx
      // means it already marked the row `failed` on its way out.
      if (e.status == 404) await _markFailedQuietly(materialId);
      rethrow;
    } catch (_) {
      // Never reached the function at all — no network, no session. A function
      // that never ran can't mark its own failure.
      await _markFailedQuietly(materialId);
      rethrow;
    }
  }

  /// Resets a failed material and asks for ingestion again — the Retry action.
  Future<int> reingest(String materialId) async {
    await retryIngest(materialId);
    return requestIngest(materialId);
  }

  /// [markIngestFailed] without letting its own failure replace the real error.
  Future<void> _markFailedQuietly(String materialId) async {
    try {
      await markIngestFailed(materialId);
    } catch (_) {
      // The invocation error is the one worth surfacing.
    }
  }

  /// Records that ingestion didn't happen, so the row reads as retryable rather
  /// than sitting on `uploaded` looking like it's still queued.
  ///
  /// Called when the `embed-material` invocation itself fails — a function that
  /// never ran can't mark its own failure.
  Future<void> markIngestFailed(String materialId) =>
      _setStatus(materialId, IngestStatus.failed);

  /// Puts a failed material back in the queue. The caller re-invokes
  /// `embed-material` afterwards; this only resets the row the UI reads.
  ///
  /// `embedded` is deliberately not settable from here — 0009_atomicity.sql has
  /// a trigger that rejects it unless embedded chunks actually exist.
  Future<StudyMaterial> retryIngest(String materialId) =>
      _setStatus(materialId, IngestStatus.uploaded);

  Future<StudyMaterial> _setStatus(String id, IngestStatus status) async {
    final row = await db
        .from('materials')
        .update({'status': status.db})
        .eq('id', id)
        .select()
        .single();
    return StudyMaterial.fromMap(row);
  }

  /// Deletes the row first, then the object.
  ///
  /// That order matters: a row whose object is already gone breaks preview and
  /// re-ingestion with no way for the student to clear it, whereas an object
  /// whose row is gone is invisible and costs only storage. If the two can't
  /// both succeed, leave the recoverable failure.
  Future<void> deleteMaterial(StudyMaterial material) async {
    await db.from('materials').delete().eq('id', material.id);

    final path = material.storagePath;
    if (path != null) {
      await db.storage.from(SupabaseConfig.materialsBucket).remove([path]);
    }
  }

  /// Asks the `summarize-material` Edge Function to summarize this material
  /// into bullet points. Returns the summary text.
  Future<String> requestSummary(String materialId) async {
    final res = await db.functions.invoke(
      'summarize-material',
      body: {'materialId': materialId},
    );
    final data = res.data;
    if (data is Map && data['summary'] is String) {
      return data['summary'] as String;
    }
    throw 'The summary came back empty. Try again.';
  }

  /// Asks the `delete-account` Edge Function to permanently delete all of the
  /// signed-in user's data — materials, goals, progress, and the auth account.
  Future<void> deleteAccount() async {
    await db.functions.invoke('delete-account');
  }
}
