// Weak topics: parsing what get_weak_topics returns, and WeakSpotsStore's
// practice actions, with Supabase faked at the repository seam.

import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/state/stores.dart';

void main() {
  group('WeakTopic', () {
    test('reads the RPC row and describes its evidence', () {
      final t = WeakTopic.fromMap({
        'material_id': 'm1',
        'material_title': 'dbms.txt',
        'unit_label': 'Unit 2: Transactions',
        'answered': 3,
        'correct': 0,
        'cards_reviewed': 4,
        'cards_struggling': 2,
        'miss_rate': 0.71,
      });
      expect(t.name, 'Unit 2: Transactions');
      expect(t.missRate, 0.71);
      expect(t.evidence, '0/3 quiz answers right · 2 of 4 cards marked hard');
    });

    test('a file without unit headings is named after the file', () {
      final t = WeakTopic.fromMap({
        'material_id': 'm1',
        'material_title': 'Notes photo 30 Sep.jpg',
        'unit_label': null,
        'answered': 2,
        'correct': 1,
      });
      expect(t.name, 'Notes photo 30 Sep.jpg');
      expect(t.evidence, '1/2 quiz answers right');
    });
  });

  group('WeakSpotsStore', () {
    test('loads the weakest three and generates a targeted quiz', () async {
      final quizzes = _FakeQuizzes();
      final store = WeakSpotsStore(quizzes: quizzes, cards: _FakeCards());
      addTearDown(store.dispose);

      await store.load();
      expect(store.topics.single.name, 'Unit 2');
      expect(quizzes.limitAsked, 3);

      expect(await store.practiceQuiz(), 'quiz-1');
      expect(store.making, isNull);
    });

    test('a failed generation reports why and clears the spinner', () async {
      final store = WeakSpotsStore(
          quizzes: _FakeQuizzes(), cards: _FakeCards(fail: true));
      addTearDown(store.dispose);

      expect(await store.practiceCards(), isNull);
      expect(store.error, isNotNull);
      expect(store.making, isNull);
      expect(store.busy, isFalse);
    });
  });
}

class _FakeQuizzes extends QuizRepository {
  int? limitAsked;

  @override
  Future<List<WeakTopic>> getWeakTopics({int limit = 5}) async {
    limitAsked = limit;
    return const [
      WeakTopic(
          materialId: 'm1',
          materialTitle: 'dbms.txt',
          unitLabel: 'Unit 2',
          answered: 3,
          missRate: 1),
    ];
  }

  @override
  Future<String> generateWeakQuiz({int length = 5}) async => 'quiz-1';
}

class _FakeCards extends FlashcardRepository {
  _FakeCards({this.fail = false});
  final bool fail;

  @override
  Future<int> generateWeakDeck() async {
    if (fail) throw Exception('generate-flashcards is down');
    return 10;
  }
}
