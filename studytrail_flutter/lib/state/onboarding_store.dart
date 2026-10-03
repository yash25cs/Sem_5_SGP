import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../data/repositories.dart';
import '../models/models.dart';
import '../services/youtube_service.dart';
import 'async_store.dart';

/// Backs the two onboarding steps that write data: material upload and goal
/// creation. Kept separate from [ProfileStore] because it only lives for the
/// duration of onboarding — once the goal exists the app reads through the
/// per-tab stores instead.
class OnboardingStore extends AsyncStore {
  OnboardingStore({
    MaterialRepository? materials,
    GoalRepository? goals,
    YouTubeService? youtube,
    this.busyAiCooldown = const Duration(seconds: 60),
  })  : _materials = materials ?? const MaterialRepository(),
        _goals = goals ?? const GoalRepository(),
        _youtube = youtube ?? YouTubeService();

  final MaterialRepository _materials;
  final GoalRepository _goals;
  final YouTubeService _youtube;

  /// How long the reader waits when the AI says it's busy (429).
  ///
  /// The free tier embeds about 100 chunks a minute — measured 2026-10-03: four
  /// 23-chunk videos at once went through, the fifth got a 429 — and a
  /// 92-video playlist read three at a time ran past that in its second
  /// minute, leaving 39 videos `failed`. The window is per minute, so a minute
  /// is what clears it.
  final Duration busyAiCooldown;

  /// Cooldowns in a row, with nothing read in between, before the reader
  /// decides the limit is the day's rather than the minute's and pauses.
  static const _cooldownsBeforePause = 3;

  /// How many materials one student may keep.
  ///
  /// Chosen for the free tier's actual costs, not as a round number: every file
  /// is re-read by Gemini on upload and its chunks are searched on every single
  /// question. The `chat` function returns the 6 best chunks regardless of how
  /// many exist, so past a point more files stop improving answers and only
  /// dilute retrieval — a stray page from a half-related PDF starts outranking
  /// the right unit. 20 covers a full semester's subjects with room to spare.
  ///
  /// A YouTube playlist is one item however many videos it holds (D-038): it
  /// is one course, and its videos cost only embeddings, not a Gemini read.
  static const maxMaterials = 20;

  /// The most videos read from one playlist — one page of YouTube's listing.
  static const maxPlaylistVideos = 100;

  /// Videos read at once. Each spends ~1 s on the phone and ~9 s in
  /// `embed-material`, so three at a time takes a 92-video playlist from about
  /// 18 minutes to about 6, at one embedding call per video.
  static const parallelVideos = 3;

  List<StudyMaterial> _uploaded = const [];
  List<MaterialPlaylist> _playlists = const [];
  Goal? _goal;

  /// A single video, or a playlist's listing, being fetched — short, and the
  /// add-a-link controls wait for it.
  bool _addingLink = false;
  String? _linkProgress;

  /// The background reader working through playlists' videos; null when idle.
  Future<void>? _run;
  String? _activePlaylistId;
  bool _stopRequested = false;

  /// Work arrived while the reader was past it; go round once more.
  bool _again = false;

  /// While set, no worker sends anything to the AI — see [busyAiCooldown].
  DateTime? _coolUntil;
  int _cooldownsInARow = 0;

  /// Writes of a skip list, chained so they land in order.
  Future<void> _skipWrites = Future.value();

  /// Every material, playlist videos included, newest first.
  List<StudyMaterial> get uploaded => _uploaded;

  /// Materials that aren't part of a playlist — each takes a library slot.
  List<StudyMaterial> get standalone =>
      _uploaded.where((m) => m.playlistId == null).toList();

  List<MaterialPlaylist> get playlists => _playlists;
  Goal? get createdGoal => _goal;

  /// What counts against [maxMaterials]: each file or video on its own, and
  /// each playlist once.
  int get itemCount => standalone.length + _playlists.length;
  bool get hasMaterial => itemCount > 0;

  /// Whether another item may be added. Drives the disabled state on both the
  /// onboarding drop zone and the chat sheet's add buttons.
  bool get atLimit => itemCount >= maxMaterials;

  /// Slots left before [maxMaterials] is reached.
  int get remainingSlots => (maxMaterials - itemCount).clamp(0, maxMaterials);

  /// True while a pasted link is being opened. A playlist's videos are read
  /// afterwards, in the background — see [readingPlaylists].
  bool get addingLink => _addingLink;

  /// "Opening the playlist…" while [addingLink].
  String? get linkProgress => _linkProgress;

  /// True while playlist videos are being read. Separate from [busy] and
  /// [addingLink] on purpose: it runs for minutes, the student carries on
  /// using the app, and this store outlives the screen it started on.
  bool get readingPlaylists => _run != null;

  /// The playlist whose videos are being read right now.
  String? get activePlaylistId => _activePlaylistId;

  /// Completes when the background reader has nothing left to do.
  Future<void> whenIdle() async {
    while (_run != null) {
      await _run;
    }
  }

  /// Everything that can be picked for a quiz or a deck, in library order:
  /// files first, then each playlist's videos in playlist order.
  List<StudyMaterial> get libraryOrder => [
        ...standalone,
        for (final playlist in _playlists) ...videosOf(playlist),
      ];

  /// A playlist's stored videos, in playlist order.
  List<StudyMaterial> videosOf(MaterialPlaylist playlist) {
    final order = {
      for (var i = 0; i < playlist.videoIds.length; i++)
        playlist.videoIds[i]: i,
    };
    final videos =
        _uploaded.where((m) => m.playlistId == playlist.id).toList();
    int position(StudyMaterial m) =>
        order[_videoIdOf(m)] ?? playlist.videoIds.length;
    videos.sort((a, b) => position(a).compareTo(position(b)));
    return videos;
  }

  /// Videos of [playlist] not yet stored or skipped — what the reader has
  /// left to do.
  List<String> pendingOf(MaterialPlaylist playlist) {
    final stored = {
      for (final m in _uploaded)
        if (m.playlistId == playlist.id) _videoIdOf(m),
    };
    return [
      for (final id in playlist.videoIds)
        if (!stored.contains(id) && !playlist.skippedIds.contains(id)) id,
    ];
  }

  /// Counts for a playlist's row in the library.
  PlaylistProgress progressOf(MaterialPlaylist playlist) {
    final videos = _uploaded.where((m) => m.playlistId == playlist.id);
    return PlaylistProgress(
      total: playlist.videoIds.length,
      ready: videos.where((m) => m.status == IngestStatus.embedded).length,
      failed: videos.where((m) => m.status == IngestStatus.failed).length,
      skipped: playlist.videoIds.where(playlist.skippedIds.contains).length,
      pending: pendingOf(playlist).length,
    );
  }

  static String? _videoIdOf(StudyMaterial m) {
    final url = m.externalUrl;
    return url == null ? null : YouTubeLink.parse(url)?.videoId;
  }

  Future<void> load() => runLoad(() async {
        final results = await Future.wait([
          _materials.getMaterials(),
          _materials.getPlaylists(),
        ]);
        _uploaded = results[0] as List<StudyMaterial>;
        _playlists = results[1] as List<MaterialPlaylist>;
      });

  /// Opens the system picker, uploads whatever was chosen, then asks the
  /// `embed-material` function to read each file. Returns how many files
  /// actually landed.
  ///
  /// 0 with no [error] means the user backed out, which isn't a failure and
  /// shouldn't produce a message. 0 with an error means the first file failed;
  /// a non-zero count with an error means the batch stopped partway, and those
  /// files really are stored — reporting 0 there would have told the student
  /// nothing happened while [uploaded] showed otherwise.
  Future<int> pickAndUpload(MaterialType sourceType) async {
    if (atLimit) {
      setError(
        'You already have $maxMaterials files. Remove one to add another.',
      );
      return 0;
    }

    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: sourceType == MaterialType.syllabusPdf
          ? FileType.custom
          : FileType.any,
      // Only these can be read: PDFs and photos go through Gemini's document
      // vision, .txt/.md are split locally. A .docx or .pptx would upload fine
      // and then fail ingestion, so it isn't offered.
      allowedExtensions: sourceType == MaterialType.syllabusPdf
          ? const ['pdf', 'txt', 'md', 'jpg', 'jpeg', 'png', 'webp', 'heic']
          : null,
    );
    if (result == null || result.files.isEmpty) return 0;

    // Paths are null on web; this app ships to Android, so a null path means
    // the platform couldn't materialise the file and it has to be skipped.
    final picked = result.files.where((f) => f.path != null).toList();
    if (picked.isEmpty) return 0;

    // Selecting 30 files at the picker is the easy way past the cap, so the
    // batch is trimmed here rather than refused — the first few land, and the
    // student is told the rest didn't.
    final skipped = picked.length - remainingSlots;
    final batch = skipped > 0 ? picked.take(remainingSlots).toList() : picked;

    final stored = await _storeAndIngest(
      [for (final file in batch) (path: file.path!, name: file.name)],
      sourceType,
    );

    // Set last so a real ingest failure keeps the more useful message.
    if (skipped > 0 && error == null) {
      setError(
        skipped == 1
            ? 'One file was skipped — that would pass the $maxMaterials-file '
                'limit.'
            : '$skipped files were skipped — those would pass the '
                '$maxMaterials-file limit.',
      );
    }
    return stored;
  }

  /// Photographs a page of notes (or picks a photo from the gallery) and adds
  /// it like any other file — `embed-material` reads photos with the same
  /// vision call it uses for PDFs, handwriting included. Returns 1 when it
  /// landed, 0 when cancelled or refused.
  Future<int> snapAndUpload({bool fromCamera = true}) async {
    if (atLimit) {
      setError(
        'You already have $maxMaterials files. Remove one to add another.',
      );
      return 0;
    }

    final XFile? shot;
    try {
      shot = await ImagePicker().pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        // A notes page stays legible at this size, and it keeps the upload and
        // the vision call quick on mobile data.
        maxWidth: 2400,
        imageQuality: 85,
      );
    } catch (_) {
      setError(fromCamera
          ? "Couldn't open the camera."
          : "Couldn't open your photos.");
      return 0;
    }
    if (shot == null) return 0;

    final dot = shot.path.lastIndexOf('.');
    final ext = dot < 0 ? 'jpg' : shot.path.substring(dot + 1).toLowerCase();
    return _storeAndIngest(
      [(path: shot.path, name: '${_photoTitle(DateTime.now())}.$ext')],
      MaterialType.notes,
    );
  }

  /// "Notes photo 30 Sep 14.05" — readable in the materials list, and the
  /// time keeps two photos taken the same day apart.
  static String _photoTitle(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Notes photo ${t.day} ${months[t.month - 1]} '
        '${two(t.hour)}.${two(t.minute)}';
  }

  /// Uploads each file, then asks for each to be read. Returns how many were
  /// stored.
  ///
  /// Ingestion is a second pass, outside the mutation: a file the AI can't read
  /// shouldn't make a successful upload look like it never happened. The file
  /// is stored either way — the row's status is what says whether it's
  /// searchable yet.
  Future<int> _storeAndIngest(
    List<({String path, String name})> files,
    MaterialType sourceType,
  ) async {
    var stored = 0;
    final fresh = <StudyMaterial>[];
    await runMutation(() async {
      for (final file in files) {
        final saved = await _materials.uploadFile(
          file: File(file.path),
          fileName: file.name,
          sourceType: sourceType,
        );
        _uploaded = [saved, ..._uploaded];
        fresh.add(saved);
        stored++;
      }
    });
    await _ingestAll(fresh);
    return stored;
  }

  /// Retry for a row that ended up `failed` — reset it, ask again, then show
  /// whatever it became.
  Future<bool> reingest(StudyMaterial material) async {
    _patchStatus(material.id, IngestStatus.processing);
    final ok = await runMutation(() async {
      await _materials.reingest(material.id);
    });
    await _refresh(material.id);
    return ok;
  }

  /// Asks for ingestion one file at a time, then reads back the final status.
  Future<void> _ingestAll(List<StudyMaterial> materials) async {
    Object? firstFailure;
    for (final material in materials) {
      // A bookmark link has nothing to download; the function refuses it.
      if (material.storagePath == null) continue;

      _patchStatus(material.id, IngestStatus.processing);
      try {
        await _materials.requestIngest(material.id);
      } catch (e) {
        // Per file: one unreadable PDF shouldn't abandon the rest of the batch.
        // The first reason is the one shown — a list of them helps nobody.
        firstFailure ??= e;
      }
      await _refresh(material.id);
    }
    if (firstFailure != null) setError(firstFailure);
  }

  /// Shows a status locally while the function works, so the chip doesn't sit on
  /// "Uploaded" for the several seconds a PDF takes.
  void _patchStatus(String id, IngestStatus status) {
    _uploaded = [
      for (final m in _uploaded) m.id == id ? m.withStatus(status) : m,
    ];
    notifyListeners();
  }

  /// Replaces one row with the server's copy — the authoritative status.
  Future<void> _refresh(String id) async {
    try {
      final latest = await _materials.getMaterial(id);
      if (latest == null) return;
      _uploaded = [for (final m in _uploaded) m.id == id ? latest : m];
      notifyListeners();
    } catch (_) {
      // A stale status chip is a cosmetic loss next to the error already set.
    }
  }

  /// Reads a YouTube video, or a whole playlist, into the library.
  ///
  /// A single video is read before this returns. A playlist is listed and
  /// recorded (one library item, D-038), and this returns while its videos are
  /// read in the background, [parallelVideos] at a time — so the screen can
  /// say what's happening and the student can carry on. [wholePlaylist]
  /// decides a `watch?v=…&list=…` link; a bare playlist link is always the
  /// whole playlist. Returns null when nothing could start, with [error] set.
  Future<YouTubeImport?> importYouTube(
    YouTubeLink link, {
    bool wholePlaylist = true,
  }) async {
    if (_addingLink || busy || !link.isUsable) return null;
    final usePlaylist =
        link.playlistId != null && (wholePlaylist || link.videoId == null);
    return usePlaylist
        ? _addPlaylist(link.playlistId!)
        : _addVideo(link.videoId!);
  }

  Future<YouTubeImport?> _addVideo(String videoId) async {
    if (atLimit) {
      setError(
        'You already have $maxMaterials items. Remove one to add another.',
      );
      return null;
    }
    if (_uploaded.any((m) => _videoIdOf(m) == videoId)) {
      setError('That video is already in your library.');
      return null;
    }

    clearError();
    _setLinkProgress('Reading the captions…');
    try {
      final transcript = await _youtube.transcript(videoId);
      if (!transcript.hasCaptions) {
        setError('"${transcript.video.title}" has no captions, so the AI '
            "can't read it. Try another video, or upload notes for it.");
        return null;
      }
      final saved = await _materials.addVideoTranscript(
        videoId: videoId,
        title: transcript.video.title,
        transcript: transcript.toFileText(),
      );
      _uploaded = [saved, ..._uploaded];
      notifyListeners();
      await _ingestAll([saved]);
      return const YouTubeImport.video();
    } on YouTubeException catch (e) {
      setError(e.message);
      return null;
    } catch (e) {
      setError(e);
      return null;
    } finally {
      _setLinkProgress(null);
    }
  }

  Future<YouTubeImport?> _addPlaylist(String youtubeId) async {
    // Pasted again: carry on where it stopped rather than adding it twice.
    final existing =
        _playlists.where((p) => p.youtubeId == youtubeId).firstOrNull;
    if (existing != null) {
      final left = pendingOf(existing).length;
      if (left == 0) {
        setError('That playlist is already in your library.');
        return null;
      }
      clearError();
      _startReader();
      return YouTubeImport.playlist(
          title: existing.title, queued: left, resumed: true);
    }
    if (atLimit) {
      setError(
        'You already have $maxMaterials items. Remove one to add another.',
      );
      return null;
    }

    clearError();
    _setLinkProgress('Opening the playlist…');
    try {
      final listing = await _youtube.playlist(youtubeId);
      final videos = listing.videos.take(maxPlaylistVideos).toList();
      final ids = [for (final v in videos) v.id];
      // Speech runs ~15 characters a second and a chunk is ~1,500, so a
      // video's length says roughly how many chunks it becomes. Ten minutes
      // for one the listing gave no length for.
      final seconds = videos.fold<int>(0, (sum, v) => sum + (v.seconds ?? 600));
      final playlist = await _materials.createPlaylist(
        youtubeId: youtubeId,
        title: listing.title,
        videoIds: ids,
      );
      _playlists = [playlist, ..._playlists];
      notifyListeners();
      _startReader();
      return YouTubeImport.playlist(
        title: playlist.title,
        queued: ids.length,
        chunks: seconds ~/ 100,
        capped: listing.videos.length >= maxPlaylistVideos,
      );
    } on YouTubeException catch (e) {
      setError(e.message);
      return null;
    } catch (e) {
      setError(e);
      return null;
    } finally {
      _setLinkProgress(null);
    }
  }

  void _setLinkProgress(String? progress) {
    _addingLink = progress != null;
    _linkProgress = progress;
    notifyListeners();
  }

  /// Carries on reading any playlist the phone didn't finish — the app was
  /// closed, or the signal dropped. Called at launch, when the app comes back
  /// to the foreground, and from a playlist's Resume button.
  Future<void> resumeImports() async {
    if (_run != null) return;
    if (!loaded) await load();
    if (_playlists.any(_hasWork)) {
      clearError();
      _startReader();
    }
  }

  bool _hasWork(MaterialPlaylist playlist) =>
      pendingOf(playlist).isNotEmpty || _unreadOf(playlist).isNotEmpty;

  /// Stored but never sent to `embed-material` — the app closed in between.
  List<StudyMaterial> _unreadOf(MaterialPlaylist playlist) => [
        for (final m in _uploaded)
          if (m.playlistId == playlist.id &&
              m.storagePath != null &&
              m.status == IngestStatus.uploaded)
            m,
      ];

  void _startReader() {
    if (_run != null) {
      // A retry or a second playlist the running pass may already be past.
      _again = true;
      return;
    }
    _again = false;
    _run = _readPlaylists().whenComplete(() {
      final paused = _stopRequested;
      _run = null;
      _activePlaylistId = null;
      _stopRequested = false;
      notifyListeners();
      if (_again && !paused) _startReader();
    });
    notifyListeners();
  }

  /// Puts a playlist's failed videos back in the queue and reads them again —
  /// the playlist row's Retry, for videos that failed before the reader knew
  /// to wait out a busy AI.
  Future<void> retryFailed(MaterialPlaylist playlist) async {
    final failed = {
      for (final m in videosOf(playlist))
        if (m.status == IngestStatus.failed) m.id,
    };
    if (failed.isEmpty) return;
    try {
      await _materials.resetFailed(playlist.id);
    } catch (e) {
      setError(e);
      return;
    }
    _uploaded = [
      for (final m in _uploaded)
        failed.contains(m.id) ? m.withStatus(IngestStatus.uploaded) : m,
    ];
    clearError();
    _startReader();
  }

  /// Works through every playlist with videos left, oldest added first, until
  /// none have any or a pause is asked for. A playlist added while this runs
  /// is picked up when the current one finishes.
  Future<void> _readPlaylists() async {
    final attempted = <String>{};
    while (!_stopRequested) {
      final playlist = _playlists.reversed
          .where((p) => !attempted.contains(p.id) && _hasWork(p))
          .firstOrNull;
      if (playlist == null) break;
      attempted.add(playlist.id);
      _activePlaylistId = playlist.id;
      notifyListeners();

      final tasks = <Future<void> Function()>[
        for (final m in _unreadOf(playlist)) () => _ingestQuietly(m),
        for (final id in pendingOf(playlist)) () => _readVideo(playlist, id),
      ];
      var next = 0;
      Future<void> worker() async {
        while (!_stopRequested && next < tasks.length) {
          await tasks[next++]();
        }
      }

      await Future.wait([for (var i = 0; i < parallelVideos; i++) worker()]);

      final failed = progressOf(playlist).failed;
      if (!_stopRequested && failed > 0 && _has(playlist)) {
        setError(failed == 1
            ? 'One video from "${playlist.title}" couldn\'t be read. Retry it '
                'in the playlist.'
            : '$failed videos from "${playlist.title}" couldn\'t be read. '
                'Retry them in the playlist.');
      }
    }
  }

  bool _has(MaterialPlaylist playlist) =>
      _playlists.any((p) => p.id == playlist.id);

  /// One playlist video: captions on the phone, stored, then read.
  Future<void> _readVideo(MaterialPlaylist playlist, String videoId) async {
    if (!_has(playlist)) return;
    final YouTubeTranscript transcript;
    try {
      transcript = await _youtube.transcript(videoId);
    } on YouTubeException catch (e) {
      // No signal isn't the video's fault: stop, and keep it for later.
      // Private or deleted is: skip it for good.
      if (e.retryable) {
        _pause(playlist);
      } else {
        _skip(playlist, videoId);
      }
      return;
    }
    if (!transcript.hasCaptions) {
      _skip(playlist, videoId);
      return;
    }
    if (!_has(playlist) || _stopRequested) return;

    final StudyMaterial saved;
    try {
      saved = await _materials.addVideoTranscript(
        videoId: videoId,
        title: transcript.video.title,
        transcript: transcript.toFileText(),
        playlistId: playlist.id,
      );
    } catch (_) {
      // Supabase unreachable. Nothing was stored, so it's still pending.
      _pause(playlist);
      return;
    }
    _uploaded = [saved, ..._uploaded];
    notifyListeners();
    await _ingestQuietly(saved);
  }

  /// [_ingestAll] for the background reader. A real failure stays on the row
  /// (its Retry button) and is summed up once the playlist is done, rather
  /// than replacing the error banner once per video.
  ///
  /// A busy AI is not a real failure: every worker waits out
  /// [busyAiCooldown] and this video goes again. If the AI is still busy
  /// after [_cooldownsBeforePause] waits with nothing read in between, the
  /// limit is the day's, so the video goes back in the queue and the reader
  /// pauses until the next launch.
  Future<void> _ingestQuietly(StudyMaterial material) async {
    var again = material.status == IngestStatus.failed;
    while (true) {
      await _waitOutCooldown();
      if (_stopRequested) {
        await _requeue(material);
        return;
      }
      _patchStatus(material.id, IngestStatus.processing);
      try {
        if (again) {
          // The function marked it failed on the way out; reset, then ask.
          await _materials.reingest(material.id);
        } else {
          await _materials.requestIngest(material.id);
        }
        _cooldownsInARow = 0;
        break;
      } on FunctionException catch (e) {
        if (e.status != 429) break;
        again = true;
        final cooling = _coolUntil?.isAfter(DateTime.now()) ?? false;
        if (!cooling) {
          // Only the worker that starts a cooldown counts it; the other two
          // hit the same wall at the same moment.
          _cooldownsInARow++;
          if (_cooldownsInARow > _cooldownsBeforePause) {
            await _requeue(material);
            _pauseForQuota();
            return;
          }
          _coolUntil = DateTime.now().add(busyAiCooldown);
        }
      } catch (_) {
        // Recorded on the row by the function, or by requestIngest itself.
        break;
      }
    }
    await _refresh(material.id);
  }

  Future<void> _waitOutCooldown() async {
    final until = _coolUntil;
    if (until == null) return;
    final left = until.difference(DateTime.now());
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  /// Back to `uploaded`, where [resumeImports] picks it up.
  Future<void> _requeue(StudyMaterial material) async {
    try {
      final row = await _materials.retryIngest(material.id);
      _uploaded = [for (final m in _uploaded) m.id == row.id ? row : m];
    } catch (_) {
      _patchStatus(material.id, IngestStatus.failed);
      return;
    }
    notifyListeners();
  }

  void _pauseForQuota() {
    if (_stopRequested) return;
    _stopRequested = true;
    _cooldownsInARow = 0;
    _coolUntil = null;
    setError("The AI's free limit is used up for now, so reading paused. It "
        'carries on when you open the app again, or tap Resume later.');
  }

  void _pause(MaterialPlaylist playlist) {
    if (_stopRequested) return;
    _stopRequested = true;
    setError('Paused reading "${playlist.title}" — no connection. It carries '
        'on when you open the app again, or tap Resume.');
  }

  /// Marks a video as never to be read, locally at once and on the server in
  /// order. Each write sends the whole current list, so the last one to land
  /// is always the newest.
  void _skip(MaterialPlaylist playlist, String videoId) {
    final current = _playlists.where((p) => p.id == playlist.id).firstOrNull;
    if (current == null || current.skippedIds.contains(videoId)) return;
    _playlists = [
      for (final p in _playlists)
        p.id == playlist.id ? p.withSkipped({...p.skippedIds, videoId}) : p,
    ];
    notifyListeners();
    _skipWrites = _skipWrites.then((_) async {
      final latest = _playlists.where((p) => p.id == playlist.id).firstOrNull;
      if (latest == null) return;
      try {
        await _materials.setSkipped(latest.id, latest.skippedIds);
      } catch (_) {
        // The video comes up again next time and is skipped again. Harmless.
      }
    });
  }

  /// Removes a playlist with all its videos, stopping its reader first.
  Future<bool> removePlaylist(MaterialPlaylist playlist) async {
    final running = _run;
    if (running != null && _activePlaylistId == playlist.id) {
      _stopRequested = true;
      await running;
    }
    final ok = await runMutation(() async {
      final paths = [
        for (final m in videosOf(playlist))
          if (m.storagePath != null) m.storagePath!,
      ];
      await _materials.deletePlaylist(playlist, paths);
      _playlists = _playlists.where((p) => p.id != playlist.id).toList();
      _uploaded =
          _uploaded.where((m) => m.playlistId != playlist.id).toList();
    });
    // Other playlists may have been waiting behind the one just removed.
    if (ok) unawaited(resumeImports());
    return ok;
  }

  Future<bool> addLink(String url, {String? title}) => runMutation(() async {
        final saved = await _materials.addLink(url: url, title: title);
        _uploaded = [saved, ..._uploaded];
      });

  Future<bool> removeMaterial(StudyMaterial material) => runMutation(() async {
        await _materials.deleteMaterial(material);
        _uploaded = _uploaded.where((m) => m.id != material.id).toList();
        // A video removed from a playlist stays removed: without this the
        // reader would see it as unread and fetch it straight back.
        final playlist =
            _playlists.where((p) => p.id == material.playlistId).firstOrNull;
        final videoId = _videoIdOf(material);
        if (playlist != null && videoId != null) _skip(playlist, videoId);
      });

  /// Creates the goal (and its subjects) that the rest of the app hangs off.
  /// The AI roadmap generation that follows lands in Phase C.
  Future<bool> createGoal({
    required String name,
    DateTime? examDate,
    Pace pace = Pace.steady,
    List<String> subjects = const [],
  }) =>
      runMutation(() async {
        _goal = await _goals.createGoal(
          name: name,
          examDate: examDate,
          pace: pace,
          subjectNames: subjects,
        );
      });
}

/// What [OnboardingStore.importYouTube] started, for the screen to say.
class YouTubeImport {
  const YouTubeImport.video()
      : playlistTitle = null,
        queued = 0,
        chunks = 0,
        capped = false,
        resumed = false;

  const YouTubeImport.playlist({
    required String title,
    required this.queued,
    this.chunks = 0,
    this.capped = false,
    this.resumed = false,
  }) : playlistTitle = title;

  /// Null for a single video.
  final String? playlistTitle;

  /// Videos left to read.
  final int queued;

  /// Roughly how many chunks they'll become, from their lengths.
  final int chunks;

  /// The playlist had more than [OnboardingStore.maxPlaylistVideos].
  final bool capped;

  /// The playlist was already in the library; this carries on with it.
  final bool resumed;

  String get summary {
    final title = playlistTitle;
    if (title == null) return 'Video added';
    // ~4 s a video at three at a time, or the free tier's ~100 chunks a
    // minute, whichever is slower (D-038).
    final byVideos = queued * 4 / 60;
    final byChunks = chunks / 90;
    final minutes = (byVideos > byChunks ? byVideos : byChunks).ceil();
    final time = minutes <= 1 ? 'about a minute' : 'about $minutes minutes';
    final videos = '$queued video${queued == 1 ? '' : 's'}';
    if (resumed) return 'Carrying on with "$title" — $videos left, $time';
    final first = capped
        ? 'the first ${OnboardingStore.maxPlaylistVideos} videos'
        : videos;
    return 'Reading $first from "$title" — $time. Keep the app open; you can '
        'carry on using it.';
  }
}

/// Counts for one playlist's row in the library.
class PlaylistProgress {
  const PlaylistProgress({
    required this.total,
    required this.ready,
    required this.failed,
    required this.skipped,
    required this.pending,
  });

  final int total;
  final int ready;
  final int failed;
  final int skipped;
  final int pending;

  /// Share of the playlist that has been dealt with, for the progress bar.
  double get fraction =>
      total == 0 ? 1 : ((total - pending) / total).clamp(0, 1).toDouble();
}
