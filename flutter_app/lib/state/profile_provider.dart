import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../models/models.dart';
import 'providers.dart';

/// The signed-in user's own profile — display name and saved avatar.
///
/// Everyone else's name arrives on party state, and everyone else's face is
/// fetched by account id, so this is only what we need to draw *me*: my own
/// account control, and the editor's starting point.
class ProfileState {
  const ProfileState({this.profile, this.loading = false, this.error});

  final UserProfile? profile;
  final bool loading;
  final String? error;

  /// What to call me. Falls back to the account name, then to nothing.
  String get shownName => profile?.shownName ?? '';
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier(this._ref) : super(const ProfileState());

  final Ref _ref;

  /// A failure here is not fatal: no profile means no customisation, which is
  /// the ordinary state of a brand-new account.
  Future<void> load() async {
    state = ProfileState(profile: state.profile, loading: true);
    try {
      final profile = await _ref.read(apiClientProvider).profile();
      state = ProfileState(profile: profile);
    } catch (e) {
      state = ProfileState(profile: state.profile, error: e.toString());
    }
  }

  /// Returns null on success, or a message to show the user. Saving reports
  /// failure rather than quietly appearing to have worked.
  Future<String?> save({String? displayName, AvatarConfig? avatar}) async {
    state = ProfileState(profile: state.profile, loading: true);
    try {
      final saved = await _ref
          .read(apiClientProvider)
          .saveProfile(displayName: displayName, avatar: avatar);
      state = ProfileState(profile: saved);
      // My face changed, so every cached drawing of it is stale.
      _ref.read(avatarRevisionProvider.notifier).state++;
      return null;
    } catch (e) {
      final message = e is ApiException ? e.message : 'Could not save';
      state = ProfileState(profile: state.profile, error: message);
      return message;
    }
  }

  void clear() => state = const ProfileState();
}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>(
  (ref) => ProfileNotifier(ref),
);

/// Bumped whenever a drawn avatar might have changed. Avatar widgets cache the
/// SVG they fetched — they are ~35 KB each and a party redraws constantly — and
/// this is what tells them the cache is stale, so a profile edit shows up
/// without anyone reloading anything.
final avatarRevisionProvider = StateProvider<int>((ref) => 0);
