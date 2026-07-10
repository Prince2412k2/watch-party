/// No remaining placeholder screens — Browse/Detail (E3), Downloads/Offline
/// (E8), Servarr (E9), and Party (E5) all now have real implementations.
/// `PartyScreen` moved to `party_screen.dart`; re-exported here so
/// `router.dart`'s existing `import 'screens/placeholder_screens.dart'` keeps
/// resolving without a router.dart edit (see the E5 report for the one-line
/// change to point that import straight at `party_screen.dart` instead,
/// whenever router.dart is next touched).
library;

export 'party_screen.dart';
