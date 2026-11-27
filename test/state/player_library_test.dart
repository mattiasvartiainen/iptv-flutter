import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/models/library_identity.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/favorite_repository.dart';
import 'package:iptv_flutter/services/catalog/user_library_repository.dart';
import 'package:iptv_flutter/services/playback/fake_playback.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NavigationController navigation;
  late _Library library;
  late PlayerController player;
  late List<String> changedPlaylists;
  setUp(() {
    navigation = NavigationController();
    library = _Library();
    changedPlaylists = [];
    player = PlayerController(
      playbackAdapter: _Tracks(),
      navigationController: navigation,
      favorites: library,
      userLibrary: library,
      onFavoriteChanged: changedPlaylists.add,
    );
  });
  tearDown(() {
    player.dispose();
    navigation.dispose();
  });

  test(
    'stable playlist/key identity survives item renumbering and persisted reads',
    () async {
      await player.openPlayer(_item('row1', 'one', 42));
      await player.toggleFavorite();
      expect(library.values[('default', 'one', 42)], isTrue);
      expect(changedPlaylists, ['one']);
      await player.openPlayer(_item('row9', 'one', 42));
      expect(player.favorite, isTrue);
      await player.toggleFavorite();
      expect(library.values[('default', 'one', 42)], isFalse);
      expect(changedPlaylists, ['one', 'one']);
    },
  );

  test('session identity scopes equal row IDs and clears on exit', () async {
    await player.openPlayer(_item('same-row', 'one', 42), profileId: 'alice');
    expect(
      player.libraryIdentity,
      const LibraryIdentity(playlistId: 'one', profileId: 'alice', itemKey: 42),
    );
    await player.openPlayer(_item('same-row', 'two', 99), profileId: 'bob');
    expect(
      player.libraryIdentity,
      const LibraryIdentity(playlistId: 'two', profileId: 'bob', itemKey: 99),
    );
    navigation.pop();
    expect(player.libraryIdentity, isNull);
  });

  test('favorite operations respect the playback profile', () async {
    await player.openPlayer(_item('row', 'one', 42), profileId: 'other');
    await player.toggleFavorite();
    expect(library.profiles, contains('other'));
    expect(player.libraryIdentity?.profileId, 'other');
    expect(player.userLibrary, same(library));
    await player.openPlayer(_item('row', 'one', 42));
    expect(player.favorite, isFalse);
    expect(library.values[('other', 'one', 42)], isTrue);
    expect(library.values[('default', 'one', 42)], isNull);
  });

  test(
    'rapid toggles serialize and in-flight write captures original identity',
    () async {
      await player.openPlayer(_item('row1', 'one', 42));
      library.writeGate = Completer<void>();
      final write = player.toggleFavorite();
      await player.toggleFavorite();
      expect(library.writes, 1);
      await player.openPlayer(_item('row2', 'two', 43));
      library.writeGate!.complete();
      await write;
      expect(library.values[('default', 'one', 42)], isTrue);
      expect(changedPlaylists, ['one']);
      expect(player.favorite, isFalse);
      expect(player.favoriteBusy, isFalse);
      expect(library.values[('default', 'two', 43)], isNull);
    },
  );

  test('late favourite read cannot replace a newer playback item', () async {
    library.readGate = Completer<bool>();
    await player.openPlayer(_item('row1', 'one', 42));
    final pending = library.readGate!;
    library.readGate = null;
    await player.openPlayer(_item('row2', 'two', 43));
    pending.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(player.favorite, isFalse);
  });

  test(
    'write and track failures report nonfatal errors and can retry',
    () async {
      await player.openPlayer(_item('row1', 'one', 42));
      library.failWrite = true;
      await player.toggleFavorite();
      expect(player.controlError, contains('Could not update'));
      expect(changedPlaylists, isEmpty);
      expect(player.playbackState.value.status, PlaybackStatus.playing);
      library.failWrite = false;
      await player.toggleFavorite();
      expect(player.favorite, isTrue);
      expect(player.controlError, isNull);
      expect(await player.selectTrack('missing', subtitle: false), isFalse);
      expect(player.controlError, contains('Could not change track'));
      expect(player.playbackState.value.status, PlaybackStatus.playing);
      expect(await player.selectTrack('1', subtitle: false), isTrue);
      expect(player.controlError, isNull);
    },
  );

  test('absolute seek clamps negative/end positions', () async {
    await player.openPlayer(_item('row1', 'one', 42));
    await player.seekTo(const Duration(seconds: -1));
    expect(player.playbackState.value.position, Duration.zero);
    await player.seekTo(const Duration(hours: 1));
    expect(player.playbackState.value.position, const Duration(minutes: 5));
  });
}

ContentItem _item(String id, String playlist, int key) => ContentItem(
  group: 'Movies',
  id: id,
  title: 'Movie',
  type: ContentType.vod,
  streamUrl: 'https://example.invalid/movie.mp4',
  catalogPlaylistId: playlist,
  catalogItemKey: key,
);

class _Tracks extends FakePlaybackAdapter {
  _Tracks()
    : super(
        transitionDelay: Duration.zero,
        duration: const Duration(minutes: 5),
        mediaInfo: const PlaybackMediaInfo(
          audioTracks: [PlaybackTrack(id: '1', label: 'English')],
        ),
      );
}

class _Library implements FavoriteRepository, UserLibraryRepository {
  final values = <(String, String, int), bool>{};
  Completer<void>? writeGate;
  Completer<bool>? readGate;
  bool failWrite = false;
  int writes = 0;
  final profiles = <String>[];
  @override
  Future<bool> isFavorite({
    required String playlistId,
    required int itemKey,
    String profileId = 'default',
  }) async {
    profiles.add(profileId);
    return readGate != null
        ? await readGate!.future
        : values[(profileId, playlistId, itemKey)] ?? false;
  }

  @override
  Future<void> setFavorite({
    required String playlistId,
    required int itemKey,
    required bool favorite,
    String profileId = 'default',
  }) async {
    profiles.add(profileId);
    writes++;
    if (writeGate != null) await writeGate!.future;
    if (failWrite) throw StateError('write failed');
    values[(profileId, playlistId, itemKey)] = favorite;
  }

  @override
  Future<List<CatalogItemSummary>> favoriteItems({
    required String playlistId,
    String profileId = 'default',
    int limit = kCatalogPageSize,
  }) => throw UnimplementedError();

  @override
  Future<CatalogPlaybackProgress?> playbackProgress({
    required String playlistId,
    required int itemKey,
    String profileId = 'default',
  }) => throw UnimplementedError();

  @override
  Future<void> savePlaybackProgress({
    required String playlistId,
    required int itemKey,
    required int positionMs,
    int? durationMs,
    String profileId = 'default',
  }) => throw UnimplementedError();

  @override
  Future<void> recordWatchHistory({
    required String playlistId,
    required int itemKey,
    required bool completed,
    int? positionMs,
    int? durationMs,
    String profileId = 'default',
  }) => throw UnimplementedError();

  @override
  Future<List<CatalogItemSummary>> recentlyWatchedItems({
    required String playlistId,
    String profileId = 'default',
    int limit = kHomePreviewCount,
  }) => throw UnimplementedError();
}
