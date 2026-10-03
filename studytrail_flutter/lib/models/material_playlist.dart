/// A row of `material_playlists` — a YouTube playlist in the library.
///
/// It takes one of the library's slots however many videos it has (D-038).
/// Its videos are ordinary `video_link` materials whose `playlistId` points
/// here; this row holds the list they're read from, so an import the phone
/// couldn't finish can carry on later.
class MaterialPlaylist {
  const MaterialPlaylist({
    required this.id,
    required this.youtubeId,
    required this.title,
    required this.videoIds,
    this.skippedIds = const {},
    this.createdAt,
  });

  final String id;
  final String youtubeId;
  final String title;

  /// The playlist's videos in order, as listed when it was added (at most 100).
  final List<String> videoIds;

  /// Videos that won't be read: no captions, unavailable, or removed by the
  /// student.
  final Set<String> skippedIds;
  final DateTime? createdAt;

  String get url => 'https://www.youtube.com/playlist?list=$youtubeId';

  MaterialPlaylist withSkipped(Set<String> skipped) => MaterialPlaylist(
        id: id,
        youtubeId: youtubeId,
        title: title,
        videoIds: videoIds,
        skippedIds: skipped,
        createdAt: createdAt,
      );

  factory MaterialPlaylist.fromMap(Map<String, dynamic> m) => MaterialPlaylist(
        id: m['id'] as String,
        youtubeId: m['youtube_id'] as String,
        title: m['title'] as String,
        videoIds: [
          for (final v in (m['video_ids'] as List? ?? const [])) v as String,
        ],
        skippedIds: {
          for (final v in (m['skipped_ids'] as List? ?? const [])) v as String,
        },
        createdAt: m['created_at'] == null
            ? null
            : DateTime.parse(m['created_at'] as String),
      );
}
