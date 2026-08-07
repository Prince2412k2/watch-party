// Player interaction core — the parts of the analog player model that must
// behave identically in Flutter and React.
//
// Ported verbatim from app/client/src/analog/playerCore.ts and driven by the
// same cases in app/shared/design/interaction.json.
//
// Pure: no widgets, no timers. Callers own the clock and feed `atMs` / `nowMs`
// in, which is also what makes the timing rules ("four seconds", "three
// seconds") testable without waiting in real time.

import '../ui/analog_tokens.dart';

// ── chat message toasts ─────────────────────────────────────────────────────
//
// "Up to three messages stack at once. Additional older messages collapse into
// a count rather than extending across the player." (player-interface-reference)
//
// Toasts exist only while the drawer is closed; opening chat dismisses them
// because the messages are then visible in full.

class ToastMessage {
  const ToastMessage({
    required this.id,
    required this.sender,
    required this.preview,
    required this.receivedAtMs,
  });

  final String id;
  final String sender;
  final String preview;
  final int receivedAtMs;
}

class ToastQueueState {
  const ToastQueueState({this.queue = const [], this.chatOpen = false});

  /// Oldest first. Everything still inside its lifetime.
  final List<ToastMessage> queue;
  final bool chatOpen;
}

class ToastView {
  const ToastView({required this.toasts, required this.collapsedCount});

  /// At most [AnalogTiming.toastMaxStack], newest last.
  final List<ToastMessage> toasts;

  /// Live messages beyond the visible stack, shown as a count.
  final int collapsedCount;
}

/// Record an incoming chat message.
///
/// While the drawer is open nothing is queued at all — the message is already
/// on screen, and queueing it would make it toast the moment chat closes.
ToastQueueState pushToast(ToastQueueState state, ToastMessage message) {
  if (state.chatOpen) return state;
  if (state.queue.any((existing) => existing.id == message.id)) return state;
  return ToastQueueState(
    queue: [...state.queue, message],
    chatOpen: state.chatOpen,
  );
}

/// Drop everything past its lifetime. Each toast expires on its own clock.
ToastQueueState expireToasts(ToastQueueState state, int nowMs) {
  final lifetime = AnalogTiming.toastLifetimeMs.inMilliseconds;
  final queue = state.queue
      .where((message) => nowMs - message.receivedAtMs < lifetime)
      .toList(growable: false);
  if (queue.length == state.queue.length) return state;
  return ToastQueueState(queue: queue, chatOpen: state.chatOpen);
}

/// Opening chat dismisses visible toasts; closing it does not resurrect them.
ToastQueueState setChatOpen(ToastQueueState state, bool chatOpen) {
  if (chatOpen == state.chatOpen) return state;
  return ToastQueueState(
    queue: chatOpen ? const [] : state.queue,
    chatOpen: chatOpen,
  );
}

ToastView toastView(ToastQueueState state) {
  if (state.chatOpen) {
    return const ToastView(toasts: [], collapsedCount: 0);
  }
  const max = AnalogTiming.toastMaxStack;
  if (state.queue.length <= max) {
    return ToastView(toasts: List.of(state.queue), collapsedCount: 0);
  }
  return ToastView(
    toasts: state.queue.sublist(state.queue.length - max),
    collapsedCount: state.queue.length - max,
  );
}

// ── control auto-hide ───────────────────────────────────────────────────────
//
// "During playback, controls hide after three seconds without relevant input."
// "Auto-hidden controls must return on pointer movement, tap, focus movement,
// or a relevant media key without changing playback state."
//
// The hold set is what keeps the chrome up while the user is mid-interaction:
// scrubbing, a settings stack open, focus inside the chat composer. Without it
// the menu you just opened vanishes under your cursor.

enum PlayerInputKind { pointer, tap, focus, key, mediaKey, scroll }

class AutoHideState {
  const AutoHideState({
    required this.visible,
    required this.lastInputAtMs,
    required this.holds,
    required this.playing,
  });

  AutoHideState.initial({int atMs = 0, this.playing = true})
      : visible = true,
        lastInputAtMs = atMs,
        holds = const [];

  final bool visible;
  final int lastInputAtMs;

  /// Reasons the chrome is pinned open. Non-empty means never hide.
  final List<String> holds;

  /// Chrome stays up whenever playback is not running.
  final bool playing;

  AutoHideState copyWith({
    bool? visible,
    int? lastInputAtMs,
    List<String>? holds,
    bool? playing,
  }) =>
      AutoHideState(
        visible: visible ?? this.visible,
        lastInputAtMs: lastInputAtMs ?? this.lastInputAtMs,
        holds: holds ?? this.holds,
        playing: playing ?? this.playing,
      );
}

/// Any relevant input reveals the chrome and restarts the timer.
AutoHideState noteInput(AutoHideState state, PlayerInputKind kind, int atMs) =>
    state.copyWith(visible: true, lastInputAtMs: atMs);

AutoHideState holdControls(AutoHideState state, String reason) {
  if (state.holds.contains(reason)) return state;
  return state.copyWith(visible: true, holds: [...state.holds, reason]);
}

/// Release a hold. The auto-hide timer restarts from [atMs] rather than from
/// whenever the hold was taken, so closing a menu gives the full three seconds
/// instead of hiding instantly.
AutoHideState releaseControls(AutoHideState state, String reason, int atMs) {
  if (!state.holds.contains(reason)) return state;
  return state.copyWith(
    holds: state.holds.where((held) => held != reason).toList(growable: false),
    lastInputAtMs: atMs,
  );
}

AutoHideState setPlaying(AutoHideState state, bool playing, int atMs) {
  if (playing == state.playing) return state;
  // Pausing reveals the chrome and keeps it up; resuming restarts the timer.
  return state.copyWith(playing: playing, visible: true, lastInputAtMs: atMs);
}

/// Advance the clock. Returns the state with `visible` resolved for [nowMs].
AutoHideState tickAutoHide(AutoHideState state, int nowMs) {
  if (state.holds.isNotEmpty || !state.playing) {
    return state.visible ? state : state.copyWith(visible: true);
  }
  final elapsed = nowMs - state.lastInputAtMs;
  final visible = elapsed < AnalogTiming.chromeAutoHideMs.inMilliseconds;
  return visible == state.visible ? state : state.copyWith(visible: visible);
}

// ── chat shortcut guard ─────────────────────────────────────────────────────
//
// "`Ctrl+C` toggles the same surface. The shortcut must not fire while focus is
// inside an editable text field and must not override the platform copy
// command when text is selected."
//
// Both conditions are real: binding Ctrl+C naively breaks copy, which users
// notice immediately and blame on the app.

class ChatShortcutContext {
  const ChatShortcutContext({
    required this.ctrlOrMeta,
    required this.key,
    required this.editable,
    required this.hasSelection,
  });

  final bool ctrlOrMeta;
  final String key;

  /// Focus is in a text field.
  final bool editable;

  /// A non-empty selection exists.
  final bool hasSelection;
}

bool shouldToggleChat(ChatShortcutContext context) {
  if (!context.ctrlOrMeta) return false;
  if (context.key.toLowerCase() != 'c') return false;
  if (context.editable) return false;
  if (context.hasSelection) return false;
  return true;
}
