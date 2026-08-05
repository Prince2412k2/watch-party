import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../models/models.dart';
import 'party_provider.dart';
import 'profile_provider.dart';
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

  /// Sign out. Ending the session on the server is best-effort; what actually
  /// signs this device out is [_teardownSession], which runs whether or not the
  /// round trip succeeded.
  Future<void> logout() async {
    try {
      await _ref.read(apiClientProvider).logout();
    } catch (_) {
      // A dropped connection or an HTTP 500 must not strand the user in a
      // half-signed-out app — and it must not surface as an unhandled error
      // from the sign-out button either. `ApiClient.logout` has already
      // dropped the local cookies on its own way out.
    } finally {
      await _teardownSession();
    }
  }

  /// Release everything that belongs to the signed-in session, in the order it
  /// has to go: the party first (it owns the socket, the LiveKit room, the sync
  /// engine and the shared player), then the per-user state the UI reads, then
  /// the configured server.
  ///
  /// Each step is independent and best-effort. A failure part-way through used
  /// to skip the rest, which is how a "logout" could leave the camera live or
  /// the socket still authenticated as the previous user.
  Future<void> _teardownSession() async {
    final steps = <FutureOr<void> Function()>[
      // Leaves the party and, with it, disconnects the socket and the LiveKit
      // room, detaches the sync engine, stops playback and clears chat.
      () => _ref.read(partyProvider.notifier).leave(),
      () => _ref.read(profileProvider.notifier).clear(),
      // Avatar widgets cache the SVG they drew, keyed by account id — bump the
      // revision so the next account can't be shown wearing this one's face.
      () {
        _ref.read(avatarRevisionProvider.notifier).state++;
      },
      // The configured server is kept only while signed in — clear it on
      // logout so the next login starts from the server picker.
      () => _ref.read(serverConfigProvider.notifier).clear(),
    ];
    for (final step in steps) {
      try {
        await step();
      } catch (_) {
        // Best-effort: the remaining steps still have to run.
      }
    }
    state = const AuthState(initialized: true);
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
