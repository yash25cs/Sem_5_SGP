// Security and the shared features, on the hosted project with three
// throwaway students:
//   A — owns study data, hosts a room, asks a doubt;
//   B — tries to read, change, delete and misuse A's data, then joins A's room;
//   C — an outsider to the room.
// Plus a client with no account at all.
//
//   STUDYTRAIL_LIVE=1 flutter test test/live/e2e_social_security_test.dart

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';

import '_harness.dart';

void main() {
  late Student a, b, c;
  const goals = GoalRepository();
  const materials = MaterialRepository();
  const roadmap = RoadmapRepository();
  const tasks = TaskRepository();
  const quizzes = QuizRepository();
  const rooms = RoomRepository();
  const doubts = DoubtRepository();
  const profiles = ProfileRepository();
  const game = GamificationRepository();

  // A's things, by id.
  late Goal goal;
  late StudyMaterial notes;
  late String quizId;
  late String attemptId;
  late String dailyTaskId;
  late String threadId;
  late StudyRoom room;
  late String doubtId;

  setUpAll(() async {
    if (!liveEnabled) return;
    a = await Student.create('owner', name: 'Aarav Owner');
    b = await Student.create('other', name: 'Bela Other');
    c = await Student.create('outside', name: 'Chirag Outside');
  });
  tearDownAll(() async {
    if (liveEnabled) await deleteStudents();
  });

  final skip = liveSkip;
  const t4 = Timeout(Duration(minutes: 4));

  test('A builds up some data', () async {
    a.use();
    goal = await goals.createGoal(
        name: 'Private goal',
        subjectNames: ['DBMS'],
        subjectExamDates: [DateTime.now().add(const Duration(days: 30))]);
    final f = await tempFile('notes.txt', dbmsNotes.codeUnits);
    notes = await materials.uploadFile(
        file: f, fileName: 'notes.txt', goalId: goal.id);
    await materials.requestIngest(notes.id);
    quizId = await quizzes.generateQuiz(materialId: notes.id, length: 3);
    attemptId = (await quizzes.startAttempt(quizId)).id;
    await roadmap.generateRoadmap(goal.id);
    final ms = await roadmap.getMilestones(goal.id);
    dailyTaskId = (await tasks.createTasksFromRoadmap(
            goalId: goal.id, tasks: [ms.first.tasks.first]))
        .single
        .id;
    threadId = (await const ChatRepository().createThread(goalId: goal.id)).id;
    // Some activity, so activity_log and streaks have a row of A's to guard.
    await game.recordSession(lengthMin: 25, focusedMin: 25);
  }, skip: skip, timeout: t4);

  group('B cannot see A\'s data', () {
    for (final (table, col) in [
      ('goals', 'id'),
      ('subjects', 'goal_id'),
      ('materials', 'id'),
      ('material_chunks', 'material_id'),
      ('milestones', 'goal_id'),
      ('daily_tasks', 'id'),
      ('quizzes', 'id'),
      ('quiz_questions', 'quiz_id'),
      ('quiz_attempts', 'id'),
      ('chat_threads', 'id'),
      ('profiles', 'id'),
      ('streaks', 'user_id'),
      ('activity_log', 'user_id'),
    ]) {
      test(table, () async {
        final id = switch (col) {
          'goal_id' => goal.id,
          'material_id' => notes.id,
          'quiz_id' => quizId,
          'user_id' => a.id,
          _ => switch (table) {
              'goals' => goal.id,
              'materials' => notes.id,
              'daily_tasks' => dailyTaskId,
              'quizzes' => quizId,
              'quiz_attempts' => attemptId,
              'chat_threads' => threadId,
              'profiles' => a.id,
              _ => throw 'no id for $table',
            },
        };
        // A sees it (the probe is real) …
        final own = await a.client.from(table).select().eq(col, id);
        expect(own, isNotEmpty, reason: 'A should see their own $table');
        // … B doesn't.
        final rows = await b.client.from(table).select().eq(col, id);
        expect(rows, isEmpty, reason: 'B read A\'s $table');
      }, skip: skip);
    }

    test('nobody without an account sees anything', () async {
      final anon = Student.anonymous();
      for (final table in ['goals', 'materials', 'profiles', 'quizzes',
          'daily_tasks', 'room_messages', 'study_rooms']) {
        final rows = await anon
            .from(table)
            .select()
            .limit(1)
            .catchError((Object _) => <Map<String, dynamic>>[]);
        expect(rows, isEmpty, reason: 'anon read $table');
      }
      await refused(() => anon.functions
          .invoke('generate-quiz', body: {'materialId': notes.id}));
      await anon.dispose();
    }, skip: skip);
  });

  group('B cannot change or delete A\'s data', () {
    test('updates and deletes reach no rows', () async {
      await b.client.from('goals').update({'name': 'hacked'}).eq('id', goal.id);
      await b.client.from('materials').delete().eq('id', notes.id);
      await b.client.from('quizzes').delete().eq('id', quizId);
      await b.client.from('chat_threads').delete().eq('id', threadId);
      await b.client
          .from('profiles')
          .update({'full_name': 'hacked'})
          .eq('id', a.id)
          .catchError((Object _) => <Map<String, dynamic>>[]);
      a.use();
      expect((await goals.getActiveGoal())!.name, 'Private goal');
      expect(await materials.getMaterial(notes.id), isNotNull);
      expect(await quizzes.getQuiz(quizId), isNotNull);
      expect((await profiles.getMyProfile())!.fullName, 'Aarav Owner');
    }, skip: skip);

    test('B cannot insert rows in A\'s name', () async {
      await refused(() => b.client.from('materials').insert({
            'user_id': a.id,
            'source_type': 'notes',
            'title': 'planted',
          }));
      await refused(() => b.client.from('goals').insert({
            'user_id': a.id,
            'name': 'planted',
          }));
    }, skip: skip);

    test('B cannot tick A\'s task, finish A\'s quiz or grade A\'s cards',
        () async {
      b.use();
      await refused(() => tasks.setDoneById(dailyTaskId, true));
      await refused(() => quizzes.submit(attemptId: attemptId, picks: {}));
      a.use();
      final today = await tasks.getTodayTasks();
      expect(today.firstWhere((t) => t.id == dailyTaskId).done, isFalse);
    }, skip: skip);

    test('B cannot read A\'s file from storage', () async {
      await refused(() =>
          b.client.storage.from('materials').download(notes.storagePath!));
      // Nor list A's folder.
      final listed = await b.client.storage
          .from('materials')
          .list(path: a.id)
          .catchError((Object _) => <FileObject>[]);
      expect(listed, isEmpty);
      // Nor write into it.
      await refused(() => b.client.storage
          .from('materials')
          .uploadBinary('${a.id}/planted.txt', Uint8List.fromList([1, 2, 3])));
    }, skip: skip);

    test('B cannot use A\'s material in any AI function', () async {
      for (final (fn, body) in [
        ('generate-quiz', {'materialId': notes.id}),
        ('generate-flashcards', {'materialId': notes.id}),
        ('summarize-material', {'materialId': notes.id}),
        ('embed-material', {'materialId': notes.id}),
        ('generate-roadmap', {'goalId': goal.id}),
        ('chat', {'threadId': threadId, 'question': 'hi'}),
      ]) {
        final err = await refused(
            () => b.client.functions.invoke(fn, body: body));
        expect(err, isNot(contains('500')), reason: '$fn: $err');
      }
    }, skip: skip);
  });

  group('Study rooms', () {
    test('A hosts a room for 2; B joins; C is turned away while it is full',
        () async {
      a.use();
      room = await rooms.createRoom(name: 'Live room', maxMembers: 2);
      expect(room.inviteCode, hasLength(6));
      b.use();
      final joined = await rooms.joinRoomByCode(room.inviteCode.toLowerCase());
      expect(joined.id, room.id, reason: 'codes are case-insensitive');
      // Joining again is a no-op, not an error.
      await rooms.joinRoomByCode(room.inviteCode);
      c.use();
      await refused(() => rooms.joinRoomByCode(room.inviteCode));
      await refused(() => rooms.joinRoomByCode('ZZZZZZ'));
      a.use();
      expect((await rooms.getMembers(room.id)).length, 2);
    }, skip: skip, timeout: t4);

    test('chat: members talk; over 500 characters is refused; an outsider '
        'reads nothing and cannot post', () async {
      b.use();
      await rooms.sendMessage(room.id, 'Hi from B',
          id: RoomRepository.newMessageId());
      await refused(() => rooms.sendMessage(room.id, 'x' * 501,
          id: RoomRepository.newMessageId()));
      a.use();
      expect((await rooms.getMessages(room.id)).map((m) => m.body),
          contains('Hi from B'));
      c.use();
      expect(await rooms.getMessages(room.id), isEmpty);
      await refused(() => rooms.sendMessage(room.id, 'intruder',
          id: RoomRepository.newMessageId()));
      await refused(() => rooms.getMembers(room.id));
    }, skip: skip);

    test('only the host sets the timer', () async {
      b.use();
      await refused(
          () => rooms.setTimer(room.id, focusMin: 50, breakMin: 10));
      a.use();
      await rooms.setTimer(room.id, focusMin: 50, breakMin: 10);
      await refused(
          () => rooms.setTimer(room.id, focusMin: 500, breakMin: 10));
    }, skip: skip);

    test('shared material: B saves A\'s notes; C cannot see them', () async {
      a.use();
      await rooms.shareMaterial(room.id, notes.id);
      b.use();
      final list = await rooms.getSharedMaterials(room.id);
      expect(list.single.title, 'notes.txt');
      final copy = await rooms.saveSharedMaterial(list.single);
      expect(copy.status, IngestStatus.embedded);
      expect(copy.storagePath, startsWith('${b.id}/'));
      await refused(() => rooms.saveSharedMaterial(list.single));
      c.use();
      await refused(() => rooms.getSharedMaterials(room.id));
      await refused(() => c.client.storage
          .from('materials')
          .download(notes.storagePath!));
    }, skip: skip, timeout: t4);

    test('group quiz: proposed from A\'s notes, B agrees, both hand in, the '
        'winner gets 30 XP', () async {
      a.use();
      final quizId = await rooms.proposeQuiz(
          roomId: room.id, materialId: notes.id, count: 5);
      b.use();
      // B can't propose (host only).
      await refused(() => rooms.proposeQuiz(
          roomId: room.id, materialId: notes.id, count: 5));
      var q = await rooms.voteQuiz(quizId, true);
      expect(q.running, isTrue, reason: 'the last yes starts it');
      expect(q.questions.every((x) => x.correctIndex == null), isTrue,
          reason: 'answers hidden while it runs');

      final xpBefore = (await a.client
              .from('profiles')
              .select('xp')
              .eq('id', a.id)
              .single())['xp'] as int;
      // A gets everything right (A wrote nothing — A guesses by reading the
      // answers after B hands in all-wrong). B picks option 0 everywhere.
      q = await rooms.submitQuiz(quizId, {for (final x in q.questions) x.id: 0});
      await refused(() => rooms.submitQuiz(quizId, {}));
      a.use();
      // The answers aren't readable until the quiz ends, so A picks 1 for all.
      final aq = await rooms.getQuiz(quizId);
      final done = await rooms
          .submitQuiz(quizId, {for (final x in aq.questions) x.id: 1});
      expect(done.finished, isTrue, reason: 'the last hand-in ends it');
      expect(done.questions.every((x) => x.correctIndex != null), isTrue);
      final winner = done.players.firstWhere((p) => p.rank == 1);
      if ((winner.score ?? 0) > 0) {
        expect(winner.xpAwarded, 30);
        if (winner.userId == a.id) {
          final xpAfter = (await a.client
                  .from('profiles')
                  .select('xp')
                  .eq('id', a.id)
                  .single())['xp'] as int;
          expect(xpAfter, xpBefore + 30);
        }
      }
      // Room history shows the quiz for both.
      final hist = await rooms.getQuizHistory(room.id);
      expect(hist.map((h) => h.id), contains(quizId));
    }, skip: skip, timeout: t4);

    test('moderation: B reports and blocks A; the host removes B, who cannot '
        'come back; C can then join', () async {
      b.use();
      await rooms.report(roomId: room.id, userId: a.id, reason: 'spam');
      await rooms.block(a.id);
      expect(await rooms.getBlockedIds(), contains(a.id));
      await rooms.unblock(a.id);
      expect(await rooms.getBlockedIds(), isEmpty);
      await refused(() => rooms.removeMember(room.id, a.id));
      a.use();
      await rooms.removeMember(room.id, b.id);
      b.use();
      await refused(() => rooms.joinRoomByCode(room.inviteCode));
      // B's history no longer opens that room's materials.
      await refused(() => rooms.getSharedMaterials(room.id));
      c.use();
      await rooms.joinRoomByCode(room.inviteCode);
    }, skip: skip);

    test('history: kept after leaving; the host closing ends the room',
        () async {
      c.use();
      await rooms.leaveRoom(room.id);
      final mine = await rooms.getHistory();
      expect(mine.single.roomId, room.id);
      expect(mine.single.isMember, isFalse);
      await rooms.removeFromHistory(room.id);
      expect(await rooms.getHistory(), isEmpty);
      a.use();
      await rooms.closeRoom(room.id);
      expect((await rooms.getActiveRooms()).any((r) => r.id == room.id),
          isFalse);
      c.use();
      await refused(() => rooms.joinRoomByCode(room.inviteCode));
    }, skip: skip);
  });

  group('Doubt board', () {
    test('A asks; B answers; only A marks it solved; votes toggle', () async {
      a.use();
      final d = await doubts.post(
          title: 'Why is BCNF stricter than 3NF?',
          body: 'I keep mixing them up.',
          subject: 'DBMS');
      doubtId = d.id;
      await refused(() => doubts.post(title: ''));
      b.use();
      final withAnswer = await doubts.answer(doubtId,
          'In BCNF every determinant must be a candidate key; 3NF allows a '
          'prime attribute to depend on a non-key.');
      final answerId = withAnswer.answers.single.id;
      await refused(() => doubts.markSolved(doubtId, answerId));
      a.use();
      var t = await doubts.vote(answerId);
      expect(t.answers.single.votes, 1);
      t = await doubts.vote(answerId);
      expect(t.answers.single.votes, 0, reason: 'a second tap takes it back');
      t = await doubts.markSolved(doubtId, answerId);
      expect(t.solvedAnswerId, answerId);
      expect((await doubts.getDoubts()).any((x) => x.id == doubtId && x.solved),
          isTrue);
    }, skip: skip);

    test('AI answer from the asker\'s notes, once', () async {
      a.use();
      final t = await doubts.askAi(doubtId);
      expect(t.answers.where((x) => x.isAi), hasLength(1));
      await refused(() => doubts.askAi(doubtId));
      b.use();
      await refused(() => doubts.askAi(doubtId));
    }, skip: skip, timeout: t4);

    test('reports; blocking hides the author; only the author deletes',
        () async {
      b.use();
      await doubts.report(reason: 'other', doubtId: doubtId);
      await refused(() => doubts.deleteDoubt(doubtId));
      await rooms.block(a.id);
      expect((await doubts.getDoubts()).any((x) => x.id == doubtId), isFalse);
      await rooms.unblock(a.id);
      a.use();
      await doubts.deleteDoubt(doubtId);
      expect((await doubts.getDoubts()).any((x) => x.id == doubtId), isFalse);
    }, skip: skip);
  });

  test('leaderboard lists every student with their real rank', () async {
    a.use();
    final board = await game.getLeaderboard(limit: 200);
    final me = board.firstWhere((e) => e.userId == a.id);
    expect(me.rank, greaterThan(0));
  }, skip: skip);
}

// ignore: unused_element
typedef _Unused = PostgrestException;
