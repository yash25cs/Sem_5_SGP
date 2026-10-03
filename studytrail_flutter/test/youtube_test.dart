// YouTube videos and playlists as material: link parsing, the response shapes
// YouTubeService reads (recorded 2026-10-02), and OnboardingStore's import
// loop. test/live/youtube_live_test.dart checks the same against real YouTube.

import 'dart:convert';

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/services/youtube_service.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/video_link_sheet.dart';

void main() {
  group('YouTubeLink.parse', () {
    test('reads every common video link shape', () {
      for (final url in [
        'https://www.youtube.com/watch?v=fNk_zzaMoSs',
        'https://youtube.com/watch?v=fNk_zzaMoSs&t=42s',
        'https://m.youtube.com/watch?v=fNk_zzaMoSs',
        'https://music.youtube.com/watch?v=fNk_zzaMoSs',
        'https://youtu.be/fNk_zzaMoSs?si=abc123',
        'https://www.youtube.com/shorts/fNk_zzaMoSs',
        'https://www.youtube.com/live/fNk_zzaMoSs',
        'https://www.youtube.com/embed/fNk_zzaMoSs',
        'youtube.com/watch?v=fNk_zzaMoSs',
        '  https://youtu.be/fNk_zzaMoSs  ',
      ]) {
        final link = YouTubeLink.parse(url);
        expect(link?.videoId, 'fNk_zzaMoSs', reason: url);
        expect(link?.playlistId, isNull, reason: url);
      }
    });

    test('a playlist link is a playlist', () {
      final link = YouTubeLink.parse(
          'https://youtube.com/playlist?list=PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab&si=x');
      expect(link?.playlistId, 'PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab');
      expect(link?.isPlaylist, isTrue);
    });

    test('a video inside a playlist carries both', () {
      final link = YouTubeLink.parse('https://www.youtube.com/watch'
          '?v=fNk_zzaMoSs&list=PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab&index=1');
      expect(link?.videoId, 'fNk_zzaMoSs');
      expect(link?.playlistId, 'PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab');
      expect(link?.isPlaylist, isFalse);
    });

    test('mixes and private lists are dropped, the video kept', () {
      final mix = YouTubeLink.parse(
          'https://www.youtube.com/watch?v=fNk_zzaMoSs&list=RDfNk_zzaMoSs');
      expect(mix?.videoId, 'fNk_zzaMoSs');
      expect(mix?.playlistId, isNull);
      expect(
          YouTubeLink.parse('https://youtube.com/playlist?list=WL')!.isUsable,
          isFalse);
    });

    test('a channel page is YouTube but not usable', () {
      final link = YouTubeLink.parse('https://www.youtube.com/@3blue1brown');
      expect(link, isNotNull);
      expect(link!.isUsable, isFalse);
    });

    test('anything else is not YouTube', () {
      expect(
          YouTubeLink.parse('https://example.com/watch?v=fNk_zzaMoSs'), isNull);
      expect(YouTubeLink.parse('https://notyoutube.com/watch?v=fNk_zzaMoSs'),
          isNull);
      expect(YouTubeLink.parse(''), isNull);
      expect(YouTubeLink.parse('https://youtu.be/short')!.isUsable, isFalse);
    });
  });

  group('captions', () {
    test('decodes the double escaping and keeps start times', () {
      final lines = YouTubeService.parseCaptions(
          '<?xml version="1.0" encoding="utf-8" ?><transcript>'
          '<text start="12.76" dur="3.24">Good morning everybody.</text>'
          '<text start="16.92" dur="5.52">My name&amp;#39;s Jason\nKu.</text>'
          '<text start="20" dur="1">  </text>'
          '<text start="22.4" dur="2">x &amp;lt; y &amp;amp; z</text>'
          '</transcript>');
      expect(lines.map((l) => l.text), [
        'Good morning everybody.',
        "My name's Jason Ku.",
        'x < y & z',
      ]);
      expect(lines[1].start, 16.92);
    });

    test('falls back to srv3 paragraphs', () {
      final lines = YouTubeService.parseCaptions('<timedtext format="3"><body>'
          '<p t="1500" d="2000"><s>Hello</s><s> world</s></p>'
          '<p t="61000" d="900">again</p>'
          '</body></timedtext>');
      expect(lines.map((l) => l.text), ['Hello world', 'again']);
      expect(lines[1].start, 61);
    });

    test('prefers a language the app answers in, then a written track', () {
      const fr = CaptionTrack(url: 'fr', language: 'fr');
      const enAuto =
          CaptionTrack(url: 'en-asr', language: 'en', generated: true);
      const en = CaptionTrack(url: 'en', language: 'en-GB');
      const hi = CaptionTrack(url: 'hi', language: 'hi', generated: true);
      expect(YouTubeService.pickTrack([fr, enAuto, en, hi])!.url, 'en');
      expect(YouTubeService.pickTrack([fr, enAuto, hi])!.url, 'en-asr');
      expect(YouTubeService.pickTrack([fr, hi])!.url, 'hi');
      expect(YouTubeService.pickTrack([fr])!.url, 'fr');
      expect(YouTubeService.pickTrack(const []), isNull);
    });

    test('the transcript file stamps every line', () {
      const t = YouTubeTranscript(
        video: YouTubeVideo(id: 'ZA-tUyM_y7s', title: 'Lecture 1'),
        lines: [
          CaptionLine(5.4, 'Hello.'),
          CaptionLine(754.9, 'Middle.'),
          CaptionLine(3723, 'Late.'),
        ],
      );
      expect(
          t.toFileText(),
          '# Lecture 1\n'
          'https://www.youtube.com/watch?v=ZA-tUyM_y7s\n'
          '\n'
          '[0:05] Hello.\n'
          '[12:34] Middle.\n'
          '[1:02:03] Late.\n');
    });
  });

  group('playlists', () {
    test('reads lockups in order, skipping gone and repeated videos', () {
      final list = YouTubeService.parsePlaylist(
          'PL1',
          _browse([
            _lockup('fNk_zzaMoSs', 'Vectors | Chapter 1', '9:52'),
            _lockup('k7RM-ot2NWY', 'Linear combinations', '1:02:03'),
            _lockup('aaaaaaaaaaa', '[Private video]', null),
            _lockup('fNk_zzaMoSs', 'Vectors | Chapter 1', '9:52'),
          ]))!;
      expect(list.title, 'Essence of linear algebra');
      expect(list.videos.map((v) => v.id), ['fNk_zzaMoSs', 'k7RM-ot2NWY']);
      expect(list.videos.map((v) => v.seconds), [592, 3723]);
    });

    test('reads the older playlistVideoRenderer shape', () {
      final list = YouTubeService.parsePlaylist('PL1', {
        'contents': [
          {
            'playlistVideoRenderer': {
              'videoId': 'ZA-tUyM_y7s',
              'title': {
                'runs': [
                  {'text': '1. Algorithms '},
                  {'text': 'and Computation'}
                ]
              },
              'lengthSeconds': '2738',
            }
          }
        ],
        'header': {
          'playlistHeaderRenderer': {
            'title': {'simpleText': 'MIT 6.006'}
          }
        },
      })!;
      expect(list.title, 'MIT 6.006');
      expect(list.videos.single.title, '1. Algorithms and Computation');
      expect(list.videos.single.seconds, 2738);
    });

    test('ignores videos outside the playlist contents', () {
      final data = _browse([]);
      data['sidebar'] = {
        'items': [_lockup('fNk_zzaMoSs', 'Recommended', '3:00')]
      };
      expect(YouTubeService.parsePlaylist('PL1', data), isNull);
    });

    test('reads the RSS feed', () {
      final list = YouTubeService.parsePlaylistFeed('PL1', _feed)!;
      expect(list.title, 'Essence of linear algebra');
      expect(list.videos.map((v) => v.title),
          ['Vectors | Chapter 1', 'Span & basis']);
    });

    test('falls back to the feed when the browse call is refused', () async {
      final yt = YouTubeService(
        client: MockClient((req) async => req.url.path.contains('browse')
            ? http.Response('{"error":{}}', 400)
            : http.Response(_feed, 200)),
      );
      final list = await yt.playlist('PL1');
      expect(list.videos, hasLength(2));
    });

    test('a playlist nobody can see is a clear error', () async {
      final yt = YouTubeService(
        client: MockClient((req) async => req.url.path.contains('browse')
            ? http.Response('{"error":{}}', 400)
            : http.Response('', 404)),
      );
      await expectLater(
          yt.playlist('PL1'),
          throwsA(isA<YouTubeException>()
              .having((e) => e.message, 'message', contains('private'))));
    });
  });

  group('transcript()', () {
    YouTubeService player(Map<String, Object?> body, {String captions = ''}) =>
        YouTubeService(
          client: MockClient((req) async => req.url.path.endsWith('/player')
              ? http.Response(jsonEncode(body), 200)
              : http.Response(captions, 200)),
        );

    test('reads the chosen track', () async {
      final yt = player({
        'playabilityStatus': {'status': 'OK'},
        'videoDetails': {'title': 'Vectors', 'lengthSeconds': '591'},
        'captions': {
          'playerCaptionsTracklistRenderer': {
            'captionTracks': [
              {
                'baseUrl': 'https://www.youtube.com/api/timedtext?v=1&fmt=srv3',
                'languageCode': 'en'
              },
            ]
          }
        },
      }, captions: '<transcript><text start="1">Hi</text></transcript>');
      final t = await yt.transcript('fNk_zzaMoSs');
      expect(t.video.title, 'Vectors');
      expect(t.video.seconds, 591);
      expect(t.hasCaptions, isTrue);
      expect(t.lines.single.text, 'Hi');
    });

    test('no tracks is a transcript without captions, not an error', () async {
      final yt = player({
        'playabilityStatus': {'status': 'OK'},
        'videoDetails': {'title': 'Silent'},
      });
      final t = await yt.transcript('fNk_zzaMoSs');
      expect(t.hasCaptions, isFalse);
      expect(t.video.title, 'Silent');
    });

    test('a video YouTube won\'t play says why', () async {
      final yt = player({
        'playabilityStatus': {'status': 'LOGIN_REQUIRED'},
      });
      await expectLater(
          yt.transcript('fNk_zzaMoSs'),
          throwsA(isA<YouTubeException>()
              .having((e) => e.message, 'message', contains('sign-in'))));
    });
  });

  group('OnboardingStore.importYouTube', () {
    const listLink =
        YouTubeLink(playlistId: 'PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab');
    List<String> ids(int n) =>
        [for (var i = 0; i < n; i++) 'vid${i.toString().padLeft(8, '0')}'];

    test(
        'a long playlist is one library item, read three at a time in the '
        'background', () async {
      // One slot left: the old one-row-per-video import would have stopped
      // after a single video.
      final repo = _Materials(existing: [
        for (var i = 0; i < OnboardingStore.maxMaterials - 1; i++) _file('f$i'),
      ]);
      final videos = ids(30);
      final youtube = _YouTube(
        videos: videos,
        silent: {videos[4]},
        unavailable: {videos[9]},
        delay: const Duration(milliseconds: 5),
      );
      final store = OnboardingStore(materials: repo, youtube: youtube);
      await store.load();

      final result = await store.importYouTube(listLink);
      expect(result!.summary,
          startsWith('Reading 30 videos from "Essence" — about 2 minutes'));
      expect(store.readingPlaylists, isTrue);
      await store.whenIdle();

      final playlist = store.playlists.single;
      expect(store.itemCount, OnboardingStore.maxMaterials);
      expect(store.atLimit, isTrue);
      final progress = store.progressOf(playlist);
      expect(progress.ready, 28);
      expect(progress.skipped, 2);
      expect(progress.pending, 0);
      expect(repo.skipped[playlist.id], {videos[4], videos[9]});
      expect(youtube.mostAtOnce, OnboardingStore.parallelVideos);
      // In playlist order, whatever order they finished in.
      expect(store.videosOf(playlist).map((m) => m.title), [
        for (final v in videos)
          if (v != videos[4] && v != videos[9]) 'Video $v'
      ]);
      expect(repo.stored[videos[0]], contains('[0:01] words'));
      expect(store.standalone, hasLength(OnboardingStore.maxMaterials - 1));
      expect(store.error, isNull);
      expect(store.readingPlaylists, isFalse);
    });

    test('no signal pauses it, and resuming carries on where it stopped',
        () async {
      final repo = _Materials();
      final videos = ids(12);
      final youtube = _YouTube(videos: videos, flaky: {videos[5]});
      final store = OnboardingStore(materials: repo, youtube: youtube);
      await store.load();

      await store.importYouTube(listLink);
      await store.whenIdle();
      final playlist = store.playlists.single;
      expect(store.error, contains('Paused'));
      expect(store.progressOf(playlist).pending, greaterThan(0));
      expect(repo.skipped[playlist.id] ?? const {}, isEmpty,
          reason: 'a dropped connection is not the video\'s fault');

      await store.resumeImports();
      await store.whenIdle();
      expect(store.progressOf(playlist).pending, 0);
      expect(store.progressOf(playlist).ready, 12);
      expect(store.error, isNull);
    });

    test('a busy AI makes the videos wait and go again instead of failing',
        () async {
      final repo = _Materials(busyFor: 4);
      final store = OnboardingStore(
        materials: repo,
        youtube: _YouTube(videos: ids(9)),
        busyAiCooldown: const Duration(milliseconds: 20),
      );
      await store.load();

      await store.importYouTube(listLink);
      await store.whenIdle();

      final progress = store.progressOf(store.playlists.single);
      expect(progress.ready, 9);
      expect(progress.failed, 0);
      expect(repo.busyAnswers, 4);
      expect(store.error, isNull);
    });

    test('a limit that never clears pauses with the videos still queued',
        () async {
      final repo = _Materials(busyFor: 1000);
      final store = OnboardingStore(
        materials: repo,
        youtube: _YouTube(videos: ids(5)),
        busyAiCooldown: const Duration(milliseconds: 10),
      );
      await store.load();

      await store.importYouTube(listLink);
      await store.whenIdle();
      final playlist = store.playlists.single;
      expect(store.error, contains('free limit'));
      expect(store.progressOf(playlist).failed, 0,
          reason: 'a busy AI is not the video\'s fault');
      expect(store.progressOf(playlist).ready, 0);

      repo.busyFor = 0;
      await store.resumeImports();
      await store.whenIdle();
      expect(store.progressOf(playlist).ready, 5);
      expect(store.error, isNull);
    });

    test('Retry puts a playlist\'s failed videos back through the reader',
        () async {
      final playlist = MaterialPlaylist(
        id: 'pl1',
        youtubeId: 'PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab',
        title: 'Essence',
        videoIds: ids(3),
      );
      final repo = _Materials(
        existing: [
          for (final v in ids(3))
            _video('m-$v', v, playlistId: 'pl1', status: IngestStatus.failed),
        ],
        playlists: [playlist],
      );
      final store = OnboardingStore(materials: repo, youtube: _YouTube());
      await store.load();
      expect(store.progressOf(playlist).failed, 3);

      await store.retryFailed(store.playlists.single);
      await store.whenIdle();

      expect(store.progressOf(store.playlists.single).ready, 3);
      expect(repo.resets, 1);
    });

    test('pasting the same playlist again carries on instead of doubling it',
        () async {
      final videos = ids(6);
      final store = OnboardingStore(
          materials: _Materials(),
          youtube: _YouTube(videos: videos, flaky: {videos[3]}));
      await store.load();
      await store.importYouTube(listLink);
      await store.whenIdle();

      final again = await store.importYouTube(listLink);
      expect(again!.resumed, isTrue);
      expect(again.summary, startsWith('Carrying on with "Essence"'));
      await store.whenIdle();
      expect(store.playlists, hasLength(1));
      expect(store.progressOf(store.playlists.single).ready, 6);

      expect(await store.importYouTube(listLink), isNull);
      expect(store.error, contains('already in your library'));
    });

    test('at launch it reads videos that were stored but never read', () async {
      final playlist = MaterialPlaylist(
        id: 'pl1',
        youtubeId: 'PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab',
        title: 'Essence',
        videoIds: const ['fNk_zzaMoSs'],
      );
      final repo = _Materials(
        existing: [
          _video('m1', 'fNk_zzaMoSs',
              playlistId: 'pl1', status: IngestStatus.uploaded),
        ],
        playlists: [playlist],
      );
      final store = OnboardingStore(materials: repo, youtube: _YouTube());

      await store.resumeImports();
      await store.whenIdle();
      expect(repo.ingested, ['m1']);
      expect(store.progressOf(store.playlists.single).ready, 1);
    });

    test('a video removed from a playlist is not read back in', () async {
      final repo = _Materials();
      final store =
          OnboardingStore(materials: repo, youtube: _YouTube(videos: ids(3)));
      await store.load();
      await store.importYouTube(listLink);
      await store.whenIdle();
      final playlist = store.playlists.single;

      await store.removeMaterial(store.videosOf(playlist).first);
      await store.resumeImports();
      await store.whenIdle();

      expect(store.videosOf(store.playlists.single), hasLength(2));
      expect(repo.skipped[playlist.id], {ids(3).first});
    });

    test('removing a playlist removes its videos and their transcripts',
        () async {
      final repo = _Materials(existing: [_file('f0')]);
      final store =
          OnboardingStore(materials: repo, youtube: _YouTube(videos: ids(4)));
      await store.load();
      await store.importYouTube(listLink);
      await store.whenIdle();

      expect(await store.removePlaylist(store.playlists.single), isTrue);
      expect(store.playlists, isEmpty);
      expect(store.uploaded.map((m) => m.id), ['f0']);
      expect(repo.deletedPaths, hasLength(4));
      expect(store.itemCount, 1);
    });

    test('a single video without captions is an error and adds nothing',
        () async {
      final repo = _Materials();
      final store = OnboardingStore(
        materials: repo,
        youtube: _YouTube(silent: {'fNk_zzaMoSs'}),
      );

      final result = await store
          .importYouTube(YouTubeLink.parse('https://youtu.be/fNk_zzaMoSs')!);

      expect(result, isNull);
      expect(store.error, contains('has no captions'));
      expect(repo.stored, isEmpty);
    });

    test('a single video takes a slot, so it is refused at the limit',
        () async {
      final store = OnboardingStore(
        materials: _Materials(existing: [
          for (var i = 0; i < OnboardingStore.maxMaterials; i++) _file('f$i'),
        ]),
        youtube: _YouTube(),
      );
      await store.load();

      expect(
          await store.importYouTube(
              YouTubeLink.parse('https://youtu.be/fNk_zzaMoSs')!),
          isNull);
      expect(store.error, contains('20 items'));
    });

    test('"just this video" ignores the playlist', () async {
      final repo = _Materials();
      final store = OnboardingStore(
          materials: repo, youtube: _YouTube(videos: ['k7RM-ot2NWY']));

      final result = await store.importYouTube(
        const YouTubeLink(
            videoId: 'fNk_zzaMoSs',
            playlistId: 'PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab'),
        wholePlaylist: false,
      );

      expect(result!.summary, 'Video added');
      expect(repo.stored.keys, ['fNk_zzaMoSs']);
      expect(store.playlists, isEmpty);
    });

    test('a playlist that will not open is the error shown', () async {
      final store = OnboardingStore(
          materials: _Materials(), youtube: _YouTube(playlistFails: true));

      final result = await store.importYouTube(listLink);

      expect(result, isNull);
      expect(store.error, contains('private'));
      expect(store.addingLink, isFalse);
      expect(store.playlists, isEmpty);
    });
  });

  group('link sheet', () {
    // The sheet that crashed: its controller used to be disposed the moment
    // the sheet's future completed, while the field was still animating out —
    // "A TextEditingController was used after being disposed", then
    // '_dependents.isEmpty': is not true. Any exception fails these tests.
    Future<OnboardingStore> open(WidgetTester tester, _YouTube youtube) async {
      final store = OnboardingStore(materials: _Materials(), youtube: youtube);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => addVideoLink(context,
                    toast: (m) => ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(m)))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('adding a playlist closes cleanly and says what it started',
        (tester) async {
      final store =
          await open(tester, _YouTube(videos: ['fNk_zzaMoSs', 'k7RM-ot2NWY']));
      await tester.enterText(find.byType(TextField),
          'https://youtube.com/playlist?list=PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab');
      await tester.tap(find.text('Add link'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Reading 2 videos from "Essence"'),
          findsOneWidget);
      expect(store.uploaded, hasLength(2));
      expect(store.itemCount, 1);
    });

    testWidgets('dismissing the sheet closes cleanly', (tester) async {
      await open(tester, _YouTube());
      await tester.enterText(find.byType(TextField), 'half typed');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a video inside a playlist asks which one was meant',
        (tester) async {
      final store = await open(tester, _YouTube(videos: ['k7RM-ot2NWY']));
      await tester.enterText(
          find.byType(TextField),
          'https://www.youtube.com/watch?v=fNk_zzaMoSs'
          '&list=PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab');
      await tester.tap(find.text('Add link'));
      await tester.pumpAndSettle();

      expect(find.text('This video is part of a playlist'), findsOneWidget);
      await tester.tap(find.text('Just this video'));
      await tester.pumpAndSettle();
      expect(find.text('Video added'), findsOneWidget);
      expect(store.uploaded.single.externalUrl, contains('fNk_zzaMoSs'));
    });
  });
}

Map<String, dynamic> _browse(List<Map<String, dynamic>> lockups) => {
      'contents': {
        'twoColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {'contents': lockups}
              }
            }
          ]
        }
      },
      'metadata': {
        'playlistMetadataRenderer': {'title': 'Essence of linear algebra'}
      },
    };

Map<String, dynamic> _lockup(String id, String title, String? badge) => {
      'lockupViewModel': {
        'contentId': id,
        'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
        'contentImage': {
          'thumbnailViewModel': {
            'overlays': [
              {
                'thumbnailBottomOverlayViewModel': {
                  'badges': [
                    if (badge != null)
                      {
                        'thumbnailBadgeViewModel': {'text': badge}
                      }
                  ]
                }
              }
            ]
          }
        },
        'metadata': {
          'lockupMetadataViewModel': {
            'title': {'content': title}
          }
        },
      }
    };

const _feed = '<?xml version="1.0" encoding="UTF-8"?>'
    '<feed><title>Essence of linear algebra</title>'
    '<author><name>3Blue1Brown</name></author>'
    '<entry><yt:videoId>fNk_zzaMoSs</yt:videoId>'
    '<title>Vectors | Chapter 1</title></entry>'
    '<entry><yt:videoId>k7RM-ot2NWY</yt:videoId>'
    '<title>Span &amp; basis</title></entry>'
    '</feed>';

StudyMaterial _video(
  String id,
  String videoId, {
  String? playlistId,
  IngestStatus status = IngestStatus.embedded,
}) =>
    StudyMaterial(
      id: id,
      sourceType: MaterialType.videoLink,
      title: videoId,
      storagePath: 'u/$videoId.txt',
      externalUrl: 'https://www.youtube.com/watch?v=$videoId',
      status: status,
      playlistId: playlistId,
    );

StudyMaterial _file(String id) => StudyMaterial(
      id: id,
      sourceType: MaterialType.notes,
      title: '$id.pdf',
      storagePath: 'u/$id.pdf',
      status: IngestStatus.embedded,
    );

/// Videos that play. [silent] ones have no captions, [unavailable] ones won't
/// play, and [flaky] ones fail once as if the signal dropped.
class _YouTube extends YouTubeService {
  _YouTube({
    this.videos = const [],
    this.silent = const {},
    this.unavailable = const {},
    Set<String> flaky = const {},
    this.playlistFails = false,
    this.delay,
  }) : _flaky = {...flaky};

  final List<String> videos;
  final Set<String> silent;
  final Set<String> unavailable;
  final Set<String> _flaky;
  final bool playlistFails;
  final Duration? delay;

  int _active = 0;

  /// The most transcripts fetched at the same time.
  int mostAtOnce = 0;

  @override
  Future<YouTubePlaylist> playlist(String id) async {
    if (playlistFails) {
      throw const YouTubeException('That playlist is private.');
    }
    return YouTubePlaylist(id: id, title: 'Essence', videos: [
      for (final v in videos) YouTubeVideo(id: v, title: 'Video $v'),
    ]);
  }

  @override
  Future<YouTubeTranscript> transcript(String videoId) async {
    _active++;
    if (_active > mostAtOnce) mostAtOnce = _active;
    try {
      final wait = delay;
      if (wait != null) await Future<void>.delayed(wait);
      if (_flaky.remove(videoId)) {
        throw const YouTubeException("Couldn't reach YouTube.",
            retryable: true);
      }
      if (unavailable.contains(videoId)) {
        throw const YouTubeException("That video isn't available.");
      }
      return YouTubeTranscript(
        video: YouTubeVideo(id: videoId, title: 'Video $videoId'),
        lines: silent.contains(videoId)
            ? const []
            : const [CaptionLine(1, 'words')],
      );
    } finally {
      _active--;
    }
  }
}

/// Keeps materials, playlists and transcripts in memory. Ingest succeeds,
/// except that the first [busyFor] calls get the AI's 429 — and, like the
/// real function, leave the row `failed`.
class _Materials extends MaterialRepository {
  _Materials({
    List<StudyMaterial> existing = const [],
    List<MaterialPlaylist> playlists = const [],
    this.busyFor = 0,
  })  : rows = [...existing],
        lists = [...playlists];

  int busyFor;
  int busyAnswers = 0;
  int resets = 0;

  final List<StudyMaterial> rows;
  final List<MaterialPlaylist> lists;
  final stored = <String, String>{};
  final ingested = <String>[];
  final skipped = <String, Set<String>>{};
  final deletedPaths = <String>[];

  @override
  Future<List<StudyMaterial>> getMaterials({String? goalId}) async => [...rows];

  @override
  Future<List<MaterialPlaylist>> getPlaylists() async => [...lists];

  @override
  Future<MaterialPlaylist> createPlaylist({
    required String youtubeId,
    required String title,
    required List<String> videoIds,
  }) async {
    final playlist = MaterialPlaylist(
        id: 'pl-$youtubeId',
        youtubeId: youtubeId,
        title: title,
        videoIds: videoIds);
    lists.add(playlist);
    return playlist;
  }

  @override
  Future<void> setSkipped(String playlistId, Set<String> skipped) async {
    this.skipped[playlistId] = {...skipped};
  }

  @override
  Future<void> deletePlaylist(
      MaterialPlaylist playlist, List<String> storagePaths) async {
    lists.removeWhere((p) => p.id == playlist.id);
    rows.removeWhere((m) => m.playlistId == playlist.id);
    deletedPaths.addAll(storagePaths);
  }

  @override
  Future<void> deleteMaterial(StudyMaterial material) async {
    rows.removeWhere((m) => m.id == material.id);
  }

  @override
  Future<StudyMaterial> addVideoTranscript({
    required String videoId,
    required String title,
    required String transcript,
    String? playlistId,
    String? goalId,
  }) async {
    stored[videoId] = transcript;
    final row = StudyMaterial(
      id: 'new-$videoId',
      sourceType: MaterialType.videoLink,
      title: title,
      storagePath: 'u/$videoId.txt',
      externalUrl: 'https://www.youtube.com/watch?v=$videoId',
      playlistId: playlistId,
    );
    rows.add(row);
    return row;
  }

  @override
  Future<int> requestIngest(String materialId) async {
    final i = rows.indexWhere((m) => m.id == materialId);
    if (busyFor > 0) {
      busyFor--;
      busyAnswers++;
      rows[i] = rows[i].withStatus(IngestStatus.failed);
      throw const FunctionException(status: 429, details: {
        'error': 'The AI is busy right now. Try again in a minute.'
      });
    }
    ingested.add(materialId);
    rows[i] = rows[i].withStatus(IngestStatus.embedded);
    return 3;
  }

  @override
  Future<StudyMaterial> retryIngest(String materialId) async {
    final i = rows.indexWhere((m) => m.id == materialId);
    rows[i] = rows[i].withStatus(IngestStatus.uploaded);
    return rows[i];
  }

  @override
  Future<void> resetFailed(String playlistId) async {
    resets++;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].playlistId == playlistId &&
          rows[i].status == IngestStatus.failed) {
        rows[i] = rows[i].withStatus(IngestStatus.uploaded);
      }
    }
  }

  @override
  Future<StudyMaterial?> getMaterial(String id) async =>
      rows.where((m) => m.id == id).firstOrNull;
}
