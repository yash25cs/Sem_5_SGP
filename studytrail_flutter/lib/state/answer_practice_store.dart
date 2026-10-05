import 'dart:io';

import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs Answer practice: one question at a time, a written answer, and the
/// examiner's feedback — plus the history of past attempts.
class AnswerPracticeStore extends AsyncStore {
  AnswerPracticeStore({AnswerRepository? answers})
      : _answers = answers ?? const AnswerRepository();

  final AnswerRepository _answers;

  /// Most questions one set can have.
  static const maxQuestions = 5;

  /// The questions being worked through, one at a time.
  List<PracticeQuestion> _set = const [];
  int _index = 0;

  PracticeQuestion? get question => _index < _set.length ? _set[_index] : null;

  /// How many questions are in this set, and which one is showing (from 1).
  int get setSize => _set.length;
  int get position => _index + 1;

  /// Another question follows this one in the set.
  bool get hasNext => _index + 1 < _set.length;

  /// The grade for the current question, once submitted.
  AnswerAttempt? _result;
  AnswerAttempt? get result => _result;

  List<AnswerAttempt> _history = const [];
  List<AnswerAttempt> get history => _history;

  Future<void> load() => runLoad(() async {
        _history = await _answers.getAttempts();
      });

  /// Practise on a specific question (e.g. from a past paper).
  void use(PracticeQuestion question) {
    _set = [question];
    _index = 0;
    _result = null;
    clearError();
    notifyListeners();
  }

  /// A new set of [count] questions (1–[maxQuestions]), starting at the first.
  Future<bool> newQuestions({int count = 1, String? unitLabel}) =>
      runMutation(() async {
        _set = await _answers.newQuestions(
          count: count.clamp(1, maxQuestions),
          unitLabel: unitLabel,
        );
        _index = 0;
        _result = null;
      });

  /// On to the next question in the set. False at the end.
  bool next() {
    if (!hasNext) return false;
    _index++;
    _result = null;
    clearError();
    notifyListeners();
    return true;
  }

  /// Done with this set: back to choosing how many questions.
  void clearSet() {
    _set = const [];
    _index = 0;
    _result = null;
    clearError();
    notifyListeners();
  }

  Future<bool> submit(String answer) async {
    final q = question;
    if (q == null) return false;
    return runMutation(() async {
      _result = await _answers.grade(q, answer.trim());
      _history = [_result!, ..._history];
    });
  }

  /// Grades photos of a handwritten answer (one per page, up to three).
  Future<bool> submitPhotos(List<File> pages) async {
    final q = question;
    if (q == null || pages.isEmpty) return false;
    return runMutation(() async {
      _result = await _answers.gradePhotos(q, pages);
      _history = [_result!, ..._history];
    });
  }

  /// Back to answering the same question, e.g. after reading the feedback.
  void retry() {
    _result = null;
    notifyListeners();
  }
}
