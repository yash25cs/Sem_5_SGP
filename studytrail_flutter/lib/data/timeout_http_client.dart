import 'dart:async';

import 'package:http/http.dart' as http;

/// Wraps every Supabase request in a deadline, so a dead network fails instead
/// of hanging.
///
/// None of the Supabase packages set a timeout, and Dart's own client doesn't
/// either — a request to an unreachable host waits forever. With Wi-Fi switched
/// off that usually surfaces fast as a failed DNS lookup, but two common cases
/// don't: a network that accepts the connection and never answers (hotel or
/// campus captive portals, a phone showing full bars with no working data), and
/// an expired session, where `SupabaseClient` refreshes the token before every
/// query and gotrue retries that refresh on a backoff ladder bounded only by
/// its 30-second auto-refresh tick. Either way the app sat on a spinner.
///
/// The body gets its own idle deadline as well: `send` only completes when the
/// response *headers* arrive, so without it a stalled download would still hang
/// with the headers already in hand.
///
/// It is also the one place every request passes through, so it pins Edge
/// Function calls to [functionsRegion] — the header `functions.invoke` would
/// send if `Supabase.initialize` let the region be set.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient({http.Client? inner, this.functionsRegion = ''})
      : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// Region for `/functions/v1/` calls; empty leaves Supabase to choose.
  final String functionsRegion;

  /// Queries, auth, and anything else that is a small round trip. Nothing here
  /// should take seconds, so waiting longer only prolongs a spinner.
  static const _standard = Duration(seconds: 20);

  /// Uploads, downloads, and the AI functions. A 14 MB PDF on a weak
  /// connection is legitimately slow, and `embed-material` budgets 90 s to read
  /// a PDF plus 40 s to embed it — a shorter cap here would abort work the
  /// server is still doing, which is worse than waiting.
  static const _longRunning = Duration(seconds: 180);

  static Duration budgetFor(Uri url) {
    final path = url.path;
    return path.contains('/functions/v1/') || path.contains('/storage/v1/')
        ? _longRunning
        : _standard;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (functionsRegion.isNotEmpty &&
        request.url.path.contains('/functions/v1/') &&
        !request.headers.containsKey('x-region')) {
      request.headers['x-region'] = functionsRegion;
    }
    final budget = budgetFor(request.url);
    final response = await _inner.send(request).timeout(budget);
    return http.StreamedResponse(
      // Per gap between chunks, not for the whole body: a large file is
      // allowed to take as long as it takes, as long as bytes keep arriving.
      response.stream.timeout(budget),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
