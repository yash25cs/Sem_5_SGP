// The home-screen widgets' Dart side: the links a widget tap opens, the exam
// lines the countdown reads, the midnight redraws, and the Settings sheet
// that previews and adds them. The Android layouts themselves are checked by
// the APK build (aapt) and on a phone.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/services/home_widget_sync.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/home_widgets_sheet.dart';

void main() {
  group('WidgetTarget.fromUri', () {
    test('reads every link WidgetLinks makes', () {
      for (final target in WidgetTarget.values) {
        expect(
            WidgetTarget.fromUri(
                Uri.parse('studytrail://widget/${target.name}')),
            target);
      }
    });

    test('ignores links that aren\'t a widget\'s', () {
      for (final uri in [
        null,
        Uri.parse('studytrail://widget/'),
        Uri.parse('studytrail://widget/settings'),
        Uri.parse('studytrail://other/focus'),
        // The sign-in callback arrives on the same activity.
        Uri.parse('in.charusat.studytrail://login-callback?code=abc'),
      ]) {
        expect(WidgetTarget.fromUri(uri), isNull, reason: '$uri');
      }
    });
  });

  group('HomeWidgetSync.examLines', () {
    test('one dated line per subject paper, in the order given', () {
      expect(
          HomeWidgetSync.examLines([
            ('Maths', DateTime(2026, 11, 3)),
            ('Physics', DateTime(2026, 11, 20)),
          ]),
          '2026-11-03\tMaths\n2026-11-20\tPhysics');
    });

    test('skips undated and unnamed subjects; nothing left is null', () {
      expect(
          HomeWidgetSync.examLines([
            ('Chemistry', null),
            ('  ', DateTime(2026, 11, 1)),
          ]),
          isNull);
      expect(HomeWidgetSync.examLines(const []), isNull);
    });

    test('a tab or newline in a name can\'t split the line', () {
      expect(HomeWidgetSync.examLines([('Lab\tWork\nII', DateTime(2026, 1, 5))]),
          '2026-01-05\tLab Work II');
    });
  });

  test('redraws just after each of the next seven midnights', () {
    final times = HomeWidgetSync.midnights(DateTime(2026, 10, 30, 22, 15));
    expect(times, hasLength(7));
    expect(times.first, DateTime(2026, 10, 31, 0, 1));
    // Across the month end.
    expect(times[1], DateTime(2026, 11, 1, 0, 1));
    expect(times.last, DateTime(2026, 11, 6, 0, 1));
  });

  testWidgets('the widgets sheet previews all three and fits a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => HomeStore(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => HomeWidgetsSheet.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // Not pumpAndSettle: the streak preview's light circles forever.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Home-screen widgets'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Exam countdown'), findsOneWidget);
    expect(find.text('Streak'), findsOneWidget);
    // Before Home has loaded the previews show samples, not blanks.
    expect(find.text('12 days'), findsOneWidget);
    expect(find.text('day streak'), findsOneWidget);
    // Tests don't run on Android, so there's no launcher to add to: the
    // sheet explains the manual way instead of showing Add buttons.
    expect(find.text('Add'), findsNothing);
    expect(find.textContaining('Long-press an empty spot'), findsOneWidget);

    // The task line moves on to the next task.
    expect(find.text('Next · Revise Unit 2 notes'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Then · Practice quiz: Optics'), findsOneWidget);
  });
}
