// Widget and transport tests: what renders before any network call happens, the
// HTTP timeout wrapper, the two error surfaces, and the generation sheet.
//
// `flutter test` runs without `--dart-define`, so `SupabaseConfig.isConfigured`
// is false and `StudyTrailApp` deliberately shows the config screen rather than
// the onboarding flow (see main.dart). Pumping the app and expecting the welcome
// headline is therefore the wrong assertion — the welcome screen is pumped on
// its own instead, which also keeps this file clear of `Supabase.initialize`.
//
// Store-level tests, with the repositories faked out, live in `stores_test.dart`.

import 'dart:async';

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/config/supabase_config.dart';
import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/data/timeout_http_client.dart';
import 'package:studytrail_flutter/main.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/welcome_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/data_states.dart';
import 'package:studytrail_flutter/widgets/generate_sheet.dart';

void main() {
  testWidgets('Welcome screen renders its headline and Next action',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const WelcomeScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Turn your exams\ninto a plan.'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('App boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const StudyTrailApp());
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);

    // Guarded rather than asserted flat: a run with
    // `--dart-define-from-file=dart_define.json` produces a configured build,
    // and that branch needs a live Supabase, so there is nothing to check here.
    if (!SupabaseConfig.isConfigured) {
      expect(find.text('Backend not configured'), findsOneWidget);
    }
  });

  group('TimeoutHttpClient', () {
    test('gives uploads and AI functions longer than plain queries', () {
      final rest = Uri.parse('https://x.supabase.co/rest/v1/goals');
      final fn = Uri.parse('https://x.supabase.co/functions/v1/chat');
      final storage = Uri.parse('https://x.supabase.co/storage/v1/object/m');

      expect(TimeoutHttpClient.budgetFor(fn),
          greaterThan(TimeoutHttpClient.budgetFor(rest)));
      expect(TimeoutHttpClient.budgetFor(storage),
          greaterThan(TimeoutHttpClient.budgetFor(rest)));
    });

    // The bug this class exists for: a host that accepts the connection and
    // never answers used to leave the app on a spinner indefinitely. Driven by
    // the test clock, so it doesn't actually wait.
    testWidgets('a request that never answers fails instead of hanging',
        (WidgetTester tester) async {
      final client = TimeoutHttpClient(inner: _SilentClient());
      Object? caught;

      final pending = client
          .get(Uri.parse('https://x.supabase.co/rest/v1/goals'))
          .then<void>((_) {}, onError: (Object e) => caught = e);

      await tester.pump(TimeoutHttpClient.budgetFor(
              Uri.parse('https://x.supabase.co/rest/v1/goals')) +
          const Duration(seconds: 1));
      await pending;

      expect(caught, isA<TimeoutException>());
    });
  });

  group('ErrorScreen', () {
    testWidgets('offline blames the connection and retries', (tester) async {
      var retries = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: ErrorScreen(
          message: "Can't reach StudyTrail.",
          offline: true,
          onRetry: () => retries++,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text("Can't reach StudyTrail."), findsOneWidget);
      // No sign-out offline: it would work, but signing back in needs the
      // network that just failed.
      expect(find.text('Sign out'), findsNothing);

      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('a server failure does not blame the student', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: ErrorScreen(
          message: 'This build needs a newer database.',
          onRetry: () {},
          secondaryLabel: 'Sign out',
          onSecondary: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text("You're offline"), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
    });
  });

  group('GenerateSheet', () {
    // Quiz and flashcard generation both read a whole material's chunks, so a
    // file that hasn't been embedded has nothing to generate from and the
    // function refuses it. The sheet must not offer one.
    testWidgets(
        'offers embedded files only, and locks the button until one is picked',
        (tester) async {
      final calls = <String>[];

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => OnboardingStore(materials: const _FakeMaterials())),
          ChangeNotifierProvider(create: (_) => FlashcardStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: GenerateSheet<FlashcardStore>(
              title: 'Generate flashcards',
              subtitle: 'Written from one file you uploaded',
              actionLabel: 'Generate cards',
              unit: 'cards',
              counts: const [10, 20, 30],
              onGenerate: (store, materialId, count) async {
                calls.add('$materialId:$count');
                return false;
              },
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Physics notes.pdf'), findsOneWidget);
      expect(find.text('Half-read.pdf'), findsNothing);
      // The hidden file is still accounted for, so its absence isn't a mystery.
      expect(find.textContaining("isn't readable yet"), findsOneWidget);

      // Nothing picked yet: tapping must not start a generation.
      await tester.tap(find.text('Generate cards'));
      await tester.pump();
      expect(calls, isEmpty);

      await tester.tap(find.text('Physics notes.pdf'));
      await tester.pump();
      await tester.tap(find.text('Generate cards'));
      await tester.pump();

      // 20 is the middle count, preselected.
      expect(calls, ['embedded-1:20']);
    });
  });
}

/// Accepts the request and never responds — a captive portal, or a phone
/// showing full bars with no working data.
class _SilentClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

/// Two files, one usable. Subclassing the repository exercises the store's real
/// [OnboardingStore.load] path without needing a Supabase client.
class _FakeMaterials extends MaterialRepository {
  const _FakeMaterials();

  @override
  Future<List<MaterialPlaylist>> getPlaylists() async => const [];

  @override
  Future<List<StudyMaterial>> getMaterials({String? goalId}) async => const [
        StudyMaterial(
          id: 'embedded-1',
          sourceType: MaterialType.syllabusPdf,
          title: 'Physics notes.pdf',
          status: IngestStatus.embedded,
        ),
        StudyMaterial(
          id: 'processing-1',
          sourceType: MaterialType.notes,
          title: 'Half-read.pdf',
          status: IngestStatus.processing,
        ),
      ];
}
