/// A question the chat offers before the first message: a short [label] for
/// the chip above the input, and the full [prompt] that is sent (and shown on
/// the empty chat's cards).
class ChatStarter {
  const ChatStarter({required this.label, required this.prompt, this.kind});

  final String label;
  final String prompt;

  /// 'explain' | 'summary' | 'exam' | 'weak' | 'compare' — picks the icon.
  final String? kind;
}

/// One ready material and the unit headings read from it.
class StarterSource {
  const StarterSource({required this.title, this.units = const []});

  final String title;
  final List<String> units;
}
