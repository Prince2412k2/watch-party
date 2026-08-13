import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../player/player_controller.dart';
import 'auth_provider.dart';
import 'now_playing_provider.dart';
import 'player_provider.dart';
import 'providers.dart';

/// Where the queue of unsent reports lives between launches.
const String kWatchHistoryQueueKey = 'playback.pendingReports';

/// How often a playing title reports its position.
///
/// Ten seconds is what the official clients use, and the number is a trade
/// between the write rate and how much progress a hard kill can lose. Pause,
/// seek, backgrounding and close all report immediately regardless, so this
/// only bounds the loss when the process dies without warning.
const Duration kWatchHistoryInterval = Duration(seconds: 10);

/// The most reports we hold for a device that has been offline. Older ones are
/// dropped first: a stale position for a title watched last week is worth less
/// than the one from an hour ago, and an unbounded queue is a disk leak with a
/// slow fuse.
const int kWatchHistoryQueueLimit = 200;

/// Reports playback to the server so a watch history exists at all.
///
/// Everything the app shows about what you have watched — Continue Watching,
/// Next Up, the Resume button, the progress hairline under a poster — is
/// Jellyfin's `UserData`, and Jellyfin only fills that in for playback it was
/// told about. Nothing told it before this, which is why all four surfaces were
/// built, wired, and permanently empty.
///
/// The reporter is deliberately dumb about *meaning*: it does not decide what
/// counts as watched, or where a resume point should be. It says where the
/// viewer is; Jellyfin applies its own thresholds. Two places must therefore
/// not be second-guessed here — the played flag (Jellyfin sets it when a
/// session stops past its MaxResumePct, 90% by default) and the resume position
/// (ignored below MinResumePct or under MinResumeDurationSeconds). Reimplementing
/// those client-side would make this app disagree with every other Jellyfin
/// client pointed at the same server.
class WatchHistoryReporter {
  WatchHistoryReporter(this._ref);

  final Ref _ref;

  Timer? _ticker;
  StreamSubscription<bool>? _playing;
  StreamSubscription<bool>? _completed;

  /// The session in flight, or null when nothing is open. Holds the identity of
  /// what is playing, NOT its position — the position is read from the player
  /// at the moment of each report, so a report is never stale.
  PlaybackReport? _session;

  /// The last position actually sent, so a stop that follows a tick with no
  /// movement between them does not spend a request saying the same thing.
  int? _lastSentTicks;

  bool _disposed = false;

  PlayerController get _player => _ref.read(playerControllerProvider);

  bool get _signedIn =>
      _ref.read(authProvider.select((s) => s.isAuthenticated));

  /// Begin watching [now]'s title. Safe to call repeatedly for the same
  /// revision — a rebuild is not a new play.
  Future<void> open(NowPlaying now) async {
    if (!now.isOpen || now.itemId == null) {
      await close();
      return;
    }
    if (_session?.itemId == now.itemId) return;

    // Switching straight from one title to another: the outgoing one still has
    // to be stopped, or it keeps whatever position it had when we looked away.
    await close();

    _session = PlaybackReport(
      itemId: now.itemId!,
      positionTicks: 0,
      mediaSourceId: now.mediaSourceId,
      playSessionId: PlaybackReport.newSessionId(),
    );
    _lastSentTicks = null;
    await _send(PlaybackReportKind.started, _session!);
    _listen();
    _startTicker();
  }

  void _listen() {
    _playing?.cancel();
    _completed?.cancel();
    // A pause is worth a report on its own: it is the most common way a viewer
    // stops for the night, and the position at that moment is the one they will
    // come back to.
    _playing = _player.playing.listen((playing) {
      if (playing) {
        _startTicker();
      } else {
        _ticker?.cancel();
      }
      unawaited(_report(isPaused: !playing));
    });
    // Reaching the end is the whole point of the played flag. Reported as a
    // STOP at the final position, which is what tips Jellyfin past its
    // watched threshold.
    _completed = _player.completed.listen((done) {
      if (done) unawaited(close());
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(kWatchHistoryInterval, (_) => _report());
  }

  /// Send the current position, if there is a session and it has moved.
  Future<void> _report({bool? isPaused, bool force = false}) async {
    final session = _session;
    if (session == null) return;
    final ticks = PlaybackReport.ticksOf(_player.positionNow);
    if (!force && ticks == _lastSentTicks && isPaused == null) return;
    _lastSentTicks = ticks;
    await _send(
      PlaybackReportKind.progress,
      session.copyWith(
        positionTicks: ticks,
        isPaused: isPaused ?? !_player.isPlayingNow,
      ),
    );
  }

  /// End the session in flight. Idempotent — closing twice reports once.
  Future<void> close() async {
    final session = _session;
    _session = null;
    _ticker?.cancel();
    _ticker = null;
    await _playing?.cancel();
    await _completed?.cancel();
    _playing = null;
    _completed = null;
    if (session == null) return;

    // Forced: this is the report Jellyfin decides the resume point from, so it
    // goes even when the position has not moved since the last tick.
    await _send(
      PlaybackReportKind.stopped,
      session.copyWith(
        positionTicks: PlaybackReport.ticksOf(_player.positionNow),
        isPaused: false,
      ),
    );
  }

  /// Called when the app goes to the background or the window is closing.
  ///
  /// On mobile this may be the last code that runs before the process is
  /// killed, so it reports rather than assuming a later stop will.
  Future<void> flush() => _report(force: true);

  // ── Delivery ──────────────────────────────────────────────────────────────

  Future<void> _send(PlaybackReportKind kind, PlaybackReport report) async {
    // A guest watching a downloaded title has no session to report against;
    // there is no history to write and nothing to queue for later either.
    if (!_signedIn) return;
    try {
      await _ref
          .read(apiClientProvider)
          .reportPlayback(report, kind: kind);
      // A successful send is also the signal that the network is back.
      unawaited(_drain());
    } catch (_) {
      // Offline, or the server is down. A missed progress tick is worth
      // nothing — a newer one follows in ten seconds — but a missed STOP is the
      // resume point itself, so only that one is kept for later.
      if (kind == PlaybackReportKind.stopped) await _enqueue(report);
    }
  }

  Future<void> _enqueue(PlaybackReport report) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _read(prefs)
      // One pending report per title: the newest position supersedes any older
      // one, and replaying both would move the resume point backwards.
      ..removeWhere((r) => r.itemId == report.itemId)
      ..add(report);
    while (queue.length > kWatchHistoryQueueLimit) {
      queue.removeAt(0);
    }
    await _write(prefs, queue);
  }

  /// Send everything the queue is holding. Called on a successful report and at
  /// sign-in; anything that fails again stays queued.
  Future<void> drainPending() => _drain();

  Future<void> _drain() async {
    if (_disposed || !_signedIn) return;
    final prefs = await SharedPreferences.getInstance();
    final queue = _read(prefs);
    if (queue.isEmpty) return;

    final api = _ref.read(apiClientProvider);
    final unsent = <PlaybackReport>[];
    for (final report in queue) {
      try {
        await api.reportPlayback(report, kind: PlaybackReportKind.stopped);
      } catch (_) {
        // Still unreachable — keep this one and everything after it rather than
        // hammering a server that is plainly down.
        unsent.add(report);
      }
    }
    await _write(prefs, unsent);
  }

  List<PlaybackReport> _read(SharedPreferences prefs) {
    final raw = prefs.getStringList(kWatchHistoryQueueKey) ?? const [];
    return [for (final entry in raw) ?_decode(entry)];
  }

  PlaybackReport? _decode(String entry) {
    try {
      final json = jsonDecode(entry);
      return json is Map<String, dynamic> ? PlaybackReport.fromJson(json) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(SharedPreferences prefs, List<PlaybackReport> queue) =>
      prefs.setStringList(
        kWatchHistoryQueueKey,
        [for (final report in queue) jsonEncode(report.toJson())],
      );

  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    unawaited(_playing?.cancel());
    unawaited(_completed?.cancel());
  }
}

final watchHistoryProvider = Provider<WatchHistoryReporter>((ref) {
  final reporter = WatchHistoryReporter(ref);
  ref.onDispose(reporter.dispose);
  return reporter;
});

/// Drives [WatchHistoryReporter] off what is open in the player, and off the
/// app's lifecycle.
///
/// A widget-free listener because the reporter has to outlive any particular
/// screen: the player keeps running while you browse other tabs, and a reporter
/// mounted in the player's own widget tree would stop the moment the chrome
/// unmounted while the film played on.
class WatchHistoryBinding with WidgetsBindingObserver {
  WatchHistoryBinding(this._ref);

  final Ref _ref;
  ProviderSubscription<NowPlaying>? _subscription;

  WatchHistoryReporter get _reporter => _ref.read(watchHistoryProvider);

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _subscription = _ref.listen<NowPlaying>(
      nowPlayingProvider,
      (_, now) => unawaited(_reporter.open(now)),
      fireImmediately: true,
    );
    // A queue left over from a session that ended offline.
    unawaited(_reporter.drainPending());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding is where a mobile process goes to be killed without further
    // notice, so the position goes out now rather than on a stop that may never
    // get to run.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_reporter.flush());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_reporter.drainPending());
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.close();
  }
}

final watchHistoryBindingProvider = Provider<WatchHistoryBinding>((ref) {
  final binding = WatchHistoryBinding(ref);
  ref.onDispose(binding.dispose);
  return binding;
});
