import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Flashcards screen: the deck list and a review session over the
/// cards that are due.
class FlashcardStore extends AsyncStore {
  FlashcardStore({FlashcardRepository? cards})
      : _cards = cards ?? const FlashcardRepository();

  final FlashcardRepository _cards;

  List<FlashcardDeck> _decks = const [];
  List<Flashcard> _queue = const [];
  int _index = 0;
  bool _revealed = false;
  int _reviewedThisSession = 0;
  int _generatedCards = 0;

  List<FlashcardDeck> get decks => _decks;

  /// How many cards the last [generateDeck] saved. Fewer than asked for is a
  /// normal outcome — cards the model repeated or left half-written are dropped
  /// server-side — so the screen reports what actually landed.
  int get generatedCards => _generatedCards;

  /// Cards remaining in the current review session.
  List<Flashcard> get queue => _queue;

  Flashcard? get current => _index < _queue.length ? _queue[_index] : null;

  /// True once the student has tapped to see the answer — the grade buttons
  /// only appear after this.
  bool get revealed => _revealed;

  bool get sessionFinished => _queue.isNotEmpty && _index >= _queue.length;
  int get reviewedThisSession => _reviewedThisSession;
  int get remaining => (_queue.length - _index).clamp(0, _queue.length);

  double get sessionProgress =>
      _queue.isEmpty ? 0 : _index / _queue.length;

  Future<void> load() => runLoad(() async {
        _decks = await _cards.getDecks();
      });

  /// Starts a review. Omit [deckId] to review everything that's due.
  Future<bool> startSession({String? deckId}) => runMutation(() async {
        _queue = await _cards.getDueCards(deckId: deckId);
        _index = 0;
        _revealed = false;
        _reviewedThisSession = 0;
      });

  void reveal() {
    if (_revealed) return;
    _revealed = true;
    notifyListeners();
  }

  /// Grades the current card and advances. The new schedule is computed by the
  /// `apply_sr_grade` RPC, so nothing here duplicates the SM-2 math — and the
  /// RPC pays out only for a card that was genuinely due, so no XP is named
  /// here either.
  ///
  /// The advance is optimistic: waiting on the network between cards makes
  /// review feel sluggish. If the grade doesn't land, the card goes back on the
  /// end of the queue rather than vanishing — it's still due in the database,
  /// and silently dropping it meant the session claimed a review that never
  /// happened (REVIEW.md P1).
  Future<void> grade(SrGrade grade) async {
    final card = current;
    if (card == null) return;

    _index++;
    _revealed = false;
    _reviewedThisSession++;
    notifyListeners();

    final ok = await runMutation(() async {
      await _cards.gradeCard(card, grade);
      if (sessionFinished) {
        _decks = await _cards.getDecks();
      }
    });

    if (!ok) {
      // Re-queued at the end, not back at _index: by now the student may have
      // graded further cards, and yanking the view backwards mid-review would
      // be worse than seeing this one again in a moment.
      _reviewedThisSession--;
      _queue = [..._queue, card];
      notifyListeners();
    }
  }

  Future<bool> createDeck(String name, {String? subjectId}) =>
      runMutation(() async {
        final deck = await _cards.createDeck(name: name, subjectId: subjectId);
        _decks = [deck, ..._decks];
      });

  Future<bool> addCard({
    required String deckId,
    required String front,
    required String back,
  }) =>
      runMutation(() async {
        await _cards.createCard(deckId: deckId, front: front, back: back);
        _decks = await _cards.getDecks();
      });

  Future<bool> deleteDeck(FlashcardDeck deck) => runMutation(() async {
        await _cards.deleteDeck(deck.id);
        _decks = _decks.where((d) => d.id != deck.id).toList();
      });

  /// Asks the server to write a deck from one of the student's materials, then
  /// refreshes the deck list.
  ///
  /// Appends: every generation is a new deck named after the material, so
  /// generating twice from the same file gives two decks rather than silently
  /// merging them. Every card lands due immediately, which is what puts the new
  /// deck's count straight into the review session.
  Future<bool> generateDeck({
    required String materialId,
    int count = 20,
  }) =>
      runMutation(() async {
        _generatedCards =
            await _cards.generateDeck(materialId: materialId, count: count);
        _decks = await _cards.getDecks();
      });
}
