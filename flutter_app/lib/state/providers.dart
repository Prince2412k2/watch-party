import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/mock_api_client.dart';
import '../net/socket_client.dart';

/// Core dependency-injection seams (PLAN §3.8). Phase 0 wires MOCK
/// implementations so the app boots and every epic has something to build
/// against. Epics swap in the real impls by overriding these providers at the
/// [ProviderScope] root (E2 → DioApiClient, E5 → IoSocketClient, …).

/// The API client. Overridden with a persistent [DioApiClient] once auth (E2)
/// is wired; defaults to an in-memory mock so the app runs with no backend.
final apiClientProvider = Provider<ApiClient>((ref) => MockApiClient());

/// The socket.io client for sync/chat. Mock by default.
final socketClientProvider =
    Provider<SocketClient>((ref) => MockSocketClient());
