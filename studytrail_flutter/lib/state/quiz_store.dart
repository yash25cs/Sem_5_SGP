import 'dart:math';

import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Quiz screen: one question at a time, immediate feedback, and a
/// server-scored result at the end.
class QuizStore extends AsyncStore {
  QuizStore({QuizRepository? quizzes, Random? random})
      : _quizzes = quizzes ?? const QuizRepository(),
        _random = random ?? Random();

  final QuizRepository _quizzes;
  final Random _random;

  int _lifelines = 0;

  /// 50:50 lifelines the student holds, read when a quiz starts.
  int get lifelines => _lifelines;

  /// Options a 50:50 removed, by question id.
  final Map<String, Set<int>> _hidden = {};

  /// The current question's removed options.
  Set<int> get hiddenOptions => _hidden[current?.id] ?? const {};

  /// A lifeline can go on this question: one held, not yet answered, and
  /// none used on it already.
  bool get canUseLifeline {
    final q = current;
    return _lifelines > 0 && q != null && !answered && !_hidden.containsKey(q.id);
  }

  List<Quiz> _available = const [];
  Quiz? _quiz;
  QuizAttempt? _attempt;
  int _index = 0;
  int? _picked;
  String? _generatedQuizId;
  final Map<String, int> _picks = {};

  List<Quiz> get available => _available;
  Quiz? get quiz => _quiz;
  QuizAttempt? get attempt => _attempt;

  /// The quiz the last [generate] produced, so the picker can point at it.
  String? get generatedQuizId => _generatedQuizId;

  List<QuizQuestion> get questions => _quiz?.questions ?? const [];
  QuizQuestion? get current =>
      _index < questions.length ? questions[_index] : null;

  /// The option the student tapped for the current question, or null.
  int? get picked => _picked;

  /// True once an option is tapped — the correct answer is revealed and the
  /// options lock until "Next".
  bool get answered => _picked != null;

  int get questionNumber => _index + 1;
  int get questionCount => questions.length;
  bool get isLastQuestion => _index >= questions.length - 1;

  /// Correct answers so far, for the running score chip.
  int get runningScore => _picks.entries
      .where((e) => questions
          .any((q) => q.id == e.key && q.correctIndex == e.value))
      .length;

  double get progress =>
      questions.isEmpty ? 0 : (_index + (answered ? 1 : 0)) / questions.length;

  Future<void> load({String? subjectId}) => runLoad(() async {
        _available = await _quizzes.getQuizzes(subjectId: subjectId);
      });

  /// Asks the server to write a quiz from one of the student's materials, then
  /// refreshes the picker so the new quiz is at the top.
  ///
  /// Appends: `quiz_attempts` history hangs off a quiz row, so each generation
  /// is a new quiz rather than a replacement. The refresh is unfiltered on
  /// purpose — a generated quiz has no `subject_id` yet (nothing associates a
  /// material with a subject), so a subject filter would hide the thing that was
  /// just made.
  Future<bool> generate({required String materialId, int length = 10}) =>
      runMutation(() async {
        _generatedQuizId =
            await _quizzes.generateQuiz(materialId: materialId, length: length);
        _available = await _quizzes.getQuizzes();
      });

  /// Loads a quiz and opens an attempt row. The lifeline count comes along;
  /// failing to read it just means no 50:50 this time.
  Future<bool> start(String quizId) => runMutation(() async {
        final lifelines =
            _quizzes.lifelinesLeft().catchError((Object _) => 0);
        _quiz = await _quizzes.getQuiz(quizId);
        _attempt = await _quizzes.startAttempt(quizId);
        _lifelines = await lifelines;
        _index = 0;
        _picked = null;
        _picks.clear();
        _hidden.clear();
      });

  /// Spends a 50:50 on the current question: the server takes the lifeline,
  /// then two of the wrong options go, chosen at random. False with [error]
  /// set when it couldn't be used.
  Future<bool> useLifeline() async {
    final q = current;
    if (q == null || !canUseLifeline) return false;
    return runMutation(() async {
      _lifelines = await _quizzes.useLifeline();
      final wrong = [
        for (var i = 0; i < q.options.length; i++)
          if (i != q.correctIndex) i,
      ]..shuffle(_random);
      _hidden[q.id] = wrong.take(2).toSet();
    });
  }

  void pick(int optionIndex) {
    if (_picked != null) return; // locked once answered
    final q = current;
    if (q == null) return;
    if (_hidden[q.id]?.contains(optionIndex) ?? false) return;
    _picked = optionIndex;
    _picks[q.id] = optionIndex;
    notifyListeners();
  }

  /// Advances. Returns true when that was the last question, so the screen
  /// knows to call [finish] and show results.
  bool next() {
    if (_picked == null) return false;
    if (isLastQuestion) return true;
    _index++;
    _picked = null;
    notifyListeners();
    return false;
  }

  /// Scores the attempt server-side and stores the result — also as the
  /// quiz's latest attempt in the list, so its card shows the new marks and
  /// time the moment the student goes back.
  Future<bool> finish() => runMutation(() async {
        final attempt = _attempt;
        if (attempt == null) return;
        final scored = await _quizzes.submit(
          attemptId: attempt.id,
          picks: Map.of(_picks),
        );
        _attempt = scored;
        _available = [
          for (final q in _available)
            q.id == scored.quizId ? q.withLastAttempt(scored) : q,
        ];
      });

  /// Deletes a quiz and its attempts. The list drops it only once the server
  /// has, so a failed delete leaves it where it was.
  Future<bool> deleteQuiz(Quiz quiz) => runMutation(() async {
        await _quizzes.deleteQuiz(quiz.id);
        _available = _available.where((q) => q.id != quiz.id).toList();
      });

  void reset() {
    _quiz = null;
    _attempt = null;
    _index = 0;
    _picked = null;
    _picks.clear();
    _hidden.clear();
    notifyListeners();
  }
}
