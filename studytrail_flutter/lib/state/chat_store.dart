import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Chat screen. The answer comes from the `chat` Edge Function, which
/// writes both turns server-side; this store shows optimistic bubbles and then
/// reloads the thread from the table.
///
/// Like other AI chat apps, every launch opens on a new, empty chat; earlier
/// ones are in the history panel. This store lives for the signed-in session,
/// so switching tabs or backgrounding the app keeps the conversation — only a
/// fresh launch (a fresh store) starts over.
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
  bool _opening = false;

  List<ChatThread> _history = const [];
  bool _historyLoading = false;
  bool _historyLoaded = false;
  String? _historyError;

  /// The open chat, or null for a new one nobody has asked anything in yet.
  ChatThread? get thread => _thread;

  /// True while an older chat from the history panel is being loaded.
  bool get opening => _opening;

  /// Past chats, newest first — see [loadHistory].
  List<ChatThread> get history => _history;
  bool get historyLoading => _historyLoading;
  bool get historyLoaded => _historyLoaded;

  /// Kept apart from [error] so a failed history read doesn't cover the chat.
  String? get historyError => _historyError;

  /// Transcript oldest-first, including the optimistic bubbles shown while a
  /// reply is in flight.
  List<ChatMessage> get messages => _messages;

  /// True while waiting on a reply — the composer disables its send button.
  bool get sending => _sending;

  bool get isEmpty => loaded && _messages.isEmpty;

  /// Nothing to fetch: a launch opens on a new chat. The thread row is only
  /// written with the first question ([send]), so opening the tab and leaving
  /// doesn't leave an empty chat in the history.
  Future<void> load() => runLoad(() async {});

  /// Sends a question. Shows the user's message and a pending bubble
  /// immediately, then reconciles against what the server stored.
  Future<void> send(String text) async {
    final body = text.trim();
    if (body.isEmpty || _sending) return;
    var thread = _thread;

    _sending = true;
    _suggestions = const [];
    _messages = [
      ..._messages,
      ChatMessage.localUser(body),
      ChatMessage.pending(),
    ];
    notifyListeners();

    try {
      if (thread == null) {
        // The first question is what makes this a chat worth keeping.
        final goal = await _goals.getActiveGoal();
        thread = await _chat.createThread(goalId: goal?.id);
        _thread = thread;
      }
      // Both turns are written by the `chat` function; the app can't write
      // chat rows itself (0020_hardening.sql).
      final reply = await _chat.askAi(threadId: thread.id, question: body);
      _suggestions = reply.suggestions;
      // Reloading drops the optimistic bubbles and picks up both stored turns
      // along with their citation chips.
      _messages = await _chat.getMessages(thread.id);
      _rememberInHistory(thread, body);
    } catch (e) {
      _messages = _messages
          .where((m) => !m.isPending && !m.id.startsWith('_local_'))
          .toList();
      setError(e);
      // The function saves the question before it calls the model, so a failure
      // partway through can leave it stored. Reload so the student sees their own
      // message where they left it rather than watching it disappear.
      if (thread != null) {
        try {
          _messages = await _chat.getMessages(thread.id);
          if (_messages.isNotEmpty) _rememberInHistory(thread, body);
        } catch (_) {
          // Offline, most likely — the error already set above is the real one.
        }
      }
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Starts a fresh conversation. Nothing is written until its first question.
  void newThread() {
    if (_sending) return;
    _thread = null;
    _messages = const [];
    _suggestions = const [];
    clearError();
    notifyListeners();
  }

  /// Reads the student's past chats for the history panel.
  Future<void> loadHistory() async {
    if (_historyLoading) return;
    _historyLoading = true;
    _historyError = null;
    notifyListeners();
    try {
      _history = await _chat.getHistory();
      _historyLoaded = true;
    } catch (e) {
      _historyError = friendlyError(e);
    } finally {
      _historyLoading = false;
      notifyListeners();
    }
  }

  /// Opens a past chat from the history panel, to read or carry on.
  Future<void> openThread(ChatThread thread) async {
    if (_sending || _thread?.id == thread.id) return;
    _thread = thread;
    _messages = const [];
    _suggestions = const [];
    _opening = true;
    clearError();
    notifyListeners();
    try {
      _messages = await _chat.getMessages(thread.id);
    } catch (e) {
      setError(e);
    } finally {
      _opening = false;
      notifyListeners();
    }
  }

  /// Deletes a past chat. Deleting the open one starts a new chat in its
  /// place. Returns false, with [historyError] set, when it couldn't.
  Future<bool> deleteThread(ChatThread thread) async {
    try {
      await _chat.deleteThread(thread.id);
    } catch (e) {
      _historyError = friendlyError(e);
      notifyListeners();
      return false;
    }
    _history = _history.where((t) => t.id != thread.id).toList();
    if (_thread?.id == thread.id) {
      newThread();
    } else {
      notifyListeners();
    }
    return true;
  }

  /// Puts a chat that just got its first question at the top of the history,
  /// so the panel shows it without reading the list again.
  void _rememberInHistory(ChatThread thread, String question) {
    if (_history.any((t) => t.id == thread.id)) return;
    _history = [
      ChatThread(
        id: thread.id,
        title: thread.title,
        preview: question,
        createdAt: thread.createdAt ?? DateTime.now(),
      ),
      ..._history,
    ];
  }

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
