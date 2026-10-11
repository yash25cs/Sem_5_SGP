// Loading and arrival animations: a button that shows a spinner while
// something is being created, the shared "AI is working" panel, and the
// fade-in a newly created list item arrives with.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/common.dart';
import 'package:studytrail_flutter/widgets/working.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)));

void main() {
  testWidgets('a loading button shows a spinner and ignores taps',
      (tester) async {
    var taps = 0;
    await _pump(
        tester,
        PillButton('Create', loading: true, onTap: () => taps++));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Create'));
    expect(taps, 0);

    await _pump(tester, PillButton('Create', onTap: () => taps++));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Create'));
    expect(taps, 1);
  });

  testWidgets('the AI panel moves through its messages', (tester) async {
    await _pump(
        tester, const AiWorking(messages: ['First step', 'Second step']));
    expect(find.text('First step'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Second step'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new item fades in once and stays put on rebuilds',
      (tester) async {
    double opacity() => tester
        .widget<FadeTransition>(find.descendant(
            of: find.byKey(const ValueKey('a')),
            matching: find.byType(FadeTransition)))
        .opacity
        .value;

    Widget list(List<String> ids) => Column(children: [
          for (final id in ids)
            AppearIn(key: ValueKey(id), child: Text('Item $id')),
        ]);

    await _pump(tester, list(['a']));
    expect(opacity(), lessThan(0.2));
    await tester.pumpAndSettle();
    expect(opacity(), 1);

    // Another item arrives: the first doesn't animate again.
    await _pump(tester, list(['b', 'a']));
    expect(opacity(), 1);
    final b = tester.widget<FadeTransition>(find.descendant(
        of: find.byKey(const ValueKey('b')),
        matching: find.byType(FadeTransition)));
    expect(b.opacity.value, lessThan(0.2));
    await tester.pumpAndSettle();
  });
}
