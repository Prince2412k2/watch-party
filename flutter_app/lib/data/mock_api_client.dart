import '../models/models.dart';
import 'api_client.dart';

/// In-memory [ApiClient] used by the gallery, widget tests, and any epic that
/// wants to build UI before its real endpoint lands. Deterministic, no network.
class MockApiClient implements ApiClient {
  MockApiClient({this.baseUrl = 'http://mock.local'});

  @override
  String baseUrl;

  static const _user = User(userId: 'mock-user', name: 'root', isAdmin: true);

  static final List<LibraryItem> _catalog = List.generate(
    12,
    (i) => LibraryItem(
      id: 'mock-item-$i',
      name: _titles[i % _titles.length],
      type: i.isEven ? 'Movie' : 'Series',
      productionYear: 1990 + i,
      overview: 'A placeholder synopsis for ${_titles[i % _titles.length]}.',
      runTimeTicks: (90 + i) * 60 * 10000000,
      communityRating: 6.5 + (i % 4) * 0.6,
      genres: const ['Drama', 'Thriller'],
    ),
  );

  static const _titles = [
    '12 Angry Men', 'Blade Runner', 'Chinatown', 'Dune', 'Election',
    'Fargo', 'Gattaca', 'Heat', 'Inception', 'Jaws', 'Klute', 'La La Land',
  ];

  @override
  Future<User> login(String username, String password) async => _user;

  @override
  Future<User> me() async => _user;

  @override
  Future<void> logout() async {}

  @override
  Future<HomeData> home() async => HomeData(
        views: _catalog.take(3).toList(),
        resume: _catalog.skip(3).take(4).toList(),
        nextUp: _catalog.skip(7).take(4).toList(),
      );

  @override
  Future<List<LibraryItem>> items({String? parentId}) async => _catalog;

  @override
  Future<List<LibraryItem>> children(String itemId) async =>
      _catalog.take(4).toList();

  @override
  Future<LibraryItem> item(String id) async =>
      _catalog.firstWhere((e) => e.id == id, orElse: () => _catalog.first);

  @override
  Future<List<LibraryItem>> latest({String? parentId}) async => _catalog;

  @override
  Future<List<LibraryItem>> search(String query) async {
    final q = query.toLowerCase();
    return _catalog.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  @override
  String imageUrl(String itemId,
          {ImageType type = ImageType.primary, String? tag}) =>
      '$baseUrl/image/$itemId';

  @override
  Future<StreamUrl> nativeStreamUrl(String itemId,
          {String purpose = 'stream'}) async =>
      StreamUrl(
        url: '$baseUrl/native/file?token=mock-$itemId-$purpose',
        expiresAt: DateTime.now()
            .add(const Duration(hours: 6))
            .millisecondsSinceEpoch,
      );

  @override
  Future<LiveKitToken> livekitToken(String partyId) async => const LiveKitToken(
        token: 'mock-token',
        url: 'ws://localhost:7880',
      );

  @override
  Future<dynamic> servarrGet(String path, {Map<String, dynamic>? query}) async =>
      const [];

  @override
  Future<dynamic> servarrPost(String path, {Object? body}) async =>
      {'ok': true};

  @override
  Future<dynamic> servarrDelete(String path,
          {Map<String, dynamic>? query}) async =>
      {'ok': true};

  @override
  String servarrImageUrl(String remoteUrl) => remoteUrl;
}
