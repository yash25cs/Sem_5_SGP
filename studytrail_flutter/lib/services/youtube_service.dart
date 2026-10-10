import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// YouTube videos and playlists as study material.
///
/// The transcript is read **on the phone**, not in an Edge Function, and that
/// was measured rather than chosen (docs/DECISIONS.md D-037). From Supabase's
/// servers YouTube's player API answers every client with "Sign in to confirm
/// you're not a bot"; from a home or mobile connection the same request returns
/// caption tracks that need no extra token. Gemini can watch a YouTube URL
/// itself, but a cold 60-second clip took 80 s and a 10-minute video didn't
/// finish inside 115 s — a lecture would outlive the function. So the phone
/// fetches the captions, and `embed-material` reads them like a notes file.
///
/// These are the endpoints YouTube's own apps call, not a published API, so
/// every read of a response is defensive and every failure becomes a sentence a
/// student can act on.
class YouTubeService {
  YouTubeService({http.Client? client}) : _client = client;

  http.Client? _client;
  http.Client get _http => _client ??= http.Client();

  static const _timeout = Duration(seconds: 20);

  /// The Android app's client. From a phone connection its player response
  /// carries caption URLs without a proof-of-origin token, which the web
  /// client's no longer do. Measured 2026-10-02.
  static const _android = {
    'clientName': 'ANDROID',
    'clientVersion': '20.10.38',
  };
  static const _androidAgent =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip';

  /// The web client lists a playlist's first 100 videos in one call.
  static const _web = {
    'clientName': 'WEB',
    'clientVersion': '2.20250925.01.00',
    'hl': 'en',
  };
  static const _webAgent = 'Mozilla/5.0 (Linux; Android 14) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';

  /// A playlist's title and its public videos, in playlist order.
  ///
  /// The browse call is the main path; the RSS feed is the fallback for when
  /// YouTube reshapes that response, at the cost of only the first 15 videos.
  Future<YouTubePlaylist> playlist(String id) async {
    YouTubePlaylist? found;
    try {
      final data = await _innertube(
        'browse',
        {
          'context': {'client': _web},
          'browseId': 'VL$id',
        },
        agent: _webAgent,
      );
      found = parsePlaylist(id, data);
    } on _HttpStatus {
      // 400 is what a private or made-up playlist gets. The feed answers that
      // case with a 404, which is the error worth showing.
    }

    if (found == null || found.videos.isEmpty) {
      try {
        final feed = await _get(
          'https://www.youtube.com/feeds/videos.xml?playlist_id=$id',
          agent: _webAgent,
        );
        found = parsePlaylistFeed(id, feed);
      } on _HttpStatus {
        found = null;
      }
    }

    if (found == null || found.videos.isEmpty) {
      throw const YouTubeException(
        "That playlist is private, empty or doesn't exist. Only public and "
        'unlisted playlists can be added.',
      );
    }
    return found;
  }

  /// One video's details and, when it has any, its captions.
  ///
  /// Throws [YouTubeException] when YouTube won't play the video at all;
  /// returns a transcript with no lines when it plays but has no captions.
  Future<YouTubeTranscript> transcript(String videoId) async {
    final Map<String, dynamic> player;
    try {
      player = await _innertube(
        'player',
        {
          'context': {'client': _android},
          'videoId': videoId,
        },
        agent: _androidAgent,
      );
    } on _HttpStatus {
      throw const YouTubeException(
          "YouTube didn't answer for that video. Try again in a minute.",
          retryable: true);
    }

    final playability = _map(player['playabilityStatus']);
    final status = playability?['status'];
    if (status != 'OK') throw YouTubeException(playabilityMessage(status));

    final details = _map(player['videoDetails']);
    final title = _string(details?['title']);
    final video = YouTubeVideo(
      id: videoId,
      title: title ?? 'YouTube video',
      seconds: int.tryParse('${details?['lengthSeconds']}'),
    );

    final tracks = parseTracks(player);
    final track = pickTrack(tracks);
    if (track == null) return YouTubeTranscript(video: video);

    final String xml;
    try {
      // srv3 is the richer format the web player asks for; without it the
      // response is plain `<text start dur>` lines, which is all that's needed.
      xml = await _get(track.url.replaceAll('&fmt=srv3', ''),
          agent: _androidAgent);
    } on _HttpStatus {
      throw const YouTubeException(
          "YouTube wouldn't send that video's captions. Try again in a minute.",
          retryable: true);
    }
    return YouTubeTranscript(
      video: video,
      language: track.language,
      generated: track.generated,
      lines: parseCaptions(xml),
    );
  }

  Future<Map<String, dynamic>> _innertube(
    String endpoint,
    Map<String, Object?> body, {
    required String agent,
  }) async {
    final text = await _send(() => _http.post(
          Uri.parse(
              'https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': agent,
            'Accept-Language': 'en-US,en;q=0.9',
          },
          body: jsonEncode(body),
        ));
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Falls through to the shared message.
    }
    throw const YouTubeException(
        'YouTube sent back something unexpected. Try again in a minute.',
        retryable: true);
  }

  Future<String> _get(String url, {required String agent}) =>
      _send(() => _http.get(Uri.parse(url), headers: {'User-Agent': agent}));

  /// Runs one request inside the timeout and turns transport failures into a
  /// YouTube-specific message — the app-wide one says "Can't reach
  /// StudyTrail", which would be wrong here.
  Future<String> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on TimeoutException {
      throw const YouTubeException(
          'YouTube took too long to answer. Try again.',
          retryable: true);
    } on http.ClientException {
      throw const YouTubeException(
          "Couldn't reach YouTube. Check your connection and try again.",
          retryable: true);
    }
    if (res.statusCode != 200) throw _HttpStatus(res.statusCode);
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  // ---------------------------------------------------------------------------
  // Parsing. Static and pure, so the tests can feed them recorded shapes.
  // ---------------------------------------------------------------------------

  /// What a student is told when YouTube won't play a video.
  static String playabilityMessage(Object? status) => switch (status) {
        'LOGIN_REQUIRED' => "YouTube won't share that video without a "
            "sign-in — it may be private or age-restricted.",
        'LIVE_STREAM_OFFLINE' => "That live stream hasn't started, so there's "
            'nothing to read yet.',
        _ => "That video isn't available — it may be private, deleted or "
            'blocked in your region.',
      };

  /// Videos from a browse response.
  ///
  /// Reads both shapes YouTube has used: `lockupViewModel` (current, measured
  /// 2026-10-02) and the older `playlistVideoRenderer`. Only the `contents`
  /// subtree is walked, so a "more playlists" rail can't add strangers' videos.
  static YouTubePlaylist? parsePlaylist(String id, Map<String, dynamic> data) {
    final videos = <YouTubeVideo>[];
    final seen = <String>{};

    void add(String? videoId, String? title, int? seconds) {
      if (videoId == null || !YouTubeLink.isVideoId(videoId)) return;
      if (title == null || _isRemoved(title) || !seen.add(videoId)) return;
      videos.add(YouTubeVideo(id: videoId, title: title, seconds: seconds));
    }

    void walk(Object? node) {
      if (node is List) {
        for (final child in node) {
          walk(child);
        }
        return;
      }
      if (node is! Map) return;

      final lockup = _map(node['lockupViewModel']);
      if (lockup != null &&
          lockup['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
        final meta = _map(_map(lockup['metadata'])?['lockupMetadataViewModel']);
        add(
          _string(lockup['contentId']),
          _string(_map(meta?['title'])?['content']),
          _badgeSeconds(lockup['contentImage']),
        );
        return;
      }

      final renderer = _map(node['playlistVideoRenderer']);
      if (renderer != null) {
        add(
          _string(renderer['videoId']),
          _runsText(renderer['title']),
          int.tryParse('${renderer['lengthSeconds']}'),
        );
        return;
      }

      for (final child in node.values) {
        walk(child);
      }
    }

    walk(data['contents']);
    if (videos.isEmpty) return null;

    final title = _string(_map(
            _map(data['metadata'])?['playlistMetadataRenderer'])?['title']) ??
        _runsText(
            _map(_map(data['header'])?['playlistHeaderRenderer'])?['title']) ??
        'YouTube playlist';
    return YouTubePlaylist(id: id, title: title, videos: videos);
  }

  /// Videos from the playlist's RSS feed — the first 15, in playlist order.
  static YouTubePlaylist? parsePlaylistFeed(String id, String xml) {
    final firstEntry = xml.indexOf('<entry>');
    final head = firstEntry < 0 ? xml : xml.substring(0, firstEntry);
    final title = RegExp(r'<title>([^<]*)</title>').firstMatch(head)?.group(1);

    final videos = <YouTubeVideo>[];
    final seen = <String>{};
    final entries = RegExp(r'<entry>([\s\S]*?)</entry>').allMatches(xml);
    for (final entry in entries) {
      final body = entry.group(1)!;
      final videoId = RegExp(r'<yt:videoId>([^<]+)</yt:videoId>')
          .firstMatch(body)
          ?.group(1);
      final name = RegExp(r'<title>([^<]*)</title>').firstMatch(body)?.group(1);
      if (videoId == null || name == null || !seen.add(videoId)) continue;
      final decoded = decodeEntities(name);
      if (_isRemoved(decoded)) continue;
      videos.add(YouTubeVideo(id: videoId, title: decoded));
    }
    if (videos.isEmpty) return null;
    return YouTubePlaylist(
      id: id,
      title: title == null ? 'YouTube playlist' : decodeEntities(title),
      videos: videos,
    );
  }

  /// Every caption track a player response offers.
  static List<CaptionTrack> parseTracks(Map<String, dynamic> player) {
    final list =
        _map(_map(player['captions'])?['playerCaptionsTracklistRenderer'])?[
            'captionTracks'];
    if (list is! List) return const [];
    return [
      for (final raw in list)
        if (raw is Map &&
            raw['baseUrl'] is String &&
            raw['languageCode'] is String)
          CaptionTrack(
            url: raw['baseUrl'] as String,
            language: raw['languageCode'] as String,
            generated: raw['kind'] == 'asr',
          ),
    ];
  }

  /// The track worth reading: a language the app answers in (English, Hindi,
  /// Gujarati — in that order) before any other, and a human-written track
  /// before YouTube's automatic one within the same language.
  static CaptionTrack? pickTrack(List<CaptionTrack> tracks) {
    if (tracks.isEmpty) return null;
    int rank(CaptionTrack t) {
      final lang = t.language.split('-').first.toLowerCase();
      final preferred = const ['en', 'hi', 'gu'].indexOf(lang);
      return (preferred < 0 ? 3 : preferred) * 2 + (t.generated ? 1 : 0);
    }

    var best = tracks.first;
    for (final t in tracks.skip(1)) {
      if (rank(t) < rank(best)) best = t;
    }
    return best;
  }

  /// Caption lines from the timedtext XML.
  ///
  /// Handles the plain format (`<text start="12.7">`) this service asks for,
  /// and srv3 (`<p t="12760">`) in case YouTube stops honouring that.
  static List<CaptionLine> parseCaptions(String xml) {
    final lines = <CaptionLine>[];
    void add(double start, String raw) {
      final text = decodeEntities(raw.replaceAll(RegExp(r'<[^>]*>'), ' '))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isNotEmpty) lines.add(CaptionLine(start, text));
    }

    for (final m
        in RegExp(r'<text\b[^>]*\bstart="([\d.]+)"[^>]*>([\s\S]*?)</text>')
            .allMatches(xml)) {
      add(double.tryParse(m.group(1)!) ?? 0, m.group(2)!);
    }
    if (lines.isNotEmpty) return lines;

    for (final m in RegExp(r'<p\b[^>]*\bt="(\d+)"[^>]*>([\s\S]*?)</p>')
        .allMatches(xml)) {
      add((int.tryParse(m.group(1)!) ?? 0) / 1000, m.group(2)!);
    }
    return lines;
  }

  /// Caption text arrives escaped twice — `it&amp;#39;s` — once for the XML
  /// and once more as HTML inside it, so this decodes twice.
  static String decodeEntities(String text) {
    final entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);');
    String once(String value) => value.replaceAllMapped(entity, (m) {
          final name = m.group(1)!;
          switch (name) {
            case 'amp':
              return '&';
            case 'lt':
              return '<';
            case 'gt':
              return '>';
            case 'quot':
              return '"';
            case 'apos':
              return "'";
          }
          final code = name.startsWith('#x')
              ? int.tryParse(name.substring(2), radix: 16)
              : int.tryParse(name.substring(1));
          if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
          return String.fromCharCode(code);
        });
    return once(once(text));
  }

  /// "9:52" or "1:02:03" from a thumbnail's duration badge.
  static int? _badgeSeconds(Object? node) {
    if (node is List) {
      for (final child in node) {
        final found = _badgeSeconds(child);
        if (found != null) return found;
      }
      return null;
    }
    if (node is! Map) return null;
    final badge = _map(node['thumbnailBadgeViewModel']);
    final text = _string(badge?['text']);
    if (text != null) {
      final seconds = parseDuration(text);
      if (seconds != null) return seconds;
    }
    for (final child in node.values) {
      final found = _badgeSeconds(child);
      if (found != null) return found;
    }
    return null;
  }

  /// Seconds in "m:ss" or "h:mm:ss", or null for anything else ("LIVE").
  static int? parseDuration(String text) {
    final m = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (m == null) return null;
    return int.parse(m.group(1) ?? '0') * 3600 +
        int.parse(m.group(2)!) * 60 +
        int.parse(m.group(3)!);
  }

  /// Placeholders a playlist keeps for videos that are gone.
  static bool _isRemoved(String title) =>
      title == '[Private video]' || title == '[Deleted video]';

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// `{simpleText}` or `{runs: [{text}]}` — YouTube's two text shapes.
  static String? _runsText(Object? value) {
    final map = _map(value);
    if (map == null) return null;
    final simple = _string(map['simpleText']);
    if (simple != null) return simple;
    final runs = map['runs'];
    if (runs is! List) return null;
    return _string(runs
        .map((r) => r is Map && r['text'] is String ? r['text'] as String : '')
        .join());
  }
}

/// A failure worth showing the student as-is.
class YouTubeException implements Exception {
  const YouTubeException(this.message, {this.retryable = false});
  final String message;

  /// The connection or YouTube itself hiccuped, rather than the video being
  /// unreadable. A playlist import pauses on these instead of skipping the
  /// video for good.
  final bool retryable;

  @override
  String toString() => message;
}

/// A non-200 answer, kept internal: each caller knows what it means for them.
class _HttpStatus implements Exception {
  const _HttpStatus(this.code);
  final int code;
}

/// What a pasted link points at. Both ids are set for a video opened from
/// inside a playlist (`watch?v=…&list=…`); neither is set for a YouTube page
/// that is neither, such as a channel.
class YouTubeLink {
  const YouTubeLink({this.videoId, this.playlistId});

  final String? videoId;
  final String? playlistId;

  /// Whether there is anything here that can be read.
  bool get isUsable => videoId != null || playlistId != null;

  /// A playlist link with no particular video in it.
  bool get isPlaylist => playlistId != null && videoId == null;

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _listId = RegExp(r'^[A-Za-z0-9_-]{12,64}$');

  static bool isVideoId(String id) => _videoId.hasMatch(id);

  /// The parsed link, or null when [input] isn't a YouTube link at all.
  static YouTubeLink? parse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null) return null;

    final host =
        uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m|music)\.'), '');
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? video;
    if (host == 'youtu.be') {
      video = segments.isEmpty ? null : segments.first;
    } else if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
      if (segments.length > 1 &&
          const {'shorts', 'live', 'embed', 'v'}.contains(segments.first)) {
        video = segments[1];
      } else if (segments.isNotEmpty && segments.first == 'watch') {
        video = uri.queryParameters['v'];
      }
    } else {
      return null;
    }

    final list = uri.queryParameters['list'];
    return YouTubeLink(
      videoId: video != null && _videoId.hasMatch(video) ? video : null,
      playlistId:
          list != null && _listId.hasMatch(list) && !_isMix(list) ? list : null,
    );
  }

  /// Mixes ("RD…") are generated per viewer and can't be listed, and Watch
  /// later / Liked are private to the signed-in account.
  static bool _isMix(String list) =>
      list.startsWith('RD') || const {'WL', 'LL', 'LM'}.contains(list);
}

class YouTubeVideo {
  const YouTubeVideo({required this.id, required this.title, this.seconds});

  final String id;
  final String title;

  /// Null when the listing didn't say.
  final int? seconds;

  String get url => watchUrl(id);

  static String watchUrl(String id) => 'https://www.youtube.com/watch?v=$id';
}

class YouTubePlaylist {
  const YouTubePlaylist({
    required this.id,
    required this.title,
    required this.videos,
  });

  final String id;
  final String title;
  final List<YouTubeVideo> videos;
}

class CaptionTrack {
  const CaptionTrack({
    required this.url,
    required this.language,
    this.generated = false,
  });

  final String url;
  final String language;

  /// YouTube's automatic speech recognition, rather than captions a person
  /// wrote.
  final bool generated;
}

class CaptionLine {
  const CaptionLine(this.start, this.text);

  /// Seconds from the start of the video.
  final double start;
  final String text;
}

class YouTubeTranscript {
  const YouTubeTranscript({
    required this.video,
    this.language,
    this.generated = false,
    this.lines = const [],
  });

  final YouTubeVideo video;
  final String? language;
  final bool generated;
  final List<CaptionLine> lines;

  bool get hasCaptions => lines.isNotEmpty;

  /// The text file `embed-material` reads: a two-line header, then one
  /// `[m:ss] words` line per caption. The server chunks on those stamps, so a
  /// cited chunk can say where in the video it came from.
  String toFileText() {
    final out = StringBuffer()
      ..writeln('# ${video.title}')
      ..writeln(video.url)
      ..writeln();
    for (final line in lines) {
      out.writeln('[${stamp(line.start)}] ${line.text}');
    }
    return out.toString();
  }

  /// "4:05" or "1:02:03".
  static String stamp(double seconds) {
    final total = seconds.floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }
}
