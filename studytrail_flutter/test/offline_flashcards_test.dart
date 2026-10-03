// Offline flashcard review: cache fallback, queued grades, replay on return.

import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/data/flashcard_cache.dart';
import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/state/stores.dart';

void main() {
  final past = DateTime.now().subtract(const Duration(hours: 1));
  final future = DateTime.now().add(const Duration(days: 2));

  Flashcard card(String id, DateTime due, {String deck = 'd1'}) =>
      Flashcard(id: id, deckId: deck, front: 'Q $id', back: 'A $id', dueAt: due);

  MemoryCache seeded() => MemoryCache()
    ..deckList = const [FlashcardDeck(id: 'd1', name: 'DBMS', total: 3, due: 9)]
    ..cardList = [card('c1', past), card('c2', past), card('c3', future)];

  test('offline, the deck list comes from the phone with real due counts',
      () async {
    final store = FlashcardStore(cards: FakeCards(online: false), cache: seeded());
    addTearDown(store.dispose);

    await store.load();

    expect(store.offline, isTrue);
    expect(store.error, isNull);
    // 9 was stale; two cached cards are actually due now.
    expect(store.decks.single.due, 2);
  });

  test('offline grades queue on the phone instead of bouncing back', () async {
    final cache = seeded();
    final store = FlashcardStore(cards: FakeCards(online: false), cache: cache);
    addTearDown(store.dispose);

    expect(await store.startSession(), isTrue);
    expect(store.queue.map((c) => c.id), ['c1', 'c2']);

    await store.grade(SrGrade.good);
    expect(store.pendingSync, 1);
    expect(store.error, isNull);
    expect(store.queue, hasLength(2), reason: 'not re-queued: it was saved');
    expect(cache.pendingList.single.cardId, 'c1');
  });

  test('back online, queued grades replay in order before anything else',
      () async {
    final cache = seeded()
      ..pendingList = const [
        PendingGrade(cardId: 'c1', grade: SrGrade.again),
        PendingGrade(cardId: 'gone', grade: SrGrade.good),
        PendingGrade(cardId: 'c2', grade: SrGrade.easy),
      ];
    final cards = FakeCards(online: true);
    final store = FlashcardStore(cards: cards, cache: cache);
    addTearDown(store.dispose);

    await store.load();

    // 'gone' was refused by the server (card deleted) and dropped; the rest
    // went through in the order they were given.
    expect(cards.replayed, ['c1:again', 'c2:easy']);
    expect(cache.pendingList, isEmpty);
    expect(store.pendingSync, 0);
    expect(store.offline, isFalse);
  });

  test('offline with nothing cached says so', () async {
    final store =
        FlashcardStore(cards: FakeCards(online: false), cache: MemoryCache());
    addTearDown(store.dispose);

    expect(await store.startSession(), isFalse);
    expect(store.error, contains('offline'));
  });
}

/// The failure a dropped connection produces, as far as isNetworkError can tell.
Exception _noSignal() =>
    Exception('ClientException with SocketException: Failed host lookup');

class FakeCards extends FlashcardRepository {
  FakeCards({required this.online});
  final bool online;
  final replayed = <String>[];

  @override
  Future<List<FlashcardDeck>> getDecks() async {
    if (!online) throw _noSignal();
    return const [FlashcardDeck(id: 'd1', name: 'DBMS', total: 3, due: 0)];
  }

  @override
  Future<List<Flashcard>> getUpcomingCards({int days = 7, int limit = 300}) async =>
      const [];

  @override
  Future<List<Flashcard>> getDueCards({String? deckId, int limit = 40}) async {
    if (!online) throw _noSignal();
    return const [];
  }

  @override
  Future<Flashcard> gradeCard(Flashcard card, SrGrade grade) =>
      gradeCardId(card.id, grade);

  @override
  Future<Flashcard> gradeCardId(String cardId, SrGrade grade) async {
    if (!online) throw _noSignal();
    if (cardId == 'gone') throw Exception('flashcard gone not found');
    replayed.add('$cardId:${grade.db}');
    return Flashcard(
        id: cardId, deckId: 'd1', front: '', back: '', dueAt: DateTime.now());
  }
}

class MemoryCache extends FlashcardCache {
  List<FlashcardDeck> deckList = const [];
  List<Flashcard> cardList = const [];
  List<PendingGrade> pendingList = const [];

  @override
  Future<List<FlashcardDeck>> decks() async => deckList;
  @override
  Future<void> saveDecks(List<FlashcardDeck> decks) async => deckList = decks;
  @override
  Future<List<Flashcard>> cards() async => cardList;
  @override
  Future<void> saveCards(List<Flashcard> cards) async => cardList = cards;
  @override
  Future<List<PendingGrade>> pending() async => pendingList;
  @override
  Future<void> savePending(List<PendingGrade> grades) async =>
      pendingList = grades;
}
