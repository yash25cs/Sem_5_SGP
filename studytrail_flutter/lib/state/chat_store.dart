import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Chat screen. The answer comes from the `chat` Edge Function, which
/// writes both turns server-side; this store shows optimistic bubbles and then
/// reloads the thread from the table.
class ChatStore extends AsyncStore {
  ChatStore({
    ChatRepository? chat,
    GoalRepository? goals,
    FlashcardRepository? cards,
  })  : _chat = chat ?? const ChatRepository(),
        _goals = goals ?? const GoalRepository(),
        _cards = cards ?? const FlashcardRepository();

  final ChatRepository _chat;
  final GoalRepository _goals;
  final FlashcardRepository _cards;

  /// Follow-up questions offered after the latest answer. Cleared on the next
  /// send and on a new thread, so they never describe an older answer.
  List<String> _suggestions = const [];
  List<String> get suggestions => _suggestions;

  /// Answers currently being turned into cards, and those already saved this
  /// session — the button shows a spinner, then a tick, and can't double-save.
  final Set<String> _cardsPending = {};
  final Set<String> _cardsSaved = {};
  bool cardsPending(String messageId) => _cardsPending.contains(messageId);
  bool cardsSaved(String messageId) => _cardsSaved.contains(messageId);

  ChatThread? _thread;
  List<ChatMessage> _messages = const [];
  bool _sending = false;

  ChatThread? get thread => _thread;

  /// Transcript oldest-first, including the optimistic bubbles shown while a
  /// reply is in flight.
  List<ChatMessage> get messages => _messages;

  /// True while waiting on a reply — the composer disables its send button.
  bool get sending => _sending;

  bool get isEmpty => loaded && _messages.isEmpty;

  Future<void> load() => runLoad(() async {
        final goal = await _goals.getActiveGoal();
        final thread = await _chat.getOrCreateThread(goalId: goal?.id);
        _thread = thread;
        _messages = await _chat.getMessages(thread.id);
      });

  /// Sends a question. Shows the user's message and a pending bubble
  /// immediately, then reconciles against what the server stored.
  Future<void> send(String text) async {
    final body = text.trim();
    final thread = _thread;
    if (body.isEmpty || thread == null || _sending) return;

    _sending = true;
    _suggestions = const [];
    _messages = [
      ..._messages,
      ChatMessage.localUser(body),
      ChatMessage.pending(),
    ];
    notifyListeners();

    try {
      // Both turns are written by the `chat` function; the app can't write
      // chat rows itself (0020_hardening.sql).
      final reply = await _chat.askAi(threadId: thread.id, question: body);
      _suggestions = reply.suggestions;
      // Reloading drops the optimistic bubbles and picks up both stored turns
      // along with their citation chips.
      _messages = await _chat.getMessages(thread.id);
    } catch (e) {
      _messages = _messages
          .where((m) => !m.isPending && !m.id.startsWith('_local_'))
          .toList();
      setError(e);
      // The function saves the question before it calls the model, so a failure
      // partway through can leave it stored. Reload so the student sees their own
      // message where they left it rather than watching it disappear.
      try {
        _messages = await _chat.getMessages(thread.id);
      } catch (_) {
        // Offline, most likely — the error already set above is the real one.
      }
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Starts a fresh conversation.
  Future<bool> newThread() => runMutation(() async {
        final goal = await _goals.getActiveGoal();
        _thread = await _chat.createThread(goalId: goal?.id);
        _messages = const [];
        _suggestions = const [];
      });

  /// Turns one answer into flashcards. Returns how many were saved, or null
  /// on failure with [error] set.
  Future<int?> makeCards(String messageId) async {
    if (_cardsPending.contains(messageId) || _cardsSaved.contains(messageId)) {
      return null;
    }
    _cardsPending.add(messageId);
    notifyListeners();
    try {
      final saved = await _cards.cardsFromChat(messageId);
      _cardsSaved.add(messageId);
      return saved;
    } catch (e) {
      setError(e);
      return null;
    } finally {
      _cardsPending.remove(messageId);
      notifyListeners();
    }
  }
}
