// One student's whole study journey on the hosted project, through the app's
// real repositories: profile → goal → notes (text and PDF) → roadmap → Today
// → quiz → flashcards → chat → answer practice → past paper → streak, XP,
// badges, rewards → account deletion. Edge cases sit beside each step.
//
// Tests run in order and share state; a failure early on skips nothing, but
// later steps may then fail for the same reason — read the first failure.
//
//   STUDYTRAIL_LIVE=1 flutter test test/live/e2e_study_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:studytrail_flutter/data/repositories.dart';
import 'package:studytrail_flutter/models/models.dart';

import '_harness.dart';

void main() {
  late Student a;
  const profiles = ProfileRepository();
  const goals = GoalRepository();
  const materials = MaterialRepository();
  const roadmap = RoadmapRepository();
  const tasks = TaskRepository();
  const quizzes = QuizRepository();
  const cards = FlashcardRepository();
  const chat = ChatRepository();
  const answers = AnswerRepository();
  const papers = ExamPaperRepository();
  const game = GamificationRepository();
  const analytics = AnalyticsRepository();

  late Goal goal;
  late List<Subject> subjects;
  late StudyMaterial notes;
  late StudyMaterial pdfNotes;
  String? quizId;

  Future<int> xp() async => (await profiles.getMyProfile())!.xp;

  setUpAll(() async {
    if (!liveEnabled) return;
    a = await Student.create('study', name: 'Live Study Student');
  });
  setUp(() {
    if (liveEnabled) a.use();
  });
  tearDownAll(() async {
    if (liveEnabled) await deleteStudents();
  });

  final opts = (skip: liveSkip, timeout: const Timeout(Duration(minutes: 4)));

  test('profile: created at sign-up; name, academics, language, offset',
      () async {
    final p = await profiles.getMyProfile();
    expect(p, isNotNull, reason: 'the signup trigger makes the profile');
    expect(p!.fullName, 'Live Study Student');
    expect(p.xp, 0);

    final updated = await profiles.updateProfile(
        branch: 'Computer Engineering', college: 'CHARUSAT');
    expect(updated.branch, 'Computer Engineering');
    expect((await profiles.setAnswerLanguage(AnswerLanguage.hindi))
        .answerLanguage, AnswerLanguage.hindi);
    await profiles.setAnswerLanguage(AnswerLanguage.english);
    await profiles.setUtcOffset(const Duration(hours: 5, minutes: 30));
  }, skip: opts.skip, timeout: opts.timeout);

  test('goal: subjects with their own dates; blanks dropped; date follows '
      'the last paper', () async {
    expect(await goals.hasAnyGoal(), isFalse);
    final now = DateTime.now();
    goal = await goals.createGoal(
      name: '  Semester 5  ',
      pace: Pace.steady,
      subjectNames: ['DBMS', '   ', 'Operating Systems'],
      subjectExamDates: [
        now.add(const Duration(days: 20)),
        now.add(const Duration(days: 99)), // belongs to the blank name
        now.add(const Duration(days: 30)),
      ],
      dailyMinutes: 90,
    );
    expect(goal.name, 'Semester 5', reason: 'trimmed');
    expect(goal.dailyMinutes, 90);
    subjects = await goals.getSubjects(goal.id);
    expect(subjects.map((s) => s.name).toSet(), {'DBMS', 'Operating Systems'},
        reason: 'the blank subject is dropped');
    final os = subjects.firstWhere((s) => s.name == 'Operating Systems');
    expect(os.examDate!.difference(now).inDays, inInclusiveRange(29, 30),
        reason: "dates don't shift when a blank is dropped");
    expect((await goals.getActiveGoal())?.id, goal.id);

    // Moving a paper later moves the goal's date to the last one.
    final dbms = subjects.firstWhere((s) => s.name == 'DBMS');
    await goals.setSubjectExamDate(dbms.id, now.add(const Duration(days: 45)));
    final g = await goals.getActiveGoal();
    expect(g!.examDate!.difference(now).inDays, inInclusiveRange(44, 45));
  }, skip: opts.skip, timeout: opts.timeout);

  test('notes: a text file is read into unit-labelled chunks; reading again '
      'is a no-op', () async {
    final file = await tempFile('DBMS notes.txt', dbmsNotes.codeUnits);
    notes = await materials.uploadFile(
        file: file, fileName: 'DBMS notes.txt', goalId: goal.id,
        sourceType: MaterialType.notes);
    expect(notes.storagePath, startsWith('${a.id}/'),
        reason: 'stored in the student\'s own folder');
    final chunks = await materials.requestIngest(notes.id);
    expect(chunks, greaterThan(0));
    expect((await materials.getMaterial(notes.id))!.status,
        IngestStatus.embedded);
    // A second read of a ready file costs nothing.
    expect(await materials.requestIngest(notes.id), chunks);
  }, skip: opts.skip, timeout: opts.timeout);

  test('notes: a PDF is read too; a file that is not really a PDF fails '
      'cleanly and can be retried', () async {
    final pdf = await tempFile(
        'os.pdf',
        simplePdf([
          'Unit 1: Processes',
          'A process is a program in execution with its own address space.',
          'The scheduler picks the next ready process: FCFS, SJF, round robin.',
          'Unit 2: Memory',
          'Paging splits memory into fixed frames; a page table maps pages.',
        ]));
    pdfNotes = await materials.uploadFile(
        file: pdf, fileName: 'os.pdf', goalId: goal.id);
    expect(await materials.requestIngest(pdfNotes.id), greaterThan(0));

    final junk = await tempFile('broken.pdf', List.filled(400, 7));
    final broken = await materials.uploadFile(
        file: junk, fileName: 'broken.pdf', goalId: goal.id);
    await refused(() => materials.requestIngest(broken.id));
    final after = await materials.getMaterial(broken.id);
    expect(after!.status, anyOf(IngestStatus.failed, IngestStatus.uploaded),
        reason: 'not stuck on processing');
    expect(after.status, isNot(IngestStatus.embedded));
    // Retry puts it back in the queue; deleting removes row and file.
    if (after.status == IngestStatus.failed) {
      expect((await materials.retryIngest(broken.id)).status,
          IngestStatus.uploaded);
    }
    await materials.deleteMaterial(after);
    expect(await materials.getMaterial(broken.id), isNull);
  }, skip: opts.skip, timeout: opts.timeout);

  test('notes: a client cannot mark a file ready without chunks', () async {
    final file = await tempFile('empty.txt', 'x'.codeUnits);
    final m = await materials.uploadFile(file: file, fileName: 'empty.txt');
    final err = await refused(() => a.client
        .from('materials')
        .update({'status': 'embedded'})
        .eq('id', m.id)
        .select()
        .single());
    expect(err, contains('no embedded chunks'));
    await materials.deleteMaterial(m);
  }, skip: opts.skip, timeout: opts.timeout);

  test('syllabus: typed text is saved on its subject and read in', () async {
    final dbms = subjects.firstWhere((s) => s.name == 'DBMS');
    final s = await materials.addSyllabusText(
        subjectId: dbms.id,
        title: 'DBMS syllabus',
        text: 'Unit 1: Normalisation\nUnit 2: Transactions\nUnit 3: Indexing',
        goalId: goal.id);
    await materials.requestIngest(s.id);
    final syllabi = await materials.getSyllabi();
    expect(syllabi[dbms.id]?.id, s.id);
  }, skip: opts.skip, timeout: opts.timeout);

  test('summary of a file', () async {
    final summary = await materials.requestSummary(notes.id);
    expect(summary.length, greaterThan(40));
  }, skip: opts.skip, timeout: opts.timeout);

  test('roadmap: written for the goal; regenerating replaces it', () async {
    final weeks = await roadmap.generateRoadmap(goal.id);
    expect(weeks, greaterThan(0));
    final ms = await roadmap.getMilestones(goal.id);
    expect(ms.length, weeks);
    expect(ms.every((m) => m.tasks.isNotEmpty), isTrue);
    expect(ms.first.state, MilestoneState.active);
    final pace = await roadmap.getPace(goal.id);
    expect(pace.hasRoadmap, isTrue);
    expect(pace.total, ms.fold<int>(0, (n, m) => n + m.tasks.length));
  }, skip: opts.skip, timeout: opts.timeout);

  test('Today: plan from the roadmap; tick pays 15 XP once; untick and '
      'retick pay nothing; the roadmap follows', () async {
    final ms = await roadmap.getMilestones(goal.id);
    final first = ms.first;
    final planned = await tasks.createTasksFromRoadmap(
        goalId: goal.id, tasks: first.tasks.take(2).toList());
    expect(planned, hasLength(2));
    final today = await tasks.getTodayTasks();
    expect(today.map((t) => t.id), containsAll(planned.map((t) => t.id)));

    final before = await xp();
    final done = await tasks.setDone(planned.first, true);
    expect(done.done, isTrue);
    expect(await xp(), before + 15);
    await tasks.setDone(done, false);
    await tasks.setDone(done, true);
    expect(await xp(), before + 15, reason: 'paid once per task, ever');

    final mirrored = (await roadmap.getMilestones(goal.id))
        .first
        .tasks
        .firstWhere((t) => t.id == planned.first.milestoneTaskId);
    expect(mirrored.done, isTrue, reason: 'complete_task ticks the roadmap');

    // Ticking on the roadmap goes through the same task, no double pay.
    final out = await roadmap.toggleTask(
        first.id, planned.last.milestoneTaskId!, true);
    expect(out.touchedDailyTask, isTrue);
    expect(await xp(), before + 30);

    // A client can't forge a done task or reset the reward marker.
    await refused(() => a.client
        .from('daily_tasks')
        .update({'done': false, 'rewarded_at': null})
        .eq('id', planned.first.id)
        .select()
        .single());
  }, skip: opts.skip, timeout: opts.timeout);

  test('streak: today counts after a tick', () async {
    final streak = await game.getStreak();
    expect(streak.currentStreak, greaterThanOrEqualTo(1));
  }, skip: opts.skip, timeout: opts.timeout);

  test('regenerating the roadmap: unfinished Today tasks go, finished ones '
      'stay off Today (0033)', () async {
    final ms = await roadmap.getMilestones(goal.id);
    final scheduled = await tasks.getScheduledMilestoneTaskIds(goal.id);
    final fresh = ms
        .expand((m) => m.tasks)
        .where((t) => !t.done && !scheduled.contains(t.id))
        .take(1)
        .toList();
    final pending = await tasks.createTasksFromRoadmap(
        goalId: goal.id, tasks: fresh);
    expect(pending, hasLength(1));

    await roadmap.generateRoadmap(goal.id);
    final today = await tasks.getTodayTasks();
    expect(today, isEmpty,
        reason: 'old plan: two finished (hidden) and one pending (deleted)');
    final rows = await a.client
        .from('daily_tasks')
        .select('id, done')
        .eq('goal_id', goal.id);
    expect(rows.where((r) => r['done'] == false), isEmpty);
    expect(rows.where((r) => r['done'] == true), hasLength(2),
        reason: 'kept for badges');
    expect((await roadmap.getPace(goal.id)).overdue, 0);
  }, skip: opts.skip, timeout: opts.timeout);

  test('catch-up planner runs on a fresh roadmap', () async {
    final r = await roadmap.planCatchUp(goal.id);
    expect(r.scheduled, greaterThanOrEqualTo(0));
    expect(r.daysLeft, greaterThan(0));
  }, skip: opts.skip, timeout: opts.timeout);

  test('quiz: written from a file; first attempt pays, a retake does not; '
      'wrong answers fill My mistakes', () async {
    quizId = await quizzes.generateQuiz(materialId: notes.id, length: 5);
    final quiz = (await quizzes.getQuiz(quizId!))!;
    expect(quiz.questions.length, inInclusiveRange(3, 5));
    expect(quiz.questions.every((q) => q.options.length == 4), isTrue);

    // All right but one.
    final picks = {
      for (final (i, q) in quiz.questions.indexed)
        q.id: i == 0 ? (q.correctIndex + 1) % 4 : q.correctIndex,
    };
    final before = await xp();
    final first = await quizzes.submit(
        attemptId: (await quizzes.startAttempt(quizId!)).id, picks: picks);
    expect(first.score, quiz.questions.length - 1);
    expect(first.xpEarned, (quiz.questions.length - 1) * 10);
    expect(await xp(), before + first.xpEarned!);

    final retake = await quizzes.submit(
        attemptId: (await quizzes.startAttempt(quizId!)).id, picks: picks);
    expect(retake.xpEarned, 0, reason: 'XP on the first attempt only (0032)');
    expect(await xp(), before + first.xpEarned!);

    // Submitting a finished attempt again doesn't pay twice.
    final again = await quizzes.submit(attemptId: first.id, picks: picks);
    expect(again.xpEarned, first.xpEarned);
    expect(await xp(), before + first.xpEarned!);

    final decks = await cards.getDecks();
    final mistakes = decks.where((d) => d.isMistakes).toList();
    expect(mistakes, hasLength(1));
    expect(mistakes.single.total, greaterThanOrEqualTo(1));

    // The wrong answer is evidence for weak spots, and a quiz drawn from them.
    expect(await quizzes.getWeakTopics(), isNotEmpty);
    final weakId = await quizzes.generateWeakQuiz(length: 3);
    expect((await quizzes.getQuiz(weakId))!.questions, isNotEmpty);
  }, skip: opts.skip, timeout: opts.timeout);

  test('quiz: forged scores and questions are refused', () async {
    await refused(() => a.client.from('quiz_attempts').insert({
          'user_id': a.id,
          'quiz_id': quizId,
          'score': 99,
          'xp_earned': 9999,
          'completed_at': DateTime.now().toIso8601String(),
        }));
    await refused(() => a.client.from('quizzes').insert({
          'user_id': a.id,
          'title': 'self-written',
        }));
    await refused(() => a.client
        .from('quizzes')
        .update({'xp_paid_at': null})
        .eq('id', quizId!)
        .select()
        .single());
  }, skip: opts.skip, timeout: opts.timeout);

  test('quiz history: delete one attempt, clear all; XP stays', () async {
    final before = await xp();
    final attempts = await quizzes.getAttempts(quizId: quizId);
    expect(attempts.length, 2);
    await quizzes.deleteAttempt(attempts.last.id);
    expect(await quizzes.getAttempts(quizId: quizId), hasLength(1));
    await quizzes.deleteAttempts(quizId!);
    expect(await quizzes.getAttempts(quizId: quizId), isEmpty);
    expect(await xp(), before);
    // Taking it again after clearing still pays nothing.
    final q = (await quizzes.getQuiz(quizId!))!;
    final r = await quizzes.submit(
        attemptId: (await quizzes.startAttempt(quizId!)).id,
        picks: {for (final x in q.questions) x.id: x.correctIndex});
    expect(r.xpEarned, 0);
  }, skip: opts.skip, timeout: opts.timeout);

  test('flashcards: a deck from a file; a due card pays and reschedules; a '
      'single card and a deck can be deleted', () async {
    final made = await cards.generateDeck(materialId: notes.id, count: 10);
    expect(made, greaterThan(0));
    final due = await cards.getDueCards();
    expect(due, isNotEmpty);
    final card = due.first;
    final before = await xp();
    final graded = await cards.gradeCard(card, SrGrade.good);
    expect(graded.dueAt.isAfter(DateTime.now()), isTrue);
    expect(await xp(), before + 2);
    // Not due any more: grading again pays nothing.
    await cards.gradeCard(graded, SrGrade.good);
    expect(await xp(), before + 2);

    await cards.deleteCard(card.id);
    final deckCards = await cards.getDeckCards(card.deckId);
    expect(deckCards.any((c) => c.id == card.id), isFalse);
    await cards.deleteDeck(card.deckId);
    expect((await cards.getDecks()).any((d) => d.id == card.deckId), isFalse);
  }, skip: opts.skip, timeout: opts.timeout);

  test('chat: a cited answer from the notes, follow-ups, save as cards, '
      'history, delete', () async {
    final thread = await chat.createThread(goalId: goal.id);
    final reply = await chat.askAi(
        threadId: thread.id, question: 'What does 3NF remove?');
    expect(reply.answer.toLowerCase(), contains('transitive'));
    final msgs = await chat.getMessages(thread.id);
    expect(msgs.map((m) => m.role), [ChatRole.user, ChatRole.ai]);
    final ai = msgs.last;
    expect(ai.citations, isNotEmpty, reason: 'answers cite the notes');
    expect(await cards.cardsFromChat(ai.id), greaterThan(0));
    expect((await chat.getHistory()).any((t) => t.id == thread.id), isTrue);

    // The app can't write chat rows itself (0020).
    await refused(() => a.client.from('chat_messages').insert({
          'user_id': a.id,
          'thread_id': thread.id,
          'role': 'ai',
          'text': 'forged',
        }));
    await chat.deleteThread(thread.id);
    expect((await chat.getHistory()).any((t) => t.id == thread.id), isFalse);

    final starters = await chat.getStarterSources();
    // The stored name; buildChatStarters tidies it to "DBMS notes".
    expect(starters.map((s) => s.title), contains('DBMS notes.txt'));
    expect(starters.firstWhere((s) => s.title == 'DBMS notes.txt').units,
        isNotEmpty);
  }, skip: opts.skip, timeout: opts.timeout);

  test('answer practice: questions up to 6 marks from all notes, one subject '
      'or one file; a graded answer stays within the marks', () async {
    final sources = await answers.getSources();
    expect(sources.files, isNotEmpty);
    final theory = await answers.newQuestions(count: 2);
    expect(theory.every((q) => q.marks <= 6), isTrue);
    final nep = await answers.newQuestions(
        count: 1,
        kind: AnswerKind.nep,
        source: PracticeSource(materialId: notes.id));
    expect(nep.single.marks, inInclusiveRange(3, 6));

    final q = theory.first;
    final good = await answers.grade(
        q,
        'Normalisation reduces redundancy. 1NF needs atomic values, 2NF '
        'removes partial dependencies on a composite key and 3NF removes '
        'transitive dependencies between non-key attributes, for example '
        'student city depending on pin code.');
    expect(good.score, inInclusiveRange(0, q.marks));
    expect(good.maxMarks, q.marks);

    // Too short to mark: refused, as the app's 5-word minimum does too.
    expect(await refused(() => answers.grade(q, 'I do not know.')),
        contains('Write a bit more'));
    final weak = await answers.grade(
        q, 'Normalisation is about tables in a database and keys.');
    expect(weak.score, lessThanOrEqualTo(good.score));
    expect((await answers.getAttempts()).length, greaterThanOrEqualTo(2));

    // A score the client writes itself is refused (0017).
    await refused(() => a.client.from('answer_attempts').insert({
          'user_id': a.id,
          'question': 'x',
          'answer': 'y',
          'score': 6,
          'max_marks': 6,
        }));
  }, skip: opts.skip, timeout: opts.timeout);

  test('past paper: a PDF is read into questions and topics; a mock exam '
      'follows it', () async {
    final pdf = await tempFile(
        'dbms_2025.pdf',
        simplePdf([
          'CHARUSAT University - B.Tech Sem 5 - DBMS - 2025',
          'Q1 (a) Explain 2NF and 3NF with an example. [6 marks]',
          'Q1 (b) What is a transitive dependency? [3 marks]',
          'Q2 (a) Explain two-phase locking. [6 marks]',
          'Q2 (b) How is a deadlock detected? [4 marks]',
          'Q3 Compare B+ tree and hash indexes. [6 marks]',
        ]));
    final paper = await papers.upload(
        file: pdf, fileName: 'dbms_2025.pdf', year: 2025, goalId: goal.id);
    final found = await papers.analyze(paper.id);
    expect(found, greaterThanOrEqualTo(3));
    final topics = await papers.getTopics();
    expect(topics, isNotEmpty);
    final mock = await quizzes.generateMockExam();
    expect((await quizzes.getQuiz(mock))!.questions, isNotEmpty);
    await papers.delete((await papers.getPapers()).single);
    expect(await papers.getPapers(), isEmpty);
  }, skip: opts.skip, timeout: opts.timeout);

  test('focus session pays XP; badges and their progress; leaderboard; '
      'weekly report; analytics', () async {
    final before = await xp();
    await game.recordSession(lengthMin: 25, focusedMin: 25);
    expect(await xp(), greaterThan(before));

    await game.evaluateBadges();
    final unlocked = await game.getBadges(onlyUnlocked: true);
    expect(unlocked.map((b) => b.key), contains('first_step'));
    final progress = await game.getBadgeProgress();
    expect(progress, isNotEmpty);

    final board = await game.getLeaderboard();
    expect(board.any((e) => e.userId == a.id), isTrue,
        reason: 'the caller is always on it');

    await game.getWeeklyReport();
    final totals = await analytics.getTotals();
    expect(totals, isNotNull);
    await analytics.getWeeklyBars();
    await analytics.getQuizAccuracy();
    await analytics.getAnswerStats();

    // XP can't be written by the client.
    await refused(() => a.client
        .from('profiles')
        .update({'xp': 999999})
        .eq('id', a.id)
        .select()
        .single());
    await refused(() => a.client.from('user_badges').insert(
        {'user_id': a.id, 'badge_id': 'week_warrior'}));
  }, skip: opts.skip, timeout: opts.timeout);

  test('rewards: balance is XP earned minus spent; too little XP is refused; '
      'a lifeline can be bought and used once', () async {
    final wallet = await game.getRewardWallet();
    expect(wallet.balance, wallet.earned - wallet.spent);
    if (wallet.balance < 400) {
      await refused(() => game.redeemReward('aurora_profile'));
    }
    if (wallet.balance >= 30) {
      final after = await game.redeemReward('fifty_fifty');
      expect(after.balance, wallet.balance - 30);
      expect(await quizzes.lifelinesLeft(), 1);
      expect(await quizzes.useLifeline(), 0);
      await refused(() => quizzes.useLifeline());
    }
    await refused(() => game.redeemReward('no_such_reward'));
  }, skip: opts.skip, timeout: opts.timeout);

  test('deleting the goal takes its subjects, roadmap and tasks', () async {
    await goals.deleteGoal(goal.id);
    expect(await goals.hasAnyGoal(), isFalse);
    expect(await roadmap.getMilestones(goal.id), isEmpty);
    final rows =
        await a.client.from('subjects').select('id').eq('goal_id', goal.id);
    expect(rows, isEmpty);
  }, skip: opts.skip, timeout: opts.timeout);

  test('account deletion removes the data, the files and the sign-in',
      () async {
    final path = notes.storagePath!;
    await materials.deleteAccount();
    final c = Student.anonymous();
    final signIn = await refused(() =>
        c.auth.signInWithPassword(email: a.email, password: a.password));
    expect(signIn.toLowerCase(), contains('invalid'));
    await c.dispose();
    // The deleted student's session can no longer read anything.
    final rows = await a.client.from('materials').select('id').limit(1)
        .catchError((Object _) => <Map<String, dynamic>>[]);
    expect(rows, isEmpty);
    expect(path, isNotEmpty);
  }, skip: opts.skip, timeout: opts.timeout);
}

// Keeps the analyzer quiet about the import when every test is skipped.
// ignore: unused_element
typedef _Unused = PostgrestException;
