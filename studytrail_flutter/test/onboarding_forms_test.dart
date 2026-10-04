// The two onboarding forms after D-041: the goal form starts with no subjects
// and takes an exam date with each one, and the academic form picks a program
// from a list (School asks for a class) and no longer asks for an enrollment
// ID.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/academic_profile_screen.dart';
import 'package:studytrail_flutter/screens/set_target_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    List<ChangeNotifierProvider> providers) async {
  // A narrow phone, so an overflow in the new rows fails the test.
  tester.view.physicalSize = const Size(320 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: providers,
    child: MaterialApp(theme: AppTheme.light(), home: child),
  ));
  await tester.pumpAndSettle();
}

/// Picks day [day] in the month the date picker opens on (30 days out) and
/// returns that date.
Future<DateTime> _pickDay(WidgetTester tester, int day) async {
  await tester.pumpAndSettle();
  final shown = DateTime.now().add(const Duration(days: 30));
  await tester.tap(find.text('$day'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  return DateTime(shown.year, shown.month, day);
}

Finder _sheetField() => find.descendant(
    of: find.byType(BottomSheet), matching: find.byType(TextField));

void main() {
  group('Set target', () {
    testWidgets('starts with no subjects and won\'t save without one',
        (tester) async {
      final goals = _FakeGoals();
      await _pump(tester, const SetTargetScreen(), [
        ChangeNotifierProvider<OnboardingStore>(
            create: (_) => OnboardingStore(goals: goals)),
      ]);

      expect(find.text('Add your first subject'), findsOneWidget);
      for (final old in ['DBMS', 'OS', 'Networks']) {
        expect(find.text(old), findsNothing);
      }

      await tester.enterText(find.byType(TextFormField), 'Semester exams');
      await tester.tap(find.text('Generate my roadmap'));
      await tester.pumpAndSettle();

      expect(find.text('Add at least one subject with its exam date'),
          findsOneWidget);
      expect(goals.calls, 0);
    });

    testWidgets('each subject is added with its exam date, in exam order',
        (tester) async {
      final goals = _FakeGoals();
      final store = OnboardingStore(goals: goals);
      await _pump(tester, const SetTargetScreen(), [
        ChangeNotifierProvider<OnboardingStore>.value(value: store),
      ]);
      await tester.enterText(find.byType(TextFormField), 'Semester exams');

      // The sheet wants both a name and a date.
      await tester.tap(find.text('Add your first subject'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add subject'));
      await tester.pump();
      expect(find.text('Enter the subject name'), findsOneWidget);

      await tester.enterText(_sheetField(), 'Physics');
      await tester.tap(find.text('Add subject'));
      await tester.pump();
      expect(find.text('Pick the exam date'), findsOneWidget);

      await tester.tap(find.text('Pick a date'));
      final physics = await _pickDay(tester, 20);
      await tester.tap(find.text('Add subject'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Physics'), findsOneWidget);

      // A second, earlier paper goes above it.
      await tester.tap(find.text('Add another subject'));
      await tester.pumpAndSettle();
      await tester.enterText(_sheetField(), 'Maths');
      await tester.tap(find.text('Pick a date'));
      final maths = await _pickDay(tester, 10);
      await tester.tap(find.text('Add subject'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Maths')).dy,
          lessThan(tester.getTopLeft(find.text('Physics')).dy));

      // The same name twice is refused in the sheet, with the reason.
      await tester.tap(find.text('Add another subject'));
      await tester.pumpAndSettle();
      await tester.enterText(_sheetField(), 'physics');
      await tester.tap(find.text('Add subject'));
      await tester.pump();
      expect(find.text('physics is already added'), findsOneWidget);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate my roadmap'));
      await tester.pumpAndSettle();

      expect(goals.lastSubjects, ['Maths', 'Physics']);
      expect(goals.lastSubjectDates, [maths, physics]);
      // The goal runs to the last paper.
      expect(goals.lastExamDate, physics);
    });
  });

  group('Academic details', () {
    testWidgets('no enrollment field; School asks for a class, not a branch',
        (tester) async {
      await _pump(tester, const AcademicProfileScreen(), [
        ChangeNotifierProvider<ProfileStore>(
            create: (_) => ProfileStore(
                profiles: _FakeProfiles(const Profile(id: 'me')),
                goals: _FakeGoals())),
      ]);

      expect(find.textContaining('Enrollment'), findsNothing);
      expect(find.textContaining('Roll'), findsNothing);
      expect(find.text('Enter your full name'), findsOneWidget);

      // Nothing picked yet: Save says what's missing.
      await tester.tap(find.text('Save & Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Select your program'), findsWidgets);

      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      // Grouped by field; the menu builds lazily, so only the first headings
      // are on screen.
      expect(find.text('SCHOOL'), findsOneWidget);
      expect(find.text('SCIENCE & TECHNOLOGY'), findsOneWidget);
      await tester.tap(find.text('School').last);
      await tester.pumpAndSettle();

      expect(find.text('School Name'), findsOneWidget);
      expect(find.text('Enter your school name'), findsOneWidget);
      expect(find.text('Class'), findsOneWidget);
      expect(find.text('Branch / Major (optional)'), findsNothing);
      expect(find.text('Select your class'), findsWidgets);

      await tester.tap(find.byType(DropdownButton<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class 5').last);
      await tester.pumpAndSettle();
      expect(find.text('Class 5'), findsOneWidget);
    });

    testWidgets('a profile typed before the dropdown opens as Other',
        (tester) async {
      await _pump(tester, const AcademicProfileScreen(isEditing: true), [
        ChangeNotifierProvider<ProfileStore>(
            create: (_) => ProfileStore(
                profiles: _FakeProfiles(const Profile(
                    id: 'me',
                    fullName: 'A Student',
                    college: 'Some College',
                    branch: 'B.Tech Computer Engineering · Semester 5')),
                goals: _FakeGoals())),
      ]);

      expect(find.text('Other'), findsOneWidget);
      expect(find.text('B.Tech Computer Engineering'), findsOneWidget);
      expect(find.text('Semester 5'), findsOneWidget);
    });
  });

  group('AcademicPlace', () {
    test('round-trips each kind of program', () {
      final places = [
        const AcademicPlace(
            program: AcademicProgram.school, term: 'Class 10'),
        AcademicPlace(
            program: AcademicProgram.byName('B.Tech / B.E.')!,
            specialisation: 'Computer Engineering',
            term: 'Semester 5'),
        AcademicPlace(
            program: AcademicProgram.byName('CA (Chartered Accountancy)')!,
            term: 'Intermediate'),
        const AcademicPlace(
            program: AcademicProgram.other,
            customProgram: 'Pilot Training',
            term: 'Semester 2'),
      ];
      for (final place in places) {
        final back = AcademicPlace.parse(place.format())!;
        expect(back.program.name, place.program.name);
        expect(back.customProgram, place.customProgram);
        expect(back.specialisation, place.specialisation);
        expect(back.term, place.term);
      }
      expect(places.first.format(), 'School · Class 10');
    });

    test('school drops a branch; a typed "·" can\'t split a part', () {
      expect(
          const AcademicPlace(
                  program: AcademicProgram.school,
                  specialisation: 'Science',
                  term: 'Class 12')
              .format(),
          'School · Class 12');
      expect(
          const AcademicPlace(
                  program: AcademicProgram.other,
                  customProgram: 'A · B',
                  term: 'Semester 1')
              .format(),
          'A - B · Semester 1');
      expect(AcademicPlace.parse(''), isNull);
      expect(AcademicPlace.parse(null), isNull);
    });

    test('every program has terms and a unique name', () {
      final names = <String>{};
      for (final (_, programs) in AcademicProgram.groups) {
        for (final program in programs) {
          expect(names.add(program.name), isTrue, reason: program.name);
          expect(program.options, isNotEmpty, reason: program.name);
          expect(program.name.contains('·'), isFalse, reason: program.name);
        }
      }
    });
  });
}

class _FakeGoals extends GoalRepository {
  int calls = 0;
  List<String>? lastSubjects;
  List<DateTime?>? lastSubjectDates;
  DateTime? lastExamDate;

  @override
  Future<List<Goal>> getGoals() async => const [];

  @override
  Future<Goal> createGoal({
    required String name,
    DateTime? examDate,
    Pace pace = Pace.steady,
    List<String> subjectNames = const [],
    List<DateTime?> subjectExamDates = const [],
  }) async {
    calls++;
    lastSubjects = subjectNames;
    lastSubjectDates = subjectExamDates;
    lastExamDate = examDate;
    return Goal(id: 'goal-1', name: name, examDate: examDate);
  }
}

class _FakeProfiles extends ProfileRepository {
  const _FakeProfiles(this.profile);
  final Profile profile;

  @override
  Future<Profile?> getMyProfile() async => profile;

  @override
  Future<List<Map<String, dynamic>>> getClasses() async => const [];
}
