import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/material_repository.dart';
import '../data/supabase_client.dart';

/// Where the top-level flow should be. `unknown` covers the first frame before
/// Supabase has restored any persisted session.
enum AuthStatus { unknown, signedOut, signedIn }

/// Owns session state and the auth calls the login/signup screens make.
class AuthStore extends ChangeNotifier {
  AuthStore({AuthRepository? repo}) : _repo = repo ?? const AuthRepository() {
    _status = _repo.isSignedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
    _sub = _repo.authStateChanges.listen(_onAuthChange);
  }

  final AuthRepository _repo;
  late final StreamSubscription<AuthState> _sub;

  AuthStatus _status = AuthStatus.unknown;
  bool _busy = false;
  String? _error;

  /// Set right after a successful signUp when the project requires email
  /// confirmation, so the UI can say "check your inbox" instead of hanging.
  bool _awaitingEmailConfirmation = false;

  AuthStatus get status => _status;
  bool get busy => _busy;
  String? get error => _error;
  bool get awaitingEmailConfirmation => _awaitingEmailConfirmation;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  User? get user => _repo.user;

  void _onAuthChange(AuthState state) {
    final signedIn = state.session != null;
    final next = signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
    if (next == _status) return;
    _status = next;
    if (signedIn) _awaitingEmailConfirmation = false;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Runs an auth call with busy/error bookkeeping.
  /// Returns true on success; on failure sets [error] and returns false.
  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      _error = friendlyError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> signIn(String email, String password) =>
      _run(() => _repo.signIn(email: email, password: password));

  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
  }) =>
      _run(() async {
        final res = await _repo.signUp(
          email: email,
          password: password,
          fullName: fullName,
        );
        // No session back means the project has email confirmation on.
        _awaitingEmailConfirmation = res.session == null;
      });

  Future<bool> signInWithGoogle() => _run(() => _repo.signInWithGoogle());

  Future<bool> sendPasswordReset(String email) =>
      _run(() => _repo.sendPasswordReset(email));

  /// Permanently deletes the signed-in user's account and all their data.
  /// On success the local session is cleared and the flow returns to sign-in.
  Future<bool> deleteAccount() => _run(() async {
        await const MaterialRepository().deleteAccount();
        // The auth user was deleted server-side, so the local session is stale.
        await _repo.signOut();
      });

  Future<bool> signOut() => _run(_repo.signOut);

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
