// ChatStore's follow-up suggestions and save-as-flashcards, with Supabase
// faked out at the repository seam (see stores_test.dart for why).

import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/state/stores.dart';

void main() {
  group('ChatStore follow-ups', () {
    test('an answer brings its follow-ups; the next send clears them', () async {
      final chat = _FakeChat(['What is 2NF?', 'Why BCNF?', 'Give an example']);
      final store = ChatStore(chat: chat, goals: const _NoGoal());
      addTearDown(store.dispose);
      await store.load();

      await store.send('What is 3NF?');
      expect(store.suggestions, hasLength(3));

      // While the next question is in flight the old follow-ups would describe
      // the previous answer, so they go away immediately.
      chat.suggestions = const [];
      final pending = store.send('What is 2NF?');
      expect(store.suggestions, isEmpty);
      await pending;
    });
  });

  group('ChatStore.makeCards', () {
    test('saves once per answer, even if tapped twice', () async {
      final cards = _FakeCards();
      final store = ChatStore(
          chat: _FakeChat(const []), goals: const _NoGoal(), cards: cards);
      addTearDown(store.dispose);

      final results = await Future.wait(
          [store.makeCards('m1'), store.makeCards('m1')]);

      expect(cards.calls, ['m1']);
      expect(results, [5, null]);
      expect(store.cardsSaved('m1'), isTrue);
      expect(await store.makeCards('m1'), isNull);
    });

    test('a failure says why and can be retried', () async {
      final cards = _FakeCards(fail: true);
      final store = ChatStore(
          chat: _FakeChat(const []), goals: const _NoGoal(), cards: cards);
      addTearDown(store.dispose);

      expect(await store.makeCards('m1'), isNull);
      expect(store.error, isNotNull);
      expect(store.cardsSaved('m1'), isFalse);

      cards.fail = false;
      expect(await store.makeCards('m1'), 5);
    });
  });
}

class _NoGoal extends GoalRepository {
  const _NoGoal();
  @override
  Future<Goal?> getActiveGoal() async => null;
}

class _FakeChat extends ChatRepository {
  _FakeChat(this.suggestions);
  List<String> suggestions;

  @override
  Future<ChatThread> createThread({String? title, String? goalId}) async =>
      const ChatThread(id: 't1');

  @override
  Future<List<ChatMessage>> getMessages(String threadId) async => const [];

  @override
  Future<({String answer, List<String> suggestions})> askAi({
    required String threadId,
    required String question,
    String? subjectId,
  }) async =>
      (answer: 'An answer.', suggestions: suggestions);
}

class _FakeCards extends FlashcardRepository {
  _FakeCards({this.fail = false});
  bool fail;
  final calls = <String>[];

  @override
  Future<int> cardsFromChat(String messageId) async {
    if (fail) throw Exception('generate-flashcards is down');
    calls.add(messageId);
    return 5;
  }
}
