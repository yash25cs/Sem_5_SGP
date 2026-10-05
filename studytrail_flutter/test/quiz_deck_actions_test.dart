// Quizzes and decks open in place to show what can be done with them: Start
// or Retake (Review or Re-attempt for a deck) and Delete, which asks first. A
// finished quiz shows its last marks and when; a deck with nothing due
// re-attempts as a practice run that leaves the review schedule alone.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/flashcard_cache.dart';
import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/flashcards_screen.dart';
import 'package:studytrail_flutter/screens/quiz_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/expandable_item_card.dart';

Future<void> _pump(WidgetTester tester, Widget screen,
    List<ChangeNotifierProvider> providers) async {
  tester.view.physicalSize = const Size(360 * 3, 860 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: providers,
    child: MaterialApp(theme: AppTheme.light(), home: screen),
  ));
  await tester.pumpAndSettle();
}

Finder _inDialog(String text) => find.descendant(
    of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  group('whenLabel', () {
    final now = DateTime(2026, 10, 5, 18, 0); // a Monday

    test('today and yesterday by name, with the time', () {
      expect(whenLabel(DateTime(2026, 10, 5, 15, 42), now), 'Today, 3:42 PM');
      expect(whenLabel(DateTime(2026, 10, 4, 9, 5), now), 'Yesterday, 9:05 AM');
      expect(whenLabel(DateTime(2026, 10, 5, 0, 5), now), 'Today, 12:05 AM');
      expect(whenLabel(DateTime(2026, 10, 5, 12, 0), now), 'Today, 12:00 PM');
    });

    test('older ones by date; the year only once it differs', () {
      expect(whenLabel(DateTime(2026, 9, 29, 18, 10), now),
          'Tue, 29 Sep, 6:10 PM');
      expect(whenLabel(DateTime(2025, 12, 31, 9, 0), now),
          '31 Dec 2025, 9:00 AM');
    });
  });

  group('Quizzes', () {
    late _FakeQuizzes quizzes;

    setUp(() => quizzes = _FakeQuizzes());

    List<ChangeNotifierProvider> providers() => [
          ChangeNotifierProvider<QuizStore>(
              create: (_) => QuizStore(quizzes: quizzes)),
          ChangeNotifierProvider<WeakSpotsStore>(
              create: (_) => WeakSpotsStore(quizzes: quizzes)),
        ];

    testWidgets('a finished quiz shows its last marks and when', (tester) async {
      await _pump(tester, const QuizScreen(), providers());

      expect(find.text('8/10'), findsOneWidget);
      expect(find.textContaining('Last attempt: Today,'), findsOneWidget);
      // The unfinished one has neither.
      expect(find.text('Never tried'), findsOneWidget);
      expect(find.textContaining('Last attempt'), findsOneWidget);
    });

    testWidgets('tapping opens Start / Retake and Delete, one at a time',
        (tester) async {
      await _pump(tester, const QuizScreen(), providers());
      expect(find.text('Start quiz'), findsNothing);
      expect(find.text('Delete'), findsNothing);

      await tester.tap(find.text('Never tried'));
      await tester.pumpAndSettle();
      expect(find.text('Start quiz'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Optics'));
      await tester.pumpAndSettle();
      expect(find.text('Start quiz'), findsNothing,
          reason: 'opening one closes the other');
      expect(find.text('Retake'), findsOneWidget);

      // Tapping it again closes it.
      await tester.tap(find.text('Optics'));
      await tester.pumpAndSettle();
      expect(find.text('Retake'), findsNothing);
    });

    testWidgets('Delete asks first; Cancel keeps it, Delete removes it',
        (tester) async {
      await _pump(tester, const QuizScreen(), providers());
      await tester.tap(find.text('Optics'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete quiz?'), findsOneWidget);
      expect(find.textContaining('all its attempts and marks'), findsOneWidget);
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();
      expect(quizzes.deleted, isEmpty);
      expect(find.text('Optics'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete'));
      await tester.pumpAndSettle();
      expect(quizzes.deleted, ['qa']);
      expect(find.text('Optics'), findsNothing);
      expect(find.text('Quiz deleted.'), findsOneWidget);
    });

    testWidgets('Retake starts the quiz again', (tester) async {
      await _pump(tester, const QuizScreen(), providers());
      await tester.tap(find.text('Optics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retake'));
      await tester.pumpAndSettle();
      expect(find.text('What bends light?'), findsOneWidget);
      expect(quizzes.started, ['qa']);
    });

    test('finishing puts the new marks on the quiz in the list', () async {
      final store = QuizStore(quizzes: quizzes);
      addTearDown(store.dispose);
      await store.load();
      await store.start('qb');
      store.pick(0);
      expect(store.next(), isTrue);
      expect(await store.finish(), isTrue);

      final quiz = store.available.firstWhere((q) => q.id == 'qb');
      expect(quiz.attempted, isTrue);
      expect(quiz.lastAttempt?.score, 1);
      expect(quiz.lastAttempt?.total, 1);
    });
  });

  group('Decks', () {
    late _FakeCards cards;
    late _MemoryCache cache;

    setUp(() {
      cards = _FakeCards();
      cache = _MemoryCache();
    });

    List<ChangeNotifierProvider> providers() => [
          ChangeNotifierProvider<FlashcardStore>(
              create: (_) => FlashcardStore(cards: cards, cache: cache)),
          ChangeNotifierProvider<WeakSpotsStore>(
              create: (_) =>
                  WeakSpotsStore(quizzes: _FakeQuizzes(), cards: cards)),
        ];

    testWidgets('a deck with cards due offers Review; a caught-up one '
        'Re-attempt', (tester) async {
      await _pump(tester, const FlashcardsScreen(), providers());

      await tester.tap(find.text('Physics'));
      await tester.pumpAndSettle();
      expect(find.text('Review 2'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      expect(find.text('All caught up — nothing due'), findsOneWidget);
      await tester.tap(find.text('Chemistry'));
      await tester.pumpAndSettle();
      expect(find.text('Review 2'), findsNothing);
      expect(find.text('Re-attempt'), findsOneWidget);
    });

    testWidgets('Re-attempt goes through every card without sending grades',
        (tester) async {
      await _pump(tester, const FlashcardsScreen(), providers());
      await tester.tap(find.text('Chemistry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Re-attempt'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Practice run'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('QUESTION'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Good'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Practice complete'), findsOneWidget);
      expect(cards.graded, isEmpty,
          reason: 'a practice run must not reschedule cards');
    });

    testWidgets('Delete asks first, then removes the deck', (tester) async {
      await _pump(tester, const FlashcardsScreen(), providers());
      await tester.tap(find.text('Physics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete deck?'), findsOneWidget);
      expect(find.textContaining('its 3 cards will be deleted'), findsOneWidget);
      await tester.tap(_inDialog('Delete'));
      await tester.pumpAndSettle();

      expect(cards.deletedDecks, ['d1']);
      expect(find.text('Physics'), findsNothing);
      expect(cache.deckList.map((d) => d.id), ['d2'],
          reason: 'the offline copy forgets it too');
    });
  });
}

class _FakeQuizzes extends QuizRepository {
  final deleted = <String>[];
  final started = <String>[];

  late var _quizzes = [
    Quiz(
      id: 'qa',
      title: 'Optics',
      length: 10,
      lastAttempt: QuizAttempt(
        id: 'a1',
        quizId: 'qa',
        score: 8,
        total: 10,
        completedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    ),
    const Quiz(id: 'qb', title: 'Never tried', length: 1),
  ];

  @override
  Future<List<Quiz>> getQuizzes({String? subjectId}) async => _quizzes;

  @override
  Future<void> deleteQuiz(String quizId) async {
    deleted.add(quizId);
    _quizzes = _quizzes.where((q) => q.id != quizId).toList();
  }

  @override
  Future<Quiz?> getQuiz(String quizId) async => Quiz(
        id: quizId,
        title: 'Q',
        questions: const [
          QuizQuestion(
              id: 'q1',
              question: 'What bends light?',
              options: ['Lens', 'Rock', 'Wood', 'Cloth'],
              correctIndex: 0),
        ],
      );

  @override
  Future<QuizAttempt> startAttempt(String quizId) async {
    started.add(quizId);
    return QuizAttempt(id: 'new', quizId: quizId);
  }

  @override
  Future<QuizAttempt> submit({
    required String attemptId,
    required Map<String, int> picks,
  }) async =>
      QuizAttempt(
        id: attemptId,
        quizId: 'qb',
        score: 1,
        total: 1,
        xpEarned: 10,
        completedAt: DateTime.now(),
      );

  @override
  Future<List<WeakTopic>> getWeakTopics({int limit = 5}) async => const [];
}

class _FakeCards extends FlashcardRepository {
  final graded = <String>[];
  final deletedDecks = <String>[];

  var _decks = const [
    FlashcardDeck(id: 'd1', name: 'Physics', total: 3, due: 2),
    FlashcardDeck(id: 'd2', name: 'Chemistry', total: 2, due: 0),
  ];

  @override
  Future<List<FlashcardDeck>> getDecks() async => _decks;

  @override
  Future<List<Flashcard>> getUpcomingCards(
          {int days = 7, int limit = 300}) async =>
      const [];

  @override
  Future<List<Flashcard>> getDeckCards(String deckId) async => [
        for (final i in [1, 2])
          Flashcard(
            id: '$deckId-$i',
            deckId: deckId,
            front: 'Front $i',
            back: 'Back $i',
            dueAt: DateTime.now().add(const Duration(days: 4)),
          ),
      ];

  @override
  Future<Flashcard> gradeCardId(String cardId, SrGrade grade) async {
    graded.add(cardId);
    return Flashcard(
        id: cardId, deckId: 'd2', front: '', back: '', dueAt: DateTime.now());
  }

  @override
  Future<void> deleteDeck(String deckId) async {
    deletedDecks.add(deckId);
    _decks = _decks.where((d) => d.id != deckId).toList();
  }
}

class _MemoryCache extends FlashcardCache {
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
