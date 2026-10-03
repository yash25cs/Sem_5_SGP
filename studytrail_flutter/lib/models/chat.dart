import 'enums.dart';

/// A row of `chat_messages`, with citations when the query embeds them.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.threadId,
    this.createdAt,
    this.citations = const [],
    this.isPending = false,
  });

  final String id;
  final String? threadId;
  final ChatRole role;
  final String text;
  final DateTime? createdAt;
  final List<ChatCitation> citations;

  /// True for the optimistic "thinking…" bubble that has no DB row yet.
  final bool isPending;

  bool get isUser => role == ChatRole.user;

  factory ChatMessage.fromMap(Map<String, dynamic> m) {
    final raw = m['chat_citations'];
    final cites = raw is List
        ? raw.cast<Map<String, dynamic>>().map(ChatCitation.fromMap).toList()
        : const <ChatCitation>[];

    return ChatMessage(
      id: m['id'] as String,
      threadId: m['thread_id'] as String?,
      role: ChatRole.fromDb(m['role'] as String?),
      text: (m['text'] as String?) ?? '',
      createdAt: m['created_at'] == null
          ? null
          : DateTime.parse(m['created_at'] as String),
      citations: cites,
    );
  }

  /// Local-only placeholder shown while the Edge Function is in flight.
  factory ChatMessage.pending() => const ChatMessage(
        id: '_pending',
        role: ChatRole.ai,
        text: '',
        isPending: true,
      );

  /// Local-only optimistic echo of what the user just typed.
  factory ChatMessage.localUser(String text) => ChatMessage(
        id: '_local_${DateTime.now().microsecondsSinceEpoch}',
        role: ChatRole.user,
        text: text,
      );
}

/// A row of `chat_citations` — the "Unit 3" chips under an AI answer.
class ChatCitation {
  const ChatCitation({required this.id, this.chunkId, this.unitLabel});

  final String id;
  final String? chunkId;
  final String? unitLabel;

  String get label => unitLabel ?? 'Source';

  factory ChatCitation.fromMap(Map<String, dynamic> m) => ChatCitation(
        id: m['id'] as String,
        chunkId: m['chunk_id'] as String?,
        unitLabel: m['unit_label'] as String?,
      );
}

/// A row of `chat_threads`.
class ChatThread {
  const ChatThread({required this.id, this.title, this.preview, this.createdAt});

  final String id;
  final String? title;

  /// The chat's first question — what the history panel lists it by, since
  /// nothing writes [title].
  final String? preview;
  final DateTime? createdAt;

  /// The name shown in the history panel.
  String get displayTitle {
    for (final name in [title, preview]) {
      final clean = name?.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (clean != null && clean.isNotEmpty) return clean;
    }
    return 'New chat';
  }

  factory ChatThread.fromMap(Map<String, dynamic> m) {
    final first = m['first'];
    return ChatThread(
      id: m['id'] as String,
      title: m['title'] as String?,
      preview: first is List && first.isNotEmpty && first.first is Map
          ? (first.first as Map)['text'] as String?
          : null,
      createdAt: m['created_at'] == null
          ? null
          : DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }
}
