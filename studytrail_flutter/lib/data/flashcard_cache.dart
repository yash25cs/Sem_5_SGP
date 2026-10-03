import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'supabase_client.dart';

/// A grade given while offline, waiting to be sent to `apply_sr_grade`.
class PendingGrade {
  const PendingGrade({required this.cardId, required this.grade});

  final String cardId;
  final SrGrade grade;

  Map<String, dynamic> toJson() => {'card': cardId, 'grade': grade.db};

  static PendingGrade? fromJson(Object? raw) {
    if (raw is! Map || raw['card'] is! String) return null;
    return PendingGrade(
        cardId: raw['card'] as String,
        grade: SrGrade.fromDb(raw['grade'] as String?));
  }
}

/// Decks, upcoming cards and queued grades kept on the phone, so flashcards
/// still work with no signal — the bus, the hostel, the exam hall corridor.
///
/// Keyed by user, so a second account on the same phone never sees the
/// first one's cards or replays their grades. Every read tolerates a missing
/// or unreadable store by returning nothing: the cache is a fallback, never a
/// reason for the screen to fail.
class FlashcardCache {
  const FlashcardCache();

  static String _uid() {
    try {
      return currentUserId ?? 'anon';
    } catch (_) {
      return 'anon';
    }
  }

  static String _key(String what) => 'flashcards_${what}_v1_${_uid()}';

  Future<List<Map<String, dynamic>>> _readList(String what) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(what));
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      return decoded is List
          ? [for (final e in decoded) if (e is Map) Map<String, dynamic>.from(e)]
          : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeList(String what, List<Map<String, dynamic>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(what), jsonEncode(items));
    } catch (_) {
      // Non-fatal: next online load writes it again.
    }
  }

  Future<List<FlashcardDeck>> decks() async =>
      [for (final m in await _readList('decks')) FlashcardDeck.fromMap(m)];

  Future<void> saveDecks(List<FlashcardDeck> decks) =>
      _writeList('decks', [for (final d in decks) d.toCacheMap()]);

  Future<List<Flashcard>> cards() async {
    final out = <Flashcard>[];
    for (final m in await _readList('cards')) {
      try {
        out.add(Flashcard.fromMap(m));
      } catch (_) {
        // One bad row from an older build shouldn't cost the rest.
      }
    }
    return out;
  }

  Future<void> saveCards(List<Flashcard> cards) =>
      _writeList('cards', [for (final c in cards) c.toCacheMap()]);

  Future<List<PendingGrade>> pending() async =>
      [for (final m in await _readList('pending')) ?PendingGrade.fromJson(m)];

  Future<void> savePending(List<PendingGrade> grades) =>
      _writeList('pending', [for (final g in grades) g.toJson()]);
}
