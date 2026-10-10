import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Profile and Settings screens: the student's details, their active
/// goal, and class membership.
class ProfileStore extends AsyncStore {
  ProfileStore({ProfileRepository? profiles, GoalRepository? goals})
      : _profiles = profiles ?? const ProfileRepository(),
        _goals = goals ?? const GoalRepository();

  final ProfileRepository _profiles;
  final GoalRepository _goals;

  Profile? _profile;
  List<Goal> _allGoals = const [];
  List<Map<String, dynamic>> _classes = const [];

  Profile? get profile => _profile;

  /// The goal the app works against — the three shortcut rows in Settings edit
  /// this one.
  Goal? get activeGoal => _allGoals.where((g) => g.isActive).firstOrNull;

  /// Every goal the student has, newest first, for the goal manager.
  List<Goal> get allGoals => _allGoals;

  /// Classes the student can join, for the settings picker.
  List<Map<String, dynamic>> get classes => _classes;

  Set<String> _heldRewards = const {};

  /// The Aurora Profile Card reward is owned: the profile card wears it.
  bool get auroraCard => _heldRewards.contains('aurora_profile');

  Future<void> load() => runLoad(() async {
        final results = await Future.wait([
          _profiles.getMyProfile(),
          // The whole list, not just the active one: Settings manages all of
          // them, and the active goal falls out of the same rows.
          _goals.getGoals(),
          // Needed to resolve `class_id` into a name for the Settings row.
          _profiles.getClasses(),
          // Only a look; a failed read keeps the plain card.
          _profiles
              .getHeldRewards()
              .catchError((Object _) => _heldRewards),
        ]);
        _profile = results[0] as Profile?;
        _allGoals = results[1] as List<Goal>;
        _classes = results[2] as List<Map<String, dynamic>>;
        _heldRewards = results[3] as Set<String>;
      });

  Future<bool> updateProfile({
    String? fullName,
    String? enrollmentId,
    String? branch,
    String? college,
  }) =>
      runMutation(() async {
        _profile = await _profiles.updateProfile(
          fullName: fullName,
          enrollmentId: enrollmentId,
          branch: branch,
          college: college,
        );
      });

  Future<bool> setAnswerLanguage(AnswerLanguage language) =>
      runMutation(() async {
        _profile = await _profiles.setAnswerLanguage(language);
      });

  Future<bool> loadClasses() => runMutation(() async {
        _classes = await _profiles.getClasses();
      });

  Future<bool> joinClass(String classId) => runMutation(() async {
        await _profiles.joinClass(classId);
        _profile = await _profiles.getMyProfile();
      });

  Future<bool> leaveClass() => runMutation(() async {
        await _profiles.leaveClass();
        _profile = await _profiles.getMyProfile();
      });

  /// Display name of the class the student belongs to, once [loadClasses] has
  /// run. Null when they haven't joined one or the list isn't loaded yet.
  String? get className {
    final id = _profile?.classId;
    if (id == null) return null;
    final match = _classes.where((c) => c['id'] == id).firstOrNull;
    return match?['name'] as String?;
  }

  /// Edits a goal in place. Defaults to the active one, so the three shortcut
  /// rows in Settings keep working without naming an id.
  Future<bool> updateGoal({
    String? goalId,
    String? name,
    DateTime? examDate,
    Pace? pace,
    int? dailyMinutes,
  }) =>
      runMutation(() async {
        final id = goalId ?? activeGoal?.id;
        if (id == null) return;
        final saved = await _goals.updateGoal(
          goalId: id,
          name: name,
          examDate: examDate,
          pace: pace,
          dailyMinutes: dailyMinutes,
        );
        _allGoals = [
          for (final g in _allGoals) g.id == saved.id ? saved : g,
        ];
      });

  /// Switches which goal the app works against.
  ///
  /// The whole list is re-read rather than patched locally: `setActiveGoal`
  /// retires the previous goal server-side, so only a fresh read is guaranteed
  /// to agree with the database about which single row is active.
  Future<bool> setActiveGoal(String goalId) => runMutation(() async {
        await _goals.setActiveGoal(goalId);
        _allGoals = await _goals.getGoals();
      });

  /// Deletes a goal and everything hanging off it.
  ///
  /// If it was the active one, the newest survivor takes over — leaving the
  /// student with goals but none active would blank out Home with no obvious
  /// cause.
  Future<bool> removeGoal(String goalId) => runMutation(() async {
        final wasActive = activeGoal?.id == goalId;
        await _goals.deleteGoal(goalId);
        _allGoals = _allGoals.where((g) => g.id != goalId).toList();
        if (wasActive && _allGoals.isNotEmpty) {
          await _goals.setActiveGoal(_allGoals.first.id);
        }
        _allGoals = await _goals.getGoals();
      });

  /// Re-reads the goal list after one was created elsewhere (the New goal flow
  /// writes through [OnboardingStore]).
  Future<bool> reloadGoals() => runMutation(() async {
        _allGoals = await _goals.getGoals();
      });
}
