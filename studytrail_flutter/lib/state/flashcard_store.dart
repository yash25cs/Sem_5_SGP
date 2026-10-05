import '../data/flashcard_cache.dart';
import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Flashcards screen: the deck list and a review session over the
/// cards that are due.
///
/// Works offline. Every online load caches the decks and the cards due in the
/// next week; with no network, the deck list and review sessions come from that
/// cache and grades are queued on the phone. The next online load replays the
/// queue through `apply_sr_grade` in order — so scheduling and XP are still
/// the server's, just later.
class FlashcardStore extends AsyncStore {
  FlashcardStore({FlashcardRepository? cards, FlashcardCache? cache})
      : _cards = cards ?? const FlashcardRepository(),
        _cache = cache ?? const FlashcardCache();

  final FlashcardRepository _cards;
  final FlashcardCache _cache;

  bool _offline = false;

  /// True when the last load or review fell back to the phone's copy.
  bool get offline => _offline;

  int _pendingSync = 0;

  /// Grades given offline and not yet sent.
  int get pendingSync => _pendingSync;

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

  bool _practice = false;

  /// The session is a re-attempt of a whole deck ([startPractice]): grades
  /// only move to the next card, and nothing is sent.
  bool get practice => _practice;

  Future<void> load() => runLoad(() async {
        try {
          await _syncPending();
          _decks = await _cards.getDecks();
          _offline = false;
          await _cache.saveDecks(_decks);
          await _refreshCardCache();
        } catch (e) {
          if (!isNetworkError(e)) rethrow;
          final cached = await _cache.decks();
          if (cached.isEmpty) rethrow;
          _decks = await _withCachedDueCounts(cached);
          _offline = true;
          _pendingSync = (await _cache.pending()).length;
        }
      });

  /// Starts a review. Omit [deckId] to review everything that's due.
  Future<bool> startSession({String? deckId}) => runMutation(() async {
        try {
          await _syncPending();
          _queue = await _cards.getDueCards(deckId: deckId);
          _offline = false;
        } catch (e) {
          if (!isNetworkError(e)) rethrow;
          _queue = await _cachedDue(deckId);
          _offline = true;
          if (_queue.isEmpty) {
            throw "You're offline, and no due cards are saved on this phone.";
          }
        }
        _index = 0;
        _revealed = false;
        _reviewedThisSession = 0;
        _practice = false;
      });

  /// Goes through every card in a deck again, due or not — the re-attempt of
  /// a deck that has nothing left due.
  ///
  /// A practice run: the grade buttons only advance. Sending them would let
  /// `apply_sr_grade` reschedule cards reviewed days early (a "Good" pushes
  /// the next review further out), and it pays nothing for a card that isn't
  /// due anyway. Shuffled, so a second run isn't the first one memorised.
  Future<bool> startPractice(String deckId) => runMutation(() async {
        List<Flashcard> cards;
        try {
          cards = await _cards.getDeckCards(deckId);
          _offline = false;
        } catch (e) {
          if (!isNetworkError(e)) rethrow;
          cards = [
            for (final c in await _cache.cards())
              if (c.deckId == deckId) c,
          ];
          _offline = true;
          if (cards.isEmpty) {
            throw "You're offline, and this deck's cards aren't saved on "
                'this phone.';
          }
        }
        _queue = cards..shuffle();
        _index = 0;
        _revealed = false;
        _reviewedThisSession = 0;
        _practice = true;
      });

  Future<void> _refreshCardCache() async {
    try {
      await _cache.saveCards(await _cards.getUpcomingCards());
    } catch (_) {
      // The previous copy stays; it's a fallback, not a source of truth.
    }
  }

  /// Cached cards due by now, minus any already graded offline.
  Future<List<Flashcard>> _cachedDue(String? deckId) async {
    final graded = {for (final p in await _cache.pending()) p.cardId};
    final now = DateTime.now();
    return (await _cache.cards())
        .where((c) =>
            !c.dueAt.isAfter(now) &&
            !graded.contains(c.id) &&
            (deckId == null || c.deckId == deckId))
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  Future<List<FlashcardDeck>> _withCachedDueCounts(
      List<FlashcardDeck> decks) async {
    final due = await _cachedDue(null);
    return [
      for (final d in decks)
        d.withDue(due.where((c) => c.deckId == d.id).length),
    ];
  }

  /// Sends queued offline grades, oldest first. Stops (keeping the rest) at
  /// the first network failure; drops one the server can't apply, like a card
  /// deleted since.
  Future<void> _syncPending() async {
    final queued = await _cache.pending();
    if (queued.isEmpty) {
      _pendingSync = 0;
      return;
    }
    final left = [...queued];
    while (left.isNotEmpty) {
      try {
        await _cards.gradeCardId(left.first.cardId, left.first.grade);
      } catch (e) {
        if (isNetworkError(e)) {
          await _cache.savePending(left);
          _pendingSync = left.length;
          rethrow;
        }
      }
      left.removeAt(0);
    }
    await _cache.savePending(const []);
    _pendingSync = 0;
  }

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
    // A practice run changes nothing on the server; see [startPractice].
    if (_practice) return;

    final ok = await runMutation(() async {
      try {
        await _cards.gradeCard(card, grade);
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        // No signal: keep the grade on the phone and move on. It's sent the
        // next time the deck list loads online.
        final queued = [
          ...await _cache.pending(),
          PendingGrade(cardId: card.id, grade: grade),
        ];
        await _cache.savePending(queued);
        _pendingSync = queued.length;
        _offline = true;
      }
      if (sessionFinished) {
        _decks = _offline
            ? await _withCachedDueCounts(_decks)
            : await _cards.getDecks();
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

  /// Deletes a deck and its cards (FK cascade). The phone's offline copy
  /// forgets it too, or an offline session could still open it.
  Future<bool> deleteDeck(FlashcardDeck deck) => runMutation(() async {
        await _cards.deleteDeck(deck.id);
        _decks = _decks.where((d) => d.id != deck.id).toList();
        await _cache.saveDecks(_decks);
        await _cache.saveCards([
          for (final c in await _cache.cards())
            if (c.deckId != deck.id) c,
        ]);
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
