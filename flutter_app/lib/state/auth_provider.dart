import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../models/models.dart';
import 'providers.dart';
import 'server_provider.dart';

/// Authentication lifecycle (PLAN §3.8, E2). Backed by the real
/// [ApiClient.login]/[ApiClient.me]/[ApiClient.logout] on [DioApiClient].
/// [initialized] flips true once boot-time session restore has resolved
/// (success or failure) — the router redirect waits on it so an unauthenticated
/// user isn't bounced to `/login` before we've had a chance to check the
/// persisted cookie.
class AuthState {
  const AuthState({this.user, this.loading = false, this.error, this.initialized = false});

  final User? user;
  final bool loading;
  final String? error;
  final bool initialized;

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    User? user,
    bool? loading,
    String? error,
    bool? initialized,
    bool clearError = false,
    bool clearUser = false,
  }) =>
      AuthState(
        user: clearUser ? null : (user ?? this.user),
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        initialized: initialized ?? this.initialized,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState());

  final Ref _ref;

  Future<void> login(String username, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _ref.read(apiClientProvider).login(username, password);
      state = AuthState(user: user, initialized: true);
    } catch (e) {
      state = AuthState(error: _message(e), initialized: true);
    }
  }

  /// Attempt to restore an existing session from the persisted cookie jar by
  /// probing `GET /api/auth/me`. Call once at app boot.
  Future<void> restore() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _ref.read(apiClientProvider).me();
      state = AuthState(user: user, initialized: true);
    } catch (_) {
      state = const AuthState(initialized: true);
    }
  }

  Future<void> logout() async {
    try {
      await _ref.read(apiClientProvider).logout();
    } finally {
      // The configured server is kept only while signed in — clear it on
      // logout so the next login starts from the server picker.
      await _ref.read(serverConfigProvider.notifier).clear();
      state = const AuthState(initialized: true);
    }
  }

  /// Boot-time initialization when no server is configured yet: mark the auth
  /// layer initialized (unauthenticated) without a network probe, so the router
  /// shows the login screen immediately instead of hanging on a dead default.
  void markUnauthenticated() => state = const AuthState(initialized: true);

  String _message(Object e) {
    if (e is ApiException) {
      return e.isUnauthorized ? 'Incorrect username or password.' : e.message;
    }
    return 'Could not reach the server. Check your connection.';
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(ref));
