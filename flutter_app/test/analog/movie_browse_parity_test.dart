// The Dart half of app/client/src/analog/movieBrowse.test.ts.
//
// Same cases, same expectations, in the same order — so that a change to the
// Movies browse model on one client and not the other shows up as a failure
// here rather than as two stages that quietly disagree about what Enter does.

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/movie_browse.dart';
import 'package:watchparty/analog/surface.dart';

List<MovieLevel> root(BrowseMode mode) => [
  rootLevel(const MoviesView(id: 'view-1', name: 'Movies'), mode),
];

void main() {
  test('the mode slider steps and clamps rather than wrapping', () {
    expect(browseModes, [BrowseMode.singles, BrowseMode.collections]);
    expect(stepBrowseMode(BrowseMode.singles, 1), BrowseMode.collections);
    expect(stepBrowseMode(BrowseMode.collections, -1), BrowseMode.singles);
    // Held Down settles on the last position instead of flickering back to the
    // first, which is what a two-position slider that wrapped would do.
    expect(stepBrowseMode(BrowseMode.collections, 1), BrowseMode.collections);
    expect(stepBrowseMode(BrowseMode.singles, -1), BrowseMode.singles);
    expect(stepBrowseMode(BrowseMode.singles, 0), BrowseMode.singles);
  });

  test('a stepped scroll outside the rail moves the same slider the arrows do', () {
    expect(
      modeForScrollStep(BrowseMode.singles, 1),
      stepBrowseMode(BrowseMode.singles, 1),
    );
    expect(
      modeForScrollStep(BrowseMode.collections, -1),
      stepBrowseMode(BrowseMode.collections, -1),
    );
    // steppedScroll returns 0 for everything that is not a deliberate step —
    // absorbed momentum, a delta under the threshold, a burst inside cooldown.
    expect(modeForScrollStep(BrowseMode.collections, 0), BrowseMode.collections);
  });

  test('the four arrows are four different movements on this stage', () {
    // NOT the kit's focusIntentForKey, which folds Up/Down onto Left/Right:
    // this stage has a horizontal rail AND a vertical mode slider.
    expect(stageKeyIntent('ArrowLeft'), StageIntent.railPrev);
    expect(stageKeyIntent('ArrowRight'), StageIntent.railNext);
    expect(stageKeyIntent('ArrowUp'), StageIntent.modePrev);
    expect(stageKeyIntent('ArrowDown'), StageIntent.modeNext);
    expect(stageKeyIntent('Enter'), StageIntent.activate);
    expect(stageKeyIntent(' '), StageIntent.activate);
    expect(stageKeyIntent('Spacebar'), StageIntent.activate);
    expect(stageKeyIntent('Escape'), StageIntent.back);
    expect(stageKeyIntent('Backspace'), StageIntent.back);
    expect(stageKeyIntent('a'), isNull);
    expect(stageKeyIntent('Tab'), isNull);
  });

  test('the intent names match the web spellings', () {
    // The wire names are what the shared fixture and any cross-client debugging
    // read; an enum rename in Dart must not silently change them.
    expect(StageIntent.railPrev.wireName, 'rail-prev');
    expect(StageIntent.railNext.wireName, 'rail-next');
    expect(StageIntent.modePrev.wireName, 'mode-prev');
    expect(StageIntent.modeNext.wireName, 'mode-next');
    expect(BrowseMode.singles.wireName, 'singles');
    expect(BrowseMode.collections.wireName, 'collections');
    expect(BrowseMode.fromWire('collections'), BrowseMode.collections);
    expect(BrowseMode.fromWire('nonsense'), isNull);
    expect(isBrowseMode('singles'), isTrue);
    expect(isBrowseMode(null), isFalse);
  });

  test('the mode rides on the stack, so a party follower sees the host\'s', () {
    expect(modeFromStack(root(BrowseMode.collections)), BrowseMode.collections);
    expect(modeFromStack(root(BrowseMode.singles)), BrowseMode.singles);
    // An untagged or empty stack falls back rather than guessing.
    expect(modeFromStack(const []), BrowseMode.singles);
    expect(
      modeFromStack(const [MovieLevel(id: 'view-1')], BrowseMode.collections),
      BrowseMode.collections,
    );
  });

  test('switching mode leaves any franchise you were inside', () {
    final inside = openCollection(
      root(BrowseMode.collections),
      const MovieLevel(id: 'box-1', name: 'Alien'),
    );
    expect(inside.length, 2);

    final switched = withMode(inside, BrowseMode.singles);
    expect(switched.length, 1, reason: 'truncates to the root');
    expect(modeFromStack(switched), BrowseMode.singles);
    expect(withMode(const [], BrowseMode.singles), isEmpty);
  });

  test('opening a collection pushes a level and Back pops it', () {
    final stack = openCollection(
      root(BrowseMode.collections),
      const MovieLevel(id: 'box-1', name: 'Alien'),
    );
    expect(stack.length, 2);
    expect(collectionFromStack(stack)?.id, 'box-1');

    final closed = closeCollection(stack);
    expect(closed.length, 1);
    expect(collectionFromStack(closed), isNull);
    // Back at the root is a no-op rather than emptying the stack.
    expect(closeCollection(closed).length, 1);
  });

  test('opening a collection from Singles switches the mode with it', () {
    // A box set can turn up in a library listing. Following it must not leave
    // the slider pointing at Singles while the rail shows a franchise's parts.
    final stack = openCollection(
      root(BrowseMode.singles),
      const MovieLevel(id: 'box-1', name: 'Alien'),
    );
    expect(modeFromStack(stack), BrowseMode.collections);
    expect(stack[1].type, 'BoxSet');
    expect(
      openCollection(const [], const MovieLevel(id: 'box-1', name: 'Alien')),
      isEmpty,
    );
  });

  test('only a box set counts as a drill-in', () {
    // The wire type allows every field to be absent, and following an
    // unidentified level would fetch nothing and render an empty rail.
    expect(
      collectionFromStack(const [
        MovieLevel(id: 'view-1'),
        MovieLevel(name: 'Ghost'),
      ]),
      isNull,
    );
    expect(collectionFromStack(const [MovieLevel(id: 'view-1')]), isNull);
    expect(collectionFromStack(const []), isNull);

    // A driver on an older implementation pushes a Movie level for a title's
    // detail page. Reading that as a franchise would ask the collections route
    // for a movie id and render an empty rail under the wrong heading.
    expect(
      collectionFromStack(const [
        MovieLevel(id: 'view-1'),
        MovieLevel(id: 'm1', name: 'Alien', type: 'Movie'),
      ]),
      isNull,
    );
    expect(
      collectionFromStack(const [
        MovieLevel(id: 'view-1'),
        MovieLevel(id: 's1', type: 'Season'),
      ]),
      isNull,
    );
    // No type at all is still followed: this surface only ever pushes box sets.
    expect(
      collectionFromStack(const [
        MovieLevel(id: 'view-1'),
        MovieLevel(id: 'box-1', name: 'Alien'),
      ]),
      const MovieLevel(id: 'box-1', name: 'Alien'),
    );
  });

  test('Enter plays a movie and opens a collection', () {
    expect(
      activationFor(id: 'm1', name: 'Alien', type: 'Movie'),
      const PlayActivation('m1'),
    );
    // A part inside a franchise is a movie, so it plays — "movies will act like
    // episodes", and the details are already on the stage.
    expect(
      activationFor(id: 'm2', name: 'Aliens', type: 'Movie'),
      const PlayActivation('m2'),
    );
    expect(
      activationFor(id: 'box-1', name: 'Alien', type: 'BoxSet'),
      const OpenActivation(
        MovieLevel(id: 'box-1', name: 'Alien', type: 'BoxSet'),
      ),
    );
    expect(activationFor(), const NoActivation());
    expect(activationFor(name: 'No id', type: 'Movie'), const NoActivation());
    expect(
      activationFor(id: '', name: 'Blank', type: 'Movie'),
      const NoActivation(),
    );
  });

  test('each mode and each franchise keeps its own focus position', () {
    // Singles and Collections are two lists of different lengths; one memory
    // would restore focus in one from an index only the other ever had.
    final singles = surfaceId(
      moviesTab(BrowseMode.singles),
      root(BrowseMode.singles),
    );
    final collections = surfaceId(
      moviesTab(BrowseMode.collections),
      root(BrowseMode.collections),
    );
    final inside = surfaceId(
      moviesTab(BrowseMode.collections),
      openCollection(
        root(BrowseMode.collections),
        const MovieLevel(id: 'box-1', name: 'Alien'),
      ),
    );

    expect(singles, 'movies:singles/view-1');
    expect(collections, 'movies:collections/view-1');
    expect(inside, 'movies:collections/view-1/box-1');
    expect({singles, collections, inside}.length, 3);
  });
}
