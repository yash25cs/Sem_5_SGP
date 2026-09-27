import 'package:flutter/foundation.dart';

import '../data/supabase_client.dart';

/// Shared bookkeeping for every data-backed store: a one-shot `loading` flag
/// for the first fetch, a `busy` flag for writes, and a human-readable error.
///
/// [AuthStore] predates this and keeps its own copy of the pattern because its
/// lifecycle (a stream subscription driving `status`) is different enough that
/// sharing would obscure both.
abstract class AsyncStore extends ChangeNotifier {
  bool _loading = false;
  bool _busy = false;
  bool _loaded = false;
  bool _disposed = false;
  String? _error;

  /// True during the initial fetch — screens show a skeleton.
  bool get loading => _loading;

  /// True during a write — screens disable the control that triggered it.
  bool get busy => _busy;

  /// True once the first successful load has completed.
  bool get loaded => _loaded;

  String? get error => _error;

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Wraps the initial fetch. Safe to call repeatedly — a second call while
  /// one is in flight is ignored.
  @protected
  Future<void> runLoad(Future<void> Function() action) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      _loaded = true;
    } catch (e) {
      _error = friendlyError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Wraps a write. Returns true on success; on failure sets [error] and
  /// returns false so callers can skip their success path.
  @protected
  Future<bool> runMutation(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e, st) {
      debugPrint('runMutation caught error: $e\n$st');
      _error = friendlyError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Reports a failure from a path that manages its own busy flag (e.g. chat
  /// send, which drives a separate `sending` state).
  @protected
  void setError(Object e) {
    _error = friendlyError(e);
    notifyListeners();
  }

  // A store can outlive an in-flight request (user navigates away mid-fetch);
  // notifying after dispose throws, so swallow it.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
