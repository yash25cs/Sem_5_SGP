// Settings and the onboarding material step at 320 dp, with the rows added
// for the reminder time, custom pace and calendar sync.

import 'dart:async';

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/settings_screen.dart';
import 'package:studytrail_flutter/screens/upload_material_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/theme/theme_controller.dart';

Future<void> _pumpNarrow(WidgetTester tester, Widget child,
    List<ChangeNotifierProvider> providers) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(320 * 3, 720 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: providers,
    child: MaterialApp(theme: AppTheme.light(), home: child),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Settings fits with a custom pace, reminder and calendar rows',
      (tester) async {
    await _pumpNarrow(tester, const SettingsScreen(), [
      ChangeNotifierProvider<ProfileStore>(
          create: (_) =>
              ProfileStore(profiles: const _Profiles(), goals: _Goals())),
      ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
      ChangeNotifierProvider<HomeStore>(create: (_) => HomeStore()),
      ChangeNotifierProvider<AuthStore>(
          create: (_) => AuthStore(repo: _Auth())),
    ]);

    expect(find.byKey(const ValueKey('settings-reminder')), findsOneWidget);
    expect(find.text('Class'), findsNothing);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-calendar')), 200);
    expect(find.text('Custom · 2.5 hrs/day'), findsOneWidget);
    expect(find.text('Exams & plan'), findsOneWidget);
  });

  testWidgets('Privacy and Help open from Settings and fit', (tester) async {
    await _pumpNarrow(tester, const SettingsScreen(), [
      ChangeNotifierProvider<ProfileStore>(
          create: (_) =>
              ProfileStore(profiles: const _Profiles(), goals: _Goals())),
      ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
      ChangeNotifierProvider<HomeStore>(create: (_) => HomeStore()),
      ChangeNotifierProvider<AuthStore>(
          create: (_) => AuthStore(repo: _Auth())),
    ]);

    await tester.scrollUntilVisible(find.text('Help'), 200);
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How do I earn XP?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ranks every student'), findsOneWidget);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Privacy & security'));
    await tester.pumpAndSettle();
    expect(find.text('Who else can see it'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Deleting your data'), 300);
    expect(find.textContaining('yash@'), findsNothing);
  });

  testWidgets('the material step fits with the reminder card', (tester) async {
    await _pumpNarrow(tester, const UploadMaterialScreen(), [
      ChangeNotifierProvider<OnboardingStore>(
          create: (_) => OnboardingStore(materials: const _Materials())),
    ]);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reminder-time')), 200);
    expect(find.text('Daily study reminder'), findsOneWidget);
    expect(find.textContaining('Every day at'), findsOneWidget);
  });
}

class _Profiles extends ProfileRepository {
  const _Profiles();
  @override
  Future<Profile?> getMyProfile() async =>
      const Profile(id: 'u', fullName: 'A student', email: 'a@b.c');
  @override
  Future<Set<String>> getHeldRewards() async => const {};
}

class _Goals extends GoalRepository {
  @override
  Future<List<Goal>> getGoals() async => [
        Goal(
            id: 'g',
            name: 'Semester 5 end-semester examinations',
            examDate: DateTime.now().add(const Duration(days: 30)),
            dailyMinutes: 150),
      ];
}

class _Materials extends MaterialRepository {
  const _Materials();
  @override
  Future<List<StudyMaterial>> getMaterials({String? goalId}) async => const [];
  @override
  Future<List<MaterialPlaylist>> getPlaylists() async => const [];
}

class _Auth extends AuthRepository {
  final _events = StreamController<AuthState>.broadcast();
  @override
  Stream<AuthState> get authStateChanges => _events.stream;
  @override
  bool get isSignedIn => true;
}
