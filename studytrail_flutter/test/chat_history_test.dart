// Chat history: every launch opens on a new chat, earlier ones live in a
// panel that slides in from the left. Supabase is faked at the repository
// seam (see stores_test.dart for why); the history query itself was checked
// against the live project.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/chat_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/chat_history_panel.dart';

void main() {
  group('ChatStore history', () {
    test('a launch opens on an empty new chat and writes nothing', () async {
      final chat = _Chats();
      final store = ChatStore(chat: chat, goals: const _NoGoal());
      addTearDown(store.dispose);

      await store.load();

      expect(store.thread, isNull);
      expect(store.messages, isEmpty);
      expect(chat.created, 0, reason: 'an unopened chat leaves no row behind');
    });

    test('the first question makes the chat; the next ones continue it',
        () async {
      final chat = _Chats();
      final store = ChatStore(chat: chat, goals: const _NoGoal());
      addTearDown(store.dispose);
      await store.load();

      await store.send('What is a process?');
      await store.send('And a thread?');

      expect(chat.created, 1);
      expect(store.thread, isNotNull);
      expect(store.messages.where((m) => m.isUser).map((m) => m.text),
          ['What is a process?', 'And a thread?']);
      expect(store.history.single.displayTitle, 'What is a process?');
    });

    test('New chat starts over, and the old one stays in the history',
        () async {
      final chat = _Chats();
      final store = ChatStore(chat: chat, goals: const _NoGoal());
      addTearDown(store.dispose);
      await store.load();
      await store.send('What is a process?');

      store.newThread();
      expect(store.thread, isNull);
      expect(store.messages, isEmpty);

      await store.send('Explain paging');
      expect(chat.created, 2);
      expect(store.history.map((t) => t.displayTitle),
          ['Explain paging', 'What is a process?']);
    });

    test('opening a past chat shows it, and asking carries it on', () async {
      final chat = _Chats()..seed('old', 'What is deadlock?');
      final store = ChatStore(chat: chat, goals: const _NoGoal());
      addTearDown(store.dispose);
      await store.load();
      await store.loadHistory();

      await store.openThread(store.history.single);
      expect(store.messages.first.text, 'What is deadlock?');

      await store.send('Give an example');
      expect(chat.created, 0, reason: 'it is the same chat');
      expect(chat.messages['old']!.where((m) => m.isUser), hasLength(2));
    });

    test('deleting the open chat starts a new one', () async {
      final chat = _Chats()..seed('old', 'What is deadlock?');
      final store = ChatStore(chat: chat, goals: const _NoGoal());
      addTearDown(store.dispose);
      await store.loadHistory();
      await store.openThread(store.history.single);

      expect(await store.deleteThread(store.history.single), isTrue);
      expect(store.history, isEmpty);
      expect(store.thread, isNull);
      expect(chat.messages.containsKey('old'), isFalse);
    });

    test('a failed history read stays out of the chat\'s error banner',
        () async {
      final store =
          ChatStore(chat: _Chats(historyFails: true), goals: const _NoGoal());
      addTearDown(store.dispose);

      await store.loadHistory();

      expect(store.historyError, isNotNull);
      expect(store.error, isNull);
    });
  });

  test('chats are grouped Today, Yesterday, Previous 7 days, Earlier', () {
    final now = DateTime(2026, 10, 4, 18);
    ChatThread at(String id, DateTime when) =>
        ChatThread(id: id, preview: id, createdAt: when);
    final groups = groupChatsByDay([
      at('a', DateTime(2026, 10, 4, 9)),
      at('b', DateTime(2026, 10, 3, 23)),
      at('c', DateTime(2026, 9, 29)),
      at('d', DateTime(2026, 9, 1)),
      at('e', DateTime(2026, 10, 4, 0, 5)),
    ], now);

    expect([for (final (label, _) in groups) label],
        ['Today', 'Yesterday', 'Previous 7 days', 'Earlier']);
    expect(groups.first.$2.map((t) => t.id), ['a', 'e']);
  });

  testWidgets(
      'the avatar opens the history; picking a chat opens it; New chat '
      'clears it — all at 320 dp', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 760 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final chat = _Chats()
      ..seed(
          'old',
          'Explain the difference between preemptive and non-preemptive '
              'scheduling with an example from a real operating system')
      ..seed('older', 'What is a semaphore?',
          at: DateTime.now().subtract(const Duration(days: 3)));
    final store = ChatStore(chat: chat, goals: const _NoGoal());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatStore>.value(value: store),
        ChangeNotifierProvider<OnboardingStore>(
            create: (_) => OnboardingStore(materials: const _NoMaterials())),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SafeArea(child: ChatScreen())),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Chat history'));
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('PREVIOUS 7 DAYS'), findsOneWidget);

    await tester.tap(find.text('What is a semaphore?'));
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsNothing);
    expect(store.thread?.id, 'older');
    expect(find.text('What is a semaphore?'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Chat history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New chat'));
    await tester.pumpAndSettle();
    expect(store.thread, isNull);
    expect(find.text('What is a semaphore?'), findsNothing);
  });
}

class _NoGoal extends GoalRepository {
  const _NoGoal();
  @override
  Future<Goal?> getActiveGoal() async => null;
}

class _NoMaterials extends MaterialRepository {
  const _NoMaterials();
  @override
  Future<List<StudyMaterial>> getMaterials({String? goalId}) async => const [];
  @override
  Future<List<MaterialPlaylist>> getPlaylists() async => const [];
}

/// Threads and messages in memory, shaped like the real tables.
class _Chats extends ChatRepository {
  _Chats({this.historyFails = false});

  final bool historyFails;
  final threads = <ChatThread>[];
  final messages = <String, List<ChatMessage>>{};
  int created = 0;

  void seed(String id, String question, {DateTime? at}) {
    threads.add(ChatThread(id: id, createdAt: at ?? DateTime.now()));
    messages[id] = [
      ChatMessage(id: '$id-q', role: ChatRole.user, text: question),
      ChatMessage(id: '$id-a', role: ChatRole.ai, text: 'An answer.'),
    ];
  }

  @override
  Future<ChatThread> createThread({String? title, String? goalId}) async {
    created++;
    final thread = ChatThread(id: 'new-$created', createdAt: DateTime.now());
    threads.add(thread);
    messages[thread.id] = [];
    return thread;
  }

  @override
  Future<List<ChatThread>> getHistory({int limit = 50}) async {
    if (historyFails) throw 'Could not load your chats.';
    final asked = [
      for (final t in threads)
        if (messages[t.id]?.any((m) => m.isUser) ?? false)
          ChatThread(
              id: t.id,
              createdAt: t.createdAt,
              preview: messages[t.id]!.firstWhere((m) => m.isUser).text),
    ]..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    return asked;
  }

  @override
  Future<List<ChatMessage>> getMessages(String threadId) async =>
      [...?messages[threadId]];

  @override
  Future<({String answer, List<String> suggestions})> askAi({
    required String threadId,
    required String question,
    String? subjectId,
  }) async {
    final list = messages[threadId]!;
    list.add(ChatMessage(
        id: '$threadId-${list.length}', role: ChatRole.user, text: question));
    list.add(ChatMessage(
        id: '$threadId-${list.length}', role: ChatRole.ai, text: 'Answer.'));
    return (answer: 'Answer.', suggestions: const <String>[]);
  }

  @override
  Future<void> deleteThread(String threadId) async {
    threads.removeWhere((t) => t.id == threadId);
    messages.remove(threadId);
  }
}
