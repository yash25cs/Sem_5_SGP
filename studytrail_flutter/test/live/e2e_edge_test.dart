// Odd input and awkward timing on the hosted project, through the app's real
// repositories: Hindi/Gujarati and emoji text, very long text, exams already
// past or tomorrow, out-of-range sizes, double taps, and deleting things that
// other features still point at.
//
//   STUDYTRAIL_LIVE=1 flutter test test/live/e2e_edge_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';

import '_harness.dart';

void main() {
  late Student s;
  const goals = GoalRepository();
  const materials = MaterialRepository();
  const roadmap = RoadmapRepository();
  const quizzes = QuizRepository();
  const cards = FlashcardRepository();
  const chat = ChatRepository();
  const rooms = RoomRepository();
  const doubts = DoubtRepository();
  const profiles = ProfileRepository();

  late StudyMaterial notes;

  setUpAll(() async {
    if (!liveEnabled) return;
    s = await Student.create('edge', name: 'યશ પટેલ 📚');
  });
  setUp(() {
    if (liveEnabled) s.use();
  });
  tearDownAll(() async {
    if (liveEnabled) await deleteStudents();
  });

  final skip = liveSkip;
  const t4 = Timeout(Duration(minutes: 4));

  test('Gujarati name with an emoji survives sign-up and shows its initial',
      () async {
    final p = (await profiles.getMyProfile())!;
    expect(p.fullName, 'યશ પટેલ 📚');
    expect(p.initial, isNotEmpty);
  }, skip: skip);

  test('goal: Hindi subject names, duplicates kept once, a 120-character '
      'name, no subjects at all; 121 characters is refused', () async {
    await refused(() => goals.createGoal(name: 'x' * 121));
    final g = await goals.createGoal(
      name: 'सेमेस्टर ५ — ${'x' * 107}',
      subjectNames: ['गणित', 'गणित', 'DBMS'],
      subjectExamDates: [
        DateTime.now().add(const Duration(days: 10)),
        DateTime.now().add(const Duration(days: 50)),
        null,
      ],
    );
    final subs = await goals.getSubjects(g.id);
    expect(subs.map((x) => x.name).toList()..sort(), ['DBMS', 'गणित'],
        reason: 'the first of a repeated name is kept');
    final math = subs.firstWhere((x) => x.name == 'गणित');
    expect(math.examDate!.difference(DateTime.now()).inDays,
        inInclusiveRange(9, 10));
    await goals.deleteGoal(g.id);

    final bare = await goals.createGoal(name: 'No subjects yet');
    expect(await goals.getSubjects(bare.id), isEmpty);
    await goals.deleteGoal(bare.id);
  }, skip: skip);

  test('an empty goal name is refused', () async {
    await refused(() => goals.createGoal(name: '   '));
  }, skip: skip);

  test('roadmap for an exam tomorrow still makes a plan; one already past '
      'gets a revision plan at the goal’s pace (by design)', () async {
    final soon = await goals.createGoal(
        name: 'Tomorrow',
        subjectNames: ['DBMS'],
        subjectExamDates: [DateTime.now().add(const Duration(days: 1))]);
    final f = await tempFile('notes.txt', dbmsNotes.codeUnits);
    notes = await materials.uploadFile(
        file: f, fileName: 'notes.txt', goalId: soon.id);
    await materials.requestIngest(notes.id);
    expect(await roadmap.generateRoadmap(soon.id), greaterThanOrEqualTo(1));

    final past = await goals.createGoal(
        name: 'Past',
        subjectNames: ['DBMS'],
        subjectExamDates: [DateTime.now().subtract(const Duration(days: 3))]);
    expect(await roadmap.generateRoadmap(past.id), greaterThanOrEqualTo(1));
    await goals.deleteGoal(past.id);
  }, skip: skip, timeout: t4);

  test('quiz and deck sizes outside the offered ones are kept in range',
      () async {
    final id = await quizzes.generateQuiz(materialId: notes.id, length: 500);
    final q = (await quizzes.getQuiz(id))!;
    expect(q.questions.length, inInclusiveRange(1, 20));
    final made = await cards.generateDeck(materialId: notes.id, count: 1000);
    expect(made, inInclusiveRange(1, 60));
  }, skip: skip, timeout: t4);

  test('a double tap on generate makes two quizzes, not a broken one',
      () async {
    final before = (await quizzes.getQuizzes()).length;
    final ids = await Future.wait([
      quizzes.generateQuiz(materialId: notes.id, length: 3),
      quizzes.generateQuiz(materialId: notes.id, length: 3),
    ]);
    expect(ids.toSet(), hasLength(2));
    final after = await quizzes.getQuizzes();
    expect(after.length, before + 2);
    for (final id in ids) {
      expect((await quizzes.getQuiz(id))!.questions, isNotEmpty);
    }
  }, skip: skip, timeout: t4);

  test('chat in Hindi, with the answer language set to Hindi', () async {
    await profiles.setAnswerLanguage(AnswerLanguage.hindi);
    final t = await chat.createThread();
    final r = await chat.askAi(
        threadId: t.id, question: 'तीसरा नॉर्मल फ़ॉर्म क्या हटाता है?');
    expect(RegExp(r'[ऀ-ॿ]').hasMatch(r.answer), isTrue,
        reason: 'answered in Devanagari: ${r.answer}');
    await profiles.setAnswerLanguage(AnswerLanguage.english);
  }, skip: skip, timeout: t4);

  test('chat with an empty question, or one with no notes behind it',
      () async {
    final t = await chat.createThread();
    await refused(() => chat.askAi(threadId: t.id, question: '   '));
    final r = await chat.askAi(
        threadId: t.id, question: 'Who won the 1983 cricket world cup?');
    expect(r.answer, isNotEmpty, reason: 'answers, without inventing notes');
  }, skip: skip, timeout: t4);

  test('room name: emoji and Gujarati are fine, blank and over-long are not',
      () async {
    final r = await rooms.createRoom(name: 'ડીબીએમએસ 🔥', maxMembers: 3);
    expect(r.name, 'ડીબીએમએસ 🔥');
    await rooms.closeRoom(r.id);
    await refused(() => rooms.createRoom(name: '   '));
    await refused(() => rooms.createRoom(name: 'x' * 300));
    await refused(() => rooms.createRoom(name: 'Big', maxMembers: 50));
  }, skip: skip);

  test('doubt with emoji; the body at the app’s 4000-character cap is '
      'accepted, one more is refused', () async {
    final d = await doubts.post(title: 'BCNF vs 3NF 🤔', body: 'x' * 4000);
    expect(d.title, 'BCNF vs 3NF 🤔');
    await doubts.deleteDoubt(d.id);
    expect(await refused(() => doubts.post(title: 'Too long', body: 'x' * 4001)),
        contains('too long'));
  }, skip: skip);

  test('deleting a file a quiz came from keeps the quiz', () async {
    final id = await quizzes.generateQuiz(materialId: notes.id, length: 3);
    final f = await tempFile('extra.txt', dbmsNotes.codeUnits);
    final extra = await materials.uploadFile(file: f, fileName: 'extra.txt');
    await materials.requestIngest(extra.id);
    final id2 = await quizzes.generateQuiz(materialId: extra.id, length: 3);
    await materials.deleteMaterial(extra);
    expect(await quizzes.getQuiz(id2), isNotNull,
        reason: 'a quiz outlives the file it was written from');
    expect(await quizzes.getQuiz(id), isNotNull);
  }, skip: skip, timeout: t4);

  test('deleting a file shared in a room takes it out of the room', () async {
    final r = await rooms.createRoom(name: 'Share test', maxMembers: 2);
    final f = await tempFile('shared.txt', dbmsNotes.codeUnits);
    final m = await materials.uploadFile(file: f, fileName: 'shared.txt');
    await materials.requestIngest(m.id);
    await rooms.shareMaterial(r.id, m.id);
    expect(await rooms.getSharedMaterials(r.id), hasLength(1));
    await materials.deleteMaterial(m);
    expect(await rooms.getSharedMaterials(r.id), isEmpty);
    await rooms.closeRoom(r.id);
  }, skip: skip, timeout: t4);

  test('deleting a goal keeps its notes and chats, unlinked (0035)',
      () async {
    final g = await goals.createGoal(name: 'Throwaway goal');
    final f = await tempFile('goalnotes.txt', dbmsNotes.codeUnits);
    final m = await materials.uploadFile(
        file: f, fileName: 'goalnotes.txt', goalId: g.id);
    final t = await chat.createThread(goalId: g.id);
    await goals.deleteGoal(g.id);
    final still = await materials.getMaterial(m.id);
    expect(still, isNotNull, reason: 'the notes stay in the library');
    expect(still!.goalId, isNull);
    final threads =
        await s.client.from('chat_threads').select('id').eq('id', t.id);
    expect(threads, hasLength(1), reason: 'the chat stays in the history');
  }, skip: skip);
}
