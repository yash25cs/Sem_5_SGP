import 'enums.dart';

/// A row of `materials` — an uploaded syllabus/notes file or a video link.
/// Named `StudyMaterial` to avoid colliding with Flutter's `Material` widget.
class StudyMaterial {
  const StudyMaterial({
    required this.id,
    required this.sourceType,
    this.goalId,
    this.title,
    this.storagePath,
    this.externalUrl,
    this.status = IngestStatus.uploaded,
    this.createdAt,
    this.playlistId,
  });

  final String id;
  final String? goalId;
  final MaterialType sourceType;
  final String? title;

  /// Path inside the private `materials` bucket, always `{uid}/...`.
  final String? storagePath;
  final String? externalUrl;
  final IngestStatus status;
  final DateTime? createdAt;

  /// Set on a video read in as part of a YouTube playlist; the playlist, not
  /// the video, is what takes a library slot.
  final String? playlistId;

  /// File name for display, derived from the storage path.
  String get displayName {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final p = storagePath;
    if (p != null && p.contains('/')) return p.split('/').last;
    return externalUrl ?? 'Untitled';
  }

  bool get isReady => status == IngestStatus.embedded;

  /// The same material with a different ingest status.
  ///
  /// For showing "Processing…" locally while `embed-material` works — the row is
  /// read back from Postgres afterwards, which is what settles the real status.
  StudyMaterial withStatus(IngestStatus status) => StudyMaterial(
        id: id,
        sourceType: sourceType,
        goalId: goalId,
        title: title,
        storagePath: storagePath,
        externalUrl: externalUrl,
        status: status,
        createdAt: createdAt,
        playlistId: playlistId,
      );

  factory StudyMaterial.fromMap(Map<String, dynamic> m) => StudyMaterial(
        id: m['id'] as String,
        goalId: m['goal_id'] as String?,
        sourceType: MaterialType.fromDb(m['source_type'] as String?),
        title: m['title'] as String?,
        storagePath: m['storage_path'] as String?,
        externalUrl: m['external_url'] as String?,
        status: IngestStatus.fromDb(m['status'] as String?),
        createdAt: m['created_at'] == null
            ? null
            : DateTime.parse(m['created_at'] as String),
        playlistId: m['playlist_id'] as String?,
      );

  Map<String, dynamic> toInsertMap() => {
        'source_type': sourceType.db,
        if (goalId != null) 'goal_id': goalId,
        if (title != null) 'title': title,
        if (storagePath != null) 'storage_path': storagePath,
        if (externalUrl != null) 'external_url': externalUrl,
        if (playlistId != null) 'playlist_id': playlistId,
        'status': status.db,
      };
}

/// A retrieved chunk from `match_material_chunks` — backs the citation chips
/// under an AI answer.
class MaterialChunk {
  const MaterialChunk({
    required this.id,
    required this.content,
    this.materialId,
    this.subjectId,
    this.unitLabel,
    this.similarity,
  });

  final String id;
  final String content;
  final String? materialId;
  final String? subjectId;
  final String? unitLabel;
  final double? similarity;

  String get label => unitLabel ?? 'Source';

  factory MaterialChunk.fromMap(Map<String, dynamic> m) => MaterialChunk(
        id: m['id'] as String,
        content: (m['content'] as String?) ?? '',
        materialId: m['material_id'] as String?,
        subjectId: m['subject_id'] as String?,
        unitLabel: m['unit_label'] as String?,
        similarity: (m['similarity'] as num?)?.toDouble(),
      );
}
