import '../../models/models.dart';
import '../supabase_client.dart';

/// Decks, due cards, and review grading.
///
/// SM-2 scheduling lives server-side in the `apply_sr_grade` RPC
/// (`supabase/migrations/0004_functions.sql`) so there's exactly one
/// implementation of the algorithm.
class FlashcardRepository {
  const FlashcardRepository();

  /// Decks with total/due counts from the `deck_stats` view.
  ///
  /// `deck_stats` is an aggregated (`group by`) view, so PostgREST can't infer a
  /// foreign key from `flashcard_decks` to it and rejects `deck_stats(...)` as an
  /// embed with PGRST200. Both are fetched separately and merged here; the
  /// counts land as top-level `total`/`due`, which `FlashcardDeck.fromMap`
  /// already reads.
  Future<List<FlashcardDeck>> getDecks() async {
    final results = await Future.wait([
      db
          .from('flashcard_decks')
          .select('*, subjects(name)')
          .order('created_at', ascending: false),
      db.from('deck_stats').select('deck_id, total, due'),
    ]);
    return _mergeStats(results[0], results[1]);
  }

  Future<FlashcardDeck> createDeck({
    required String name,
    String? subjectId,
  }) async {
    final row = await db
        .from('flashcard_decks')
        .insert({
          'user_id': requireUserId,
          'name': name,
          'subject_id': ?subjectId,
        })
        .select('*, subjects(name)')
        .single();
    // A brand-new deck has no cards yet, so the zero defaults are correct.
    return FlashcardDeck.fromMap(row);
  }

  /// Folds `deck_stats` rows into their matching deck by `deck_id`.
  List<FlashcardDeck> _mergeStats(
    List<Map<String, dynamic>> decks,
    List<Map<String, dynamic>> stats,
  ) {
    final byDeck = {
      for (final s in stats) s['deck_id'] as String: s,
    };
    return [
      for (final deck in decks)
        FlashcardDeck.fromMap({
          ...deck,
          ...?byDeck[deck['id'] as String],
        }),
    ];
  }

  /// Cards due now, soonest first. Omit [deckId] to review across all decks.
  Future<List<Flashcard>> getDueCards({String? deckId, int limit = 40}) async {
    var query = db
        .from('flashcards')
        .select()
        .lte('due_at', DateTime.now().toUtc().toIso8601String());
    if (deckId != null) query = query.eq('deck_id', deckId);
    final rows = await query.order('due_at', ascending: true).limit(limit);
    return rows.map(Flashcard.fromMap).toList();
  }

  Future<List<Flashcard>> getDeckCards(String deckId) async {
    final rows = await db
        .from('flashcards')
        .select()
        .eq('deck_id', deckId)
        .order('front', ascending: true);
    return rows.map(Flashcard.fromMap).toList();
  }

  Future<Flashcard> createCard({
    required String deckId,
    required String front,
    required String back,
    String? unitLabel,
  }) async {
    final row = await db
        .from('flashcards')
        .insert({
          'user_id': requireUserId,
          'deck_id': deckId,
          'front': front,
          'back': back,
          'unit_label': ?unitLabel,
        })
        .select()
        .single();
    return Flashcard.fromMap(row);
  }

  /// Applies a review grade. The RPC updates ease/interval/repetitions/due_at
  /// per SM-2 and returns the rescheduled row.
  Future<Flashcard> gradeCard(Flashcard card, SrGrade grade) async {
    final row = await db.rpc(
      'apply_sr_grade',
      params: {'card_id': card.id, 'grade': grade.db},
    );
    // The function returns a single `flashcards` record.
    final map = row is List
        ? row.first as Map<String, dynamic>
        : row as Map<String, dynamic>;
    return Flashcard.fromMap(map);
  }

  Future<void> deleteDeck(String deckId) =>
      db.from('flashcard_decks').delete().eq('id', deckId);

  Future<void> deleteCard(String cardId) =>
      db.from('flashcards').delete().eq('id', cardId);

  /// Asks the `generate-flashcards` Edge Function to write a deck from one
  /// material. Returns how many cards it saved.
  ///
  /// Unlike the roadmap and quiz generators this one has no elevated privileges
  /// — `insert on flashcards` is granted to the student, so the function acts as
  /// the caller. It lives server-side for the Gemini key, not for the write.
  ///
  /// Appends: every call is a new deck named after the material.
  Future<int> generateDeck({
    required String materialId,
    int count = 20,
  }) async {
    final res = await db.functions.invoke(
      'generate-flashcards',
      body: {'materialId': materialId, 'count': count},
    );
    final data = res.data;
    if (data is Map && data['cards'] is int) return data['cards'] as int;
    return 0;
  }
}
