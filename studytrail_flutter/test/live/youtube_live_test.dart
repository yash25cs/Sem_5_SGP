// YouTubeService against real YouTube — the part the recorded-shape tests in
// test/youtube_test.dart can't prove: that YouTube still answers these calls
// the way it did when they were written. Run from a home or mobile connection;
// from a cloud machine the player call gets a bot check.
//
//   STUDYTRAIL_LIVE=1 flutter test test/live/youtube_live_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studytrail_flutter/services/youtube_service.dart';

final _live = Platform.environment['STUDYTRAIL_LIVE'] == '1';

void main() {
  final yt = YouTubeService();

  test('lists a public playlist in order', () async {
    // 3Blue1Brown's "Essence of linear algebra".
    final list = await yt.playlist('PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab');
    expect(list.title, 'Essence of linear algebra');
    expect(list.videos.length, greaterThanOrEqualTo(15));
    expect(list.videos.first.id, 'fNk_zzaMoSs');
    expect(list.videos.first.seconds, greaterThan(500));
  }, skip: !_live);

  test('reads a lecture transcript with timestamps', () async {
    // MIT 6.006 lecture 1 — about 45 minutes, English captions.
    final t = await yt.transcript('ZA-tUyM_y7s');
    expect(t.video.title, contains('Algorithms'));
    expect(t.language, startsWith('en'));
    expect(t.lines.length, greaterThan(300));
    expect(t.lines.last.start, greaterThan(2000));
    final file = t.toFileText();
    expect(file, startsWith('# '));
    expect(file, contains(RegExp(r'\n\[\d+:\d{2}\] ')));
    expect(file, isNot(contains('&#39;')));
  }, skip: !_live, timeout: const Timeout(Duration(minutes: 1)));

  test('a made-up playlist is a clear error', () async {
    await expectLater(
      yt.playlist('PLxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx1234'),
      throwsA(isA<YouTubeException>()
          .having((e) => e.message, 'message', contains('private'))),
    );
  }, skip: !_live);
}
