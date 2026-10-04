/// Build-time configuration. Values come from `--dart-define` so keys never
/// live in the repo or get bundled as readable assets.
///
/// ```
/// flutter run -d <device> \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
///
/// The anon / publishable key is safe on the client — Postgres RLS is what
/// protects the data. The service_role key must never appear here.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');

  /// Legacy JWT anon key (`eyJ...`) on older projects.
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Newer projects issue `sb_publishable_...` instead. Either is accepted.
  static const String _publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static String get apiKey =>
      _publishableKey.isNotEmpty ? _publishableKey : _anonKey;

  /// Deep link registered in Supabase Auth → URL Configuration, and matched by
  /// the intent-filter in AndroidManifest.xml.
  static const String oauthRedirect =
      'in.charusat.studytrail://login-callback';

  /// Where Edge Functions run. This project's database is in ap-southeast-2
  /// (Sydney). Left alone, a function runs near the caller — Mumbai for a
  /// student in India — and every query it makes crosses to Sydney and back.
  /// Pinned next to the database, a call measured 0.77 s instead of 1.22 s
  /// (2026-10-04). Override with `--dart-define=SUPABASE_FUNCTIONS_REGION=…`
  /// for a project elsewhere; an empty value means "nearest the caller".
  static const String functionsRegion = String.fromEnvironment(
      'SUPABASE_FUNCTIONS_REGION',
      defaultValue: 'ap-southeast-2');

  /// Private Storage bucket holding uploaded syllabi/notes under `/{uid}/...`.
  static const String materialsBucket = 'materials';

  static bool get isConfigured => url.isNotEmpty && apiKey.isNotEmpty;

  /// Human-readable reason shown on the config error screen.
  static String get missingMessage {
    final missing = <String>[
      if (url.isEmpty) 'SUPABASE_URL',
      if (apiKey.isEmpty) 'SUPABASE_ANON_KEY',
    ];
    return 'Missing ${missing.join(' and ')}. '
        'Pass them with --dart-define when running the app.';
  }
}
