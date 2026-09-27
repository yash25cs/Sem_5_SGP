import 'package:supabase_flutter/supabase_flutter.dart';

/// Shortcut to the initialised Supabase client.
///
/// Valid only after `Supabase.initialize` has completed in `main()`.
SupabaseClient get db => Supabase.instance.client;

/// The signed-in user's id, or null when signed out.
String? get currentUserId => db.auth.currentUser?.id;

/// Same, but throws instead of returning null — for repository writes that
/// have no meaning without a session.
String get requireUserId {
  final id = currentUserId;
  if (id == null) {
    throw StateError('No signed-in user. This call requires authentication.');
  }
  return id;
}

/// True when a failure is transport-level — DNS, no route, TLS, timeout —
/// rather than something the server actually answered.
///
/// This has to be consulted *before* the type checks in [friendlyError].
/// gotrue wraps `ClientException`/`SocketException` in
/// `AuthRetryableFetchException`, which extends `AuthException` and carries the
/// raw `error.toString()` as its message. So the `AuthException` branch would
/// otherwise win and hand a student
/// "ClientException with SocketException: Failed host lookup: … errno = 7".
bool isNetworkError(Object error) {
  // AuthRetryableFetchException doubles as gotrue's 5xx wrapper, and those
  // always carry a statusCode. Transport failures never do.
  if (error is AuthRetryableFetchException && error.statusCode == null) {
    return true;
  }
  const signatures = <String>[
    'SocketException',
    'Failed host lookup',
    'No address associated with hostname',
    'ClientException',
    'HandshakeException',
    'TimeoutException',
    'Connection refused',
    'Connection reset',
    'Connection closed',
    'Network is unreachable',
  ];
  final text = error.toString();
  return signatures.any(text.contains);
}

/// Turns Supabase/Postgres errors into something worth showing a student.
///
/// Postgres error codes we care about:
/// `23505` unique violation, `23503` FK violation, `42501` RLS denial.
String friendlyError(Object error) {
  // A String here is a message this app wrote for the student itself — a limit
  // it enforces, say — so there is nothing to translate.
  if (error is String) return error;

  if (isNetworkError(error)) {
    return "Can't reach StudyTrail. Check your Wi-Fi or mobile data, "
        'then try again.';
  }

  if (error is AuthException) {
    // Reached only for 5xx, since transport failures were handled above.
    // The message here is the raw response body — often an HTML error page.
    if (error is AuthRetryableFetchException) {
      return 'The server is having trouble right now. Try again in a moment.';
    }

    final m = error.message.toLowerCase();
    if (m.contains('invalid login')) {
      return 'Wrong email or password.';
    }
    if (m.contains('already registered') || m.contains('already been')) {
      return 'That email already has an account. Try signing in.';
    }
    if (m.contains('email not confirmed')) {
      return 'Check your inbox and confirm your email first.';
    }
    if (m.contains('password')) return error.message;
    return error.message;
  }

  if (error is PostgrestException) {
    switch (error.code) {
      case '23505':
        return 'That already exists.';
      case '23503':
        return 'Something it depends on is missing. Try reloading.';
      case '42501':
        return 'You do not have access to that.';
      case 'PGRST116':
        return 'Not found.';
      // PostgREST could not find the function or table the app asked for. That
      // is never a data problem — it means the project is running an older set
      // of migrations than this build, so say the one thing that fixes it
      // instead of surfacing "in the schema cache" to a student.
      case 'PGRST202':
      case 'PGRST205':
        return 'This build needs a newer database. Apply '
            'supabase/all_migrations.sql in the Supabase SQL editor.';
    }
    return error.message;
  }

  if (error is StorageException) return error.message;

  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'The AI service is unavailable right now. Try again shortly.';
  }

  // Unexpected: log the real thing for the dashboard, tell the student
  // something they can act on.
  return 'Something went wrong. Please try again.';
}
