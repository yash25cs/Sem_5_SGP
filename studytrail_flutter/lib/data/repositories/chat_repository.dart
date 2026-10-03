import '../../models/models.dart';
import '../supabase_client.dart';

/// Chat threads and messages.
///
/// Reads and writes rows, plus one call into the `chat` Edge Function. That
/// function writes *both* turns — the question and the answer — so on the happy
/// path [askAi] is the only write, and the caller reloads the thread afterwards.
class ChatRepository {
  const ChatRepository();

  Future<List<ChatThread>> getThreads({int limit = 20}) async {
    final rows = await db
        .from('chat_threads')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(ChatThread.fromMap).toList();
  }

  /// Most recent thread, or a fresh one — the chat screen opens straight into
  /// a conversation rather than a thread list.
  Future<ChatThread> getOrCreateThread({String? goalId}) async {
    final existing = await db
        .from('chat_threads')
        .select()
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) return ChatThread.fromMap(existing);
    return createThread(goalId: goalId);
  }

  Future<ChatThread> createThread({String? title, String? goalId}) async {
    final row = await db
        .from('chat_threads')
        .insert({
          'user_id': requireUserId,
          'title': ?title,
          'goal_id': ?goalId,
        })
        .select()
        .single();
    return ChatThread.fromMap(row);
  }

  /// Full transcript, oldest first, with citation chips embedded.
  ///
  /// `ascending: true` is not decoration: postgrest-dart's `order` defaults to
  /// **descending**, the opposite of PostgREST's own default. Leaving it off
  /// rendered every conversation upside down — each answer above the question
  /// that prompted it.
  Future<List<ChatMessage>> getMessages(String threadId) async {
    final rows = await db
        .from('chat_messages')
        .select('*, chat_citations(*)')
        .eq('thread_id', threadId)
        .order('created_at', ascending: true);
    return rows.map(ChatMessage.fromMap).toList();
  }

  /// Asks the `chat` Edge Function for a grounded answer.
  ///
  /// Returns the answer text and up to three suggested follow-up questions.
  /// Both rows are already in `chat_messages` by the time this resolves, so the
  /// caller reloads rather than trusting this string — that's also what picks
  /// up the citation chips. The suggestions aren't stored anywhere; they're for
  /// the composer right now.
  ///
  /// [subjectId] narrows retrieval to one subject's materials; null searches
  /// everything the student has uploaded.
  Future<({String answer, List<String> suggestions})> askAi({
    required String threadId,
    required String question,
    String? subjectId,
  }) async {
    final res = await db.functions.invoke('chat', body: {
      'threadId': threadId,
      'question': question,
      'subjectId': ?subjectId,
    });
    final data = res.data;
    if (data is! Map) return (answer: '', suggestions: const <String>[]);
    return (
      answer: data['answer'] is String ? data['answer'] as String : '',
      suggestions: [
        for (final s in (data['suggestions'] as List? ?? const []))
          if (s is String && s.trim().isNotEmpty) s.trim(),
      ],
    );
  }

  Future<void> deleteThread(String threadId) =>
      db.from('chat_threads').delete().eq('id', threadId);
}
