/// Shared-browser state, kept beside [PartyState] rather than inside it.
///
/// Two reasons it lives here: [PartyState] is a freezed model (adding a field
/// means a codegen pass for a feature that is otherwise pure Dart), and this
/// state changes on its own cadence — a stream coming up, a control handover —
/// so a separate notifier keeps those rebuilds off every party widget.
///
/// `stage == 'browser'` on [PartyState] already says *which* activity is
/// current; this says everything else about it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shared_browser.dart';

class SharedBrowserView {
  const SharedBrowserView({this.available = false, this.browser});

  /// Whether this deployment has the feature at all. Server-authoritative: the
  /// app must never decide this from its own build configuration, or a stale
  /// install would offer a browser the server does not have.
  ///
  /// Part of the state rather than a field on the notifier so a widget that
  /// watches this provider actually rebuilds when it changes.
  final bool available;

  /// Null unless this party currently holds the browser.
  final SharedBrowserState? browser;
}

class SharedBrowserNotifier extends StateNotifier<SharedBrowserView> {
  SharedBrowserNotifier() : super(const SharedBrowserView());

  void apply({required bool available, SharedBrowserState? browser}) {
    state = SharedBrowserView(available: available, browser: browser);
  }

  void clear() => state = const SharedBrowserView();
}

final sharedBrowserProvider =
    StateNotifierProvider<SharedBrowserNotifier, SharedBrowserView>(
      (ref) => SharedBrowserNotifier(),
    );
