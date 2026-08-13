import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../models/models.dart';
import 'now_playing_provider.dart';
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
  const AuthState({
    this.user,
    this.loading = false,
    this.error,
    this.initialized = false,
  });

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
  }) => AuthState(
    user: clearUser ? null : (user ?? this.user),
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    initialized: initialized ?? this.initialized,
  );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState());

  final Ref _ref;
  int _generation = 0;

  Future<void> login(String username, String password) async {
    final generation = ++_generation;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _ref.read(apiClientProvider).login(username, password);
      if (generation != _generation) return;
      state = AuthState(user: user, initialized: true);
    } catch (e) {
      if (generation != _generation) return;
      state = AuthState(error: _message(e), initialized: true);
    }
  }

  /// Attempt to restore an existing session from the persisted cookie jar by
  /// probing `GET /api/auth/me`. Call once at app boot.
  Future<void> restore() async {
    final generation = ++_generation;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _ref.read(apiClientProvider).me();
      if (generation != _generation) return;
      state = AuthState(user: user, initialized: true);
    } catch (_) {
      if (generation != _generation) return;
      state = const AuthState(initialized: true);
    }
  }

  /// Sign out. Ending the session on the server is best-effort; what actually
  /// signs this device out is [_teardownSession], which runs whether or not the
  /// round trip succeeded.
  Future<void> logout() async {
    final generation = ++_generation;
    state = const AuthState(initialized: true);
    await Future.wait([
      _ref.read(apiClientProvider).logout().catchError((_) {}),
      _teardownSession(),
    ]);
    if (generation == _generation) {
      state = const AuthState(initialized: true);
    }
  }

  /// Release everything that belongs to the signed-in session, in the order it
  /// has to go: the party first (it owns the socket, the LiveKit room, the sync
  /// engine), then local playback, then the per-user state the UI reads, then
  /// the configured server.
  ///
  /// Each step is independent and best-effort. A failure part-way through used
  /// to skip the rest, which is how a "logout" could leave the camera live or
  /// the socket still authenticated as the previous user.
  Future<void> _teardownSession() async {
    final steps = <FutureOr<void> Function()>[
      // Leaving a party deliberately preserves local playback. Signing out is
      // the stronger boundary: the stream credentials belong to this session.
      () => _ref.read(partyProvider.notifier).leave(),
      () => _ref.read(nowPlayingProvider.notifier).close(),
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
    await Future.wait([
      for (final step in steps) Future<void>.sync(step).catchError((_) {}),
    ]);
  }

  /// Boot-time initialization when no server is configured yet: mark the auth
  /// layer initialized (unauthenticated) without a network probe, so the router
  /// shows the login screen immediately instead of hanging on a dead default.
  void markUnauthenticated() {
    _generation++;
    state = const AuthState(initialized: true);
  }

  String _message(Object e) {
    if (e is ApiException) {
      return e.isUnauthorized ? 'Incorrect username or password.' : e.message;
    }
    return 'Could not reach the server. Check your connection.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);

/// Whether the signed-in account is a Jellyfin administrator — the one bit that
/// decides who may put something on the server's disk.
///
/// Acquiring a title (Discover, request, release picker, manual magnet) and the
/// download-client controls are the admin's; everything needed to WATCH is
/// everyone's. The server enforces exactly this (`requireAdmin`, see
/// `app/server/auth.js`) — the UI reads this flag only so a member is never
/// shown a control that would answer 403. It is never the authorisation itself.
///
/// False while signed out, and false until boot-time session restore resolves,
/// so nothing admin-only flashes on screen before we know who is here.
final isAdminProvider = Provider<bool>(
  (ref) => ref.watch(authProvider.select((s) => s.user?.isAdmin ?? false)),
);
