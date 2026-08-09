import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/state/now_playing_provider.dart';
import 'package:watchparty/state/player_provider.dart';

/// Records the two calls that stop playback, over the real mock so every other
/// member of the interface keeps its normal behaviour.
class _RecordingPlayer extends MockPlayerController {
  int pauseCalls = 0;
  final List<Duration> seeks = [];

  @override
  Future<void> pause() async {
    pauseCalls++;
    await super.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    await super.seek(position);
  }
}

/// The one rule this provider exists to enforce: **only close() stops
/// playback.** Every bug it was written to prevent is something else reaching
/// the controller — which is exactly what `DetailScreen.dispose()` used to do,
/// and why Back ended the movie instead of shrinking it.
void main() {
  late _RecordingPlayer player;
  late ProviderContainer container;

  setUp(() {
    player = _RecordingPlayer();
    container = ProviderContainer(
      overrides: [playerControllerProvider.overrideWithValue(player)],
    );
  });
  tearDown(() => container.dispose());

  NowPlayingNotifier notifier() => container.read(nowPlayingProvider.notifier);
  NowPlaying now() => container.read(nowPlayingProvider);

  test('nothing is playing until something is opened', () {
    expect(now().isOpen, isFalse);
    expect(now().presentation, PlayerPresentation.hidden);
  });

  test('open lands full-window and carries its track choices', () {
    notifier().open(
      itemId: 'movie-1',
      title: 'Dune',
      audioStreamIndex: 2,
      subtitleStreamIndex: 3,
    );
    expect(now().isExpanded, isTrue);
    expect(now().itemId, 'movie-1');
    expect(now().title, 'Dune');
    expect(now().audioStreamIndex, 2);
    expect(now().subtitleStreamIndex, 3);
  });

  test('minimise never touches the controller', () {
    notifier().open(itemId: 'movie-1');
    notifier().minimise();

    expect(now().isFloating, isTrue);
    expect(now().itemId, 'movie-1', reason: 'the title must survive minimising');
    expect(player.pauseCalls, 0);
    expect(player.seeks, isEmpty);
  });

  test('expand and minimise round-trip without disturbing playback', () {
    notifier().open(itemId: 'movie-1');
    notifier().minimise();
    notifier().expand();
    notifier().minimise();
    notifier().expand();

    expect(now().isExpanded, isTrue);
    expect(player.pauseCalls, 0);
    expect(player.seeks, isEmpty);
  });

  test('close is the only thing that stops and rewinds', () async {
    notifier().open(itemId: 'movie-1');
    await notifier().close();

    expect(now().isOpen, isFalse);
    expect(now().itemId, isNull);
    expect(player.pauseCalls, 1);
    expect(player.seeks, contains(Duration.zero));
  });

  test('re-opening the same title only changes how it is shown', () {
    // A party's `party:state` resync repeats the current title on every
    // heartbeat. Treating each repeat as a fresh open would reset playback
    // several times a minute.
    notifier().open(itemId: 'movie-1', title: 'Dune', subtitleStreamIndex: 3);
    notifier().minimise();
    notifier().open(itemId: 'movie-1', title: 'Dune');

    expect(now().isExpanded, isTrue);
    expect(now().subtitleStreamIndex, 3, reason: 'the original choice stands');
    expect(player.pauseCalls, 0);
  });

  test('opening a different title supersedes the old one wholesale', () {
    notifier().open(itemId: 'movie-1', subtitleStreamIndex: 3, fromParty: true);
    notifier().open(itemId: 'movie-2');

    expect(now().itemId, 'movie-2');
    expect(now().subtitleStreamIndex, isNull, reason: 'stale choice must not leak');
    expect(now().fromParty, isFalse);
  });

  test('minimise and expand do nothing when nothing is playing', () {
    notifier().minimise();
    expect(now().presentation, PlayerPresentation.hidden);
    notifier().expand();
    expect(now().presentation, PlayerPresentation.hidden);
  });
}
