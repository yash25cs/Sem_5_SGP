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

  PracticeQuestion? _question;
  PracticeQuestion? get question => _question;

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
    _question = question;
    _result = null;
    clearError();
    notifyListeners();
  }

  Future<bool> newQuestion({String? unitLabel}) => runMutation(() async {
        _question = await _answers.newQuestion(unitLabel: unitLabel);
        _result = null;
      });

  Future<bool> submit(String answer) async {
    final q = _question;
    if (q == null) return false;
    return runMutation(() async {
      _result = await _answers.grade(q, answer.trim());
      _history = [_result!, ..._history];
    });
  }

  /// Grades photos of a handwritten answer (one per page, up to three).
  Future<bool> submitPhotos(List<File> pages) async {
    final q = _question;
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
