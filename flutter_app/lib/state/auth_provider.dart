import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'providers.dart';

/// Authentication lifecycle (PLAN §3.8). Phase 0 ships a working notifier over
/// the (mock) [apiClientProvider]; E2 replaces the client with [DioApiClient]
/// and adds session persistence + auto-login. The public surface is frozen.
class AuthState {
  const AuthState({this.user, this.loading = false, this.error});

  final User? user;
  final bool loading;
  final String? error;

  bool get isAuthenticated => user != null;

  AuthState copyWith({User? user, bool? loading, String? error, bool clearError = false, bool clearUser = false}) =>
      AuthState(
        user: clearUser ? null : (user ?? this.user),
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState());

  final Ref _ref;

  Future<void> login(String username, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _ref.read(apiClientProvider).login(username, password);
      state = AuthState(user: user);
    } catch (e) {
      state = AuthState(error: e.toString());
    }
  }

  /// Attempt to restore an existing session (auto-login). E2 wires the real
  /// cookie-backed check.
  Future<void> restore() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _ref.read(apiClientProvider).me();
      state = AuthState(user: user);
    } catch (_) {
      state = const AuthState();
    }
  }

  Future<void> logout() async {
    try {
      await _ref.read(apiClientProvider).logout();
    } finally {
      state = const AuthState();
    }
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(ref));
