// Materials shared in a study room, each student's room history, and the
// delete options for quiz attempts, whole lists of quizzes and decks, and
// single flashcards.
//
// Stores and screens run against fake repositories. The database side
// (who may see, save or unshare a material; history kept after leaving;
// outsiders refused) was checked against the live project in a rolled-back
// transaction when 0030 was written.

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'package:studytrail_flutter/data/flashcard_cache.dart';
import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';
import 'package:studytrail_flutter/screens/flashcards_screen.dart';
import 'package:studytrail_flutter/screens/quiz_screen.dart';
import 'package:studytrail_flutter/screens/room_quiz_screen.dart';
import 'package:studytrail_flutter/state/stores.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';
import 'package:studytrail_flutter/widgets/room_materials.dart';

const _me = 'me-id';
const _other = 'other-id';

StudyRoom _room() => StudyRoom(
      id: 'r1',
      name: 'DBMS revision',
      inviteCode: 'ABC123',
      createdBy: _other,
      createdAt: DateTime(2026, 10, 11),
    );

RoomSharedMaterial _share(String id,
        {String by = _other, bool saved = false, String? title}) =>
    RoomSharedMaterial(
      id: id,
      roomId: 'r1',
      materialId: 'm-$id',
      title: title ?? 'Notes $id',
      sourceType: MaterialType.notes,
      storagePath: '$by/1700000000000_notes_$id.pdf',
      sharedBy: by,
      sharedByName: by == _me ? 'Yash Patel' : 'Ravi Shah',
      createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      saved: saved,
    );

class _Rooms extends RoomRepository {
  var shared = <RoomSharedMaterial>[_share('s1'), _share('s2', by: _me)];
  var history = <RoomHistoryEntry>[
    RoomHistoryEntry(
      roomId: 'old',
      name: 'Physics crash course',
      inviteCode: 'ZZZ999',
      status: 'closed',
      role: 'host',
      createdAt: DateTime(2026, 10, 1),
      firstJoinedAt: DateTime(2026, 10, 1, 9),
      lastJoinedAt: DateTime(2026, 10, 1, 9),
      leftAt: DateTime(2026, 10, 1, 11),
      materialCount: 1,
      quizCount: 1,
    ),
  ];
  final sharedIds = <String>[];
  final unshared = <String>[];
  final savedShares = <String>[];
  final removedHistory = <String>[];
  String? saveError;

  @override
  Future<List<StudyRoom>> getActiveRooms() async => const [];

  @override
  Future<RoomQuiz?> getActiveQuiz(String roomId) async => null;

  @override
  Future<List<RoomSharedMaterial>> getSharedMaterials(String roomId) async =>
      roomId == 'old' ? [_share('h1', title: 'Optics summary')] : shared;

  @override
  Future<void> shareMaterial(String roomId, String materialId) async {
    sharedIds.add(materialId);
    shared = [
      RoomSharedMaterial(
        id: 'new',
        roomId: roomId,
        materialId: materialId,
        title: 'Fresh notes',
        sourceType: MaterialType.notes,
        sharedBy: _me,
        sharedByName: 'Yash Patel',
        createdAt: DateTime.now(),
        saved: true,
      ),
      ...shared,
    ];
  }

  @override
  Future<void> unshareMaterial(String shareId) async => unshared.add(shareId);

  @override
  Future<StudyMaterial> saveSharedMaterial(RoomSharedMaterial share) async {
    if (saveError != null) throw saveError!;
    savedShares.add(share.id);
    return StudyMaterial(
      id: 'copy-${share.id}',
      sourceType: share.sourceType,
      title: share.title,
      status: IngestStatus.embedded,
    );
  }

  @override
  Future<List<RoomHistoryEntry>> getHistory({int limit = 50}) async => history;

  @override
  Future<List<RoomMember>> getMembers(String roomId) async => const [];

  @override
  Future<List<RoomMessage>> getMessages(String roomId, {int limit = 50}) async =>
      const [];

  @override
  Future<List<RoomQuizResult>> getQuizHistory(String roomId) async => [
        RoomQuizResult(
          id: 'rq1',
          title: 'Lenses quiz',
          mode: 'standard',
          questionCount: 10,
          finishedAt: DateTime(2026, 10, 1, 10),
          score: 7,
          rank: 2,
          players: 3,
        ),
      ];

  @override
  Future<void> removeFromHistory(String roomId) async =>
      removedHistory.add(roomId);
}

/// A library with one ready material, for the Share sheet and the limit.
class _Materials extends MaterialRepository {
  _Materials({this.count = 1});
  final int count;

  @override
  Future<List<StudyMaterial>> getMaterials({String? goalId}) async => [
        for (var i = 0; i < count; i++)
          StudyMaterial(
            id: 'lib-$i',
            sourceType: MaterialType.notes,
            title: 'My notes $i',
            status: IngestStatus.embedded,
          ),
      ];

  @override
  Future<List<MaterialPlaylist>> getPlaylists() async => const [];
}

Future<void> _pump(WidgetTester tester, Widget child,
    List<ChangeNotifierProvider> providers) async {
  tester.view.physicalSize = const Size(320 * 3, 760 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: providers,
    child: MaterialApp(theme: AppTheme.light(), home: child),
  ));
  await tester.pumpAndSettle();
}

Finder _inDialog(String text) => find.descendant(
    of: find.byType(AlertDialog), matching: find.text(text));

Finder _inSheet(String text) => find.descendant(
    of: find.byType(BottomSheet), matching: find.text(text));

void main() {
  group('Room materials (store)', () {
    late _Rooms repo;
    late RoomStore store;

    setUp(() async {
      repo = _Rooms();
      store = RoomStore(roomRepo: repo, quizPollInterval: null)
        ..debugUserId = _me;
      await store.debugEnterRoomWithoutChannel(_room());
    });

    test('entering a room loads what was shared there', () {
      expect(store.sharedMaterials.map((s) => s.id), ['s1', 's2']);
    });

    test('sharing reloads the list', () async {
      final ok = await store.shareMaterial(const StudyMaterial(
          id: 'lib-0', sourceType: MaterialType.notes));
      expect(ok, isTrue);
      expect(repo.sharedIds, ['lib-0']);
      expect(store.sharedMaterials.first.id, 'new');
    });

    test('only the sharer or the host may unshare', () async {
      expect(store.canUnshare(store.sharedMaterials[1]), isTrue,
          reason: 'I shared s2');
      expect(store.canUnshare(store.sharedMaterials[0]), isFalse,
          reason: 'Ravi shared s1 and I am not the host');
      await store.unshareMaterial(store.sharedMaterials[1]);
      expect(repo.unshared, ['s2']);
      expect(store.sharedMaterials.map((s) => s.id), ['s1']);
    });

    test('saving a copy marks it saved; a refusal keeps it unsaved',
        () async {
      repo.saveError = "You've already saved this to your library.";
      expect(await store.saveShared(store.sharedMaterials[0]), isNull);
      expect(store.error, contains('already saved'));
      expect(store.sharedMaterials[0].saved, isFalse);

      repo.saveError = null;
      final copy = await store.saveShared(store.sharedMaterials[0]);
      expect(copy?.id, 'copy-s1');
      expect(store.sharedMaterials[0].saved, isTrue);
      expect(store.isSaving('s1'), isFalse);
    });

    test('refresh picks up a share whose ping was missed', () async {
      repo.shared = [_share('late'), ...repo.shared];
      expect(store.sharedMaterials, hasLength(2));
      expect(await store.refreshRoom(), isTrue);
      expect(store.sharedMaterials.map((s) => s.id), ['late', 's1', 's2']);
      expect(store.refreshing, isFalse);
    });

    test('the lobby loads history; removing one drops it', () async {
      await store.loadLobby();
      expect(store.history.single.name, 'Physics crash course');
      expect(await store.removeFromHistory('old'), isTrue);
      expect(repo.removedHistory, ['old']);
      expect(store.history, isEmpty);
    });
  });

  group('Room materials (screens)', () {
    late _Rooms repo;
    late RoomStore rooms;

    setUp(() async {
      repo = _Rooms();
      rooms = RoomStore(roomRepo: repo, quizPollInterval: null)
        ..debugUserId = _me;
      await rooms.debugEnterRoomWithoutChannel(_room());
    });

    List<ChangeNotifierProvider> providers({int libraryCount = 1}) => [
          ChangeNotifierProvider<RoomStore>.value(value: rooms),
          ChangeNotifierProvider<OnboardingStore>(
              create: (_) => OnboardingStore(
                  materials: _Materials(count: libraryCount))),
        ];

    testWidgets('the card shows Save for others\' files and Yours for mine',
        (tester) async {
      await _pump(
          tester,
          const Scaffold(body: SingleChildScrollView(child: RoomMaterialsCard())),
          providers());
      expect(find.text('Shared materials (2)'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('YOURS'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.savedShares, ['s1']);
      expect(find.text('IN LIBRARY'), findsOneWidget);
      expect(find.textContaining('is in your library'), findsOneWidget);
    });

    testWidgets('a full library refuses to save', (tester) async {
      await _pump(
          tester,
          const Scaffold(body: SingleChildScrollView(child: RoomMaterialsCard())),
          providers(libraryCount: OnboardingStore.maxMaterials));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.savedShares, isEmpty);
      expect(find.textContaining('Your library is full'), findsOneWidget);
    });

    testWidgets('Share lists ready library files and shares the one picked',
        (tester) async {
      await _pump(
          tester,
          const Scaffold(body: SingleChildScrollView(child: RoomMaterialsCard())),
          providers());
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My notes 0'));
      await tester.pumpAndSettle();
      expect(repo.sharedIds, ['lib-0']);
      expect(find.text('Shared materials (3)'), findsOneWidget);
    });

    testWidgets('a past room shows its materials and quizzes, and can be '
        'removed from history', (tester) async {
      await rooms.loadLobby();
      await _pump(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showRoomHistorySheet(context, rooms.history.single),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          providers());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Physics crash course'), findsOneWidget);
      expect(find.text('CLOSED'), findsOneWidget);
      expect(find.textContaining('You created this room'), findsOneWidget);
      expect(find.text('Optics summary'), findsOneWidget);
      expect(find.text('Lenses quiz'), findsOneWidget);
      expect(find.text('7/10'), findsOneWidget);
      expect(find.textContaining('#2 of 3'), findsOneWidget);
      expect(find.text('Rejoin room'), findsNothing,
          reason: 'a closed room cannot be rejoined');

      await tester.ensureVisible(find.text('Remove from history'));
      await tester.tap(find.text('Remove from history'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete'));
      await tester.pumpAndSettle();
      expect(repo.removedHistory, ['old']);
      expect(find.text('Physics crash course'), findsNothing);
    });
  });

  group('Speed round', () {
    testWidgets('an answer can be changed while time is left', (tester) async {
      final repo = _Speed();
      final store = RoomStore(roomRepo: repo, quizPollInterval: null)
        ..debugUserId = _me;
      await store.debugEnterRoomWithoutChannel(_room());
      await _pump(tester, const RoomQuizScreen(),
          [ChangeNotifierProvider<RoomStore>.value(value: store)]);

      await tester.tap(find.text('Read committed'));
      await tester.pump();
      expect(repo.answers, [1]);
      expect(find.textContaining('Tap another option to change it'),
          findsOneWidget);

      await tester.tap(find.text('Repeatable read'));
      await tester.pump();
      expect(repo.answers, [1, 2], reason: 'the second tap changes it');

      await tester.tap(find.text('Repeatable read'));
      await tester.pump();
      expect(repo.answers, [1, 2], reason: 'the same option again is a no-op');

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });

  group('Quiz history and delete all', () {
    late _Quizzes quizzes;

    setUp(() => quizzes = _Quizzes());

    List<ChangeNotifierProvider> providers() => [
          ChangeNotifierProvider<QuizStore>(
              create: (_) => QuizStore(quizzes: quizzes)),
          ChangeNotifierProvider<WeakSpotsStore>(
              create: (_) => WeakSpotsStore(quizzes: quizzes)),
        ];

    testWidgets('History lists past attempts; one can be deleted',
        (tester) async {
      await _pump(tester, const QuizScreen(), providers());
      await tester.tap(find.text('Optics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('Past attempts'), findsOneWidget);
      expect(find.text('8/10'), findsWidgets);
      expect(find.text('5/10'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete attempt').last);
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete'));
      await tester.pumpAndSettle();
      expect(quizzes.deletedAttempts, ['a0']);
      expect(find.text('5/10'), findsNothing);
    });

    testWidgets('Clear history removes every attempt but keeps the quiz',
        (tester) async {
      await _pump(tester, const QuizScreen(), providers());
      await tester.tap(find.text('Optics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete'));
      await tester.pumpAndSettle();

      expect(quizzes.clearedFor, ['qa']);
      expect(find.text('Past attempts'), findsNothing);
      expect(find.text('Optics'), findsOneWidget);
    });

    testWidgets('delete all asks, then empties the list', (tester) async {
      await _pump(tester, const QuizScreen(), providers());
      await tester.tap(find.byIcon(Symbols.delete_sweep));
      await tester.pumpAndSettle();
      expect(find.text('Delete all quizzes?'), findsOneWidget);
      await tester.tap(_inDialog('Delete'));
      await tester.pumpAndSettle();
      expect(quizzes.deletedAll, isTrue);
      expect(find.text('No quizzes yet'), findsOneWidget);
    });
  });

  group('Flashcards: single cards and delete all', () {
    late _Cards cards;
    late _MemoryCache cache;

    setUp(() {
      cards = _Cards();
      cache = _MemoryCache();
    });

    List<ChangeNotifierProvider> providers() => [
          ChangeNotifierProvider<FlashcardStore>(
              create: (_) => FlashcardStore(cards: cards, cache: cache)),
          ChangeNotifierProvider<WeakSpotsStore>(
              create: (_) => WeakSpotsStore(cards: cards)),
        ];

    testWidgets('Cards lists a deck\'s cards; one can be deleted',
        (tester) async {
      await _pump(tester, const FlashcardsScreen(), providers());
      await tester.tap(find.text('Physics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cards'));
      await tester.pumpAndSettle();
      expect(find.text('Front 1'), findsOneWidget);
      expect(_inSheet('2 cards'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete card').first);
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete'));
      await tester.pumpAndSettle();
      expect(cards.deletedCards, ['d1-1']);
      expect(find.text('Front 1'), findsNothing);
      expect(_inSheet('1 card'), findsOneWidget);
    });

    test('deleting the card under review moves on to the next', () async {
      final store = FlashcardStore(cards: cards, cache: cache);
      await store.load();
      await store.startSession(deckId: 'd1');
      expect(store.current?.id, 'd1-1');
      store.reveal();
      expect(await store.deleteCard(store.current!), isTrue);
      expect(store.current?.id, 'd1-2');
      expect(store.revealed, isFalse);
      expect(store.queue.length, 1);
    });

    testWidgets('delete all asks, then empties the decks and the offline copy',
        (tester) async {
      await _pump(tester, const FlashcardsScreen(), providers());
      await tester.tap(find.byIcon(Symbols.delete_sweep));
      await tester.pumpAndSettle();
      expect(find.text('Delete all decks?'), findsOneWidget);
      await tester.tap(_inDialog('Delete'));
      await tester.pumpAndSettle();
      expect(cards.deletedAll, isTrue);
      expect(find.text('No decks yet'), findsOneWidget);
      expect(cache.deckList, isEmpty);
    });
  });
}

class _Quizzes extends QuizRepository {
  final deletedAttempts = <String>[];
  final clearedFor = <String>[];
  var deletedAll = false;

  late var _attempts = [
    QuizAttempt(
      id: 'a1',
      quizId: 'qa',
      score: 8,
      total: 10,
      xpEarned: 80,
      completedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    QuizAttempt(
      id: 'a0',
      quizId: 'qa',
      score: 5,
      total: 10,
      xpEarned: 50,
      completedAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

  late var _quizzes = [
    Quiz(id: 'qa', title: 'Optics', length: 10, lastAttempt: _attempts.first),
  ];

  @override
  Future<List<Quiz>> getQuizzes({String? subjectId}) async => _quizzes;

  @override
  Future<List<QuizAttempt>> getAttempts({String? quizId, int limit = 20}) async =>
      _attempts.where((a) => a.quizId == quizId).toList();

  @override
  Future<void> deleteAttempt(String attemptId) async {
    deletedAttempts.add(attemptId);
    _attempts = _attempts.where((a) => a.id != attemptId).toList();
  }

  @override
  Future<void> deleteAttempts(String quizId) async {
    clearedFor.add(quizId);
    _attempts = const [];
    _quizzes = [const Quiz(id: 'qa', title: 'Optics', length: 10)];
  }

  @override
  Future<void> deleteAllQuizzes() async {
    deletedAll = true;
    _quizzes = const [];
  }

  @override
  Future<List<WeakTopic>> getWeakTopics({int limit = 5}) async => const [];
}

class _Cards extends FlashcardRepository {
  final deletedCards = <String>[];
  var deletedAll = false;

  late var _cards = [
    for (final i in [1, 2])
      Flashcard(
        id: 'd1-$i',
        deckId: 'd1',
        front: 'Front $i',
        back: 'Back $i',
        dueAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
  ];

  @override
  Future<List<FlashcardDeck>> getDecks() async => deletedAll
      ? const []
      : [
          FlashcardDeck(
              id: 'd1',
              name: 'Physics',
              total: _cards.length,
              due: _cards.length),
        ];

  @override
  Future<List<Flashcard>> getUpcomingCards(
          {int days = 7, int limit = 300}) async =>
      _cards;

  @override
  Future<List<Flashcard>> getDueCards({String? deckId, int limit = 40}) async =>
      _cards;

  @override
  Future<List<Flashcard>> getDeckCards(String deckId) async => _cards;

  @override
  Future<void> deleteCard(String cardId) async {
    deletedCards.add(cardId);
    _cards = _cards.where((c) => c.id != cardId).toList();
  }

  @override
  Future<void> deleteAllDecks() async => deletedAll = true;
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

/// A speed round 3 s into its first 20 s question; answers replace each other
/// the way 0031 does on the server.
class _Speed extends RoomRepository {
  final started = DateTime.now().toUtc().subtract(const Duration(seconds: 8));
  final answers = <int>[];
  int? pick;

  RoomQuiz get _quiz => RoomQuiz.fromMap({
        'id': 'q1',
        'room_id': 'r1',
        'created_by': _other,
        'title': 'Transactions speed round',
        'question_count': 2,
        'status': 'running',
        'mode': 'speed',
        'seconds_per_question': 20,
        'started_at': started.toIso8601String(),
        'server_now': DateTime.now().toUtc().toIso8601String(),
        'players': [
          {'user_id': _other, 'full_name': 'Ravi', 'score': 0},
          {'user_id': _me, 'full_name': 'Yash', 'score': 0},
        ],
        'questions': [
          {
            'id': 'a',
            'question': 'Which level prevents non-repeatable reads?',
            'options': [
              'Read uncommitted',
              'Read committed',
              'Repeatable read',
              'Serializable',
            ],
          },
          {
            'id': 'b',
            'question': 'Second question',
            'options': ['w', 'x', 'y', 'z'],
          },
        ],
        'my_picks': pick == null ? null : {'a': pick},
      });

  @override
  Future<RoomQuiz?> getActiveQuiz(String roomId) async => _quiz;

  @override
  Future<RoomQuiz> getQuiz(String quizId) async => _quiz;

  @override
  Future<RoomQuiz> tickQuiz(String quizId) async => _quiz;

  @override
  Future<RoomQuiz> answerSpeed(String quizId, String questionId, int p) async {
    answers.add(p);
    pick = p;
    return _quiz;
  }
}
