import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs Home's "Weak spots" card: the units the student keeps missing, and
/// one-tap practice aimed at exactly those.
///
/// Generating here doesn't refresh the Quiz or Flashcards lists; the screen
/// that starts it reloads [QuizStore] / [FlashcardStore] afterwards.
class WeakSpotsStore extends AsyncStore {
  WeakSpotsStore({QuizRepository? quizzes, FlashcardRepository? cards})
      : _quizzes = quizzes ?? const QuizRepository(),
        _cards = cards ?? const FlashcardRepository();

  final QuizRepository _quizzes;
  final FlashcardRepository _cards;

  List<WeakTopic> _topics = const [];
  List<WeakTopic> get topics => _topics;

  /// 'quiz' or 'cards' while one is being generated, so only that button spins.
  String? _making;
  String? get making => _making;

  Future<void> load() => runLoad(() async {
        _topics = await _quizzes.getWeakTopics(limit: 3);
      });

  /// Returns the new quiz's id, or null with [error] set.
  Future<String?> practiceQuiz() async {
    String? quizId;
    _making = 'quiz';
    final ok = await runMutation(() async {
      quizId = await _quizzes.generateWeakQuiz();
    });
    _making = null;
    notifyListeners();
    return ok ? quizId : null;
  }

  /// Returns how many cards landed, or null with [error] set.
  Future<int?> practiceCards() async {
    int? saved;
    _making = 'cards';
    final ok = await runMutation(() async {
      saved = await _cards.generateWeakDeck();
    });
    _making = null;
    notifyListeners();
    return ok ? saved : null;
  }
}
