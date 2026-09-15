import 'package:flutter/foundation.dart';

import '../models/content_item.dart';
import '../services/errors/app_issue.dart';
import '../services/catalog/catalog_query.dart';
import '../services/catalog/catalog_query_service.dart';
import '../services/catalog/catalog_repository.dart';
import '../services/logging/app_logger.dart';
import '../services/playback/playback_adapter.dart';
import '../services/settings/settings_repository.dart';
import '../services/storage/storage_bootstrap.dart';
import 'catalog_view_state.dart';

enum AppScreen {
  home,
  liveCatalog,
  movieCatalog,
  seriesCatalog,
  seasonCatalog,
  episodeCatalog,
  details,
  player,
  search,
  settings,
}

enum PrimaryNavItem { home, liveTv, movies, series, search }

enum LoadStatus { idle, loading, ready, error }

class AppController extends ChangeNotifier {
  AppController({
    CatalogRepository? catalogRepository,
    CatalogQueryService? catalogQueryService,
    SettingsRepository? settingsRepository,
    PlaybackAdapter? playbackAdapter,
    AppLogger? logger,
  }) : _catalogRepository =
           catalogRepository ?? AppStorageBootstrap.instance.catalogRepository,
       _injectedQueryService = catalogQueryService,
       _settingsRepository =
           settingsRepository ??
           AppStorageBootstrap.instance.settingsRepository,
       _logger = logger ?? const DebugAppLogger(),
       playbackAdapter = playbackAdapter ?? createPlatformPlaybackAdapter() {
    _queryService =
        _injectedQueryService ??
        (_catalogRepository is CatalogQueryService
            ? _catalogRepository as CatalogQueryService
            : null);
  }

  static const ContentItem playbackSpikeItem = ContentItem(
    id: 'playback-spike-live-hls',
    title: 'Playback Spike - Live HLS',
    type: ContentType.live,
    streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    group: 'Playback Spike',
    description:
        'Public HLS stream used to validate player integration before full catalog wiring.',
  );

  final CatalogRepository _catalogRepository;
  final CatalogQueryService? _injectedQueryService;
  final SettingsRepository _settingsRepository;
  final AppLogger _logger;
  final PlaybackAdapter playbackAdapter;

  CatalogQueryService? _queryService;

  /// Owns the visible page window; the controller never holds the full catalog.
  final CatalogViewState catalogView = CatalogViewState();

  AppScreen screen = AppScreen.home;
  LoadStatus playlistStatus = LoadStatus.idle;
  ContentItem? selectedItem;
  String? playlistUrl;
  String? activePlaylistId;
  String? refreshingPlaylistId;
  String? errorMessage;
  ContentType? catalogType;
  SeriesSummary? selectedSeries;
  SeasonSummary? selectedSeason;
  List<ManagedPlaylist> playlists = const [];
  bool showHomeLiveTv = true;
  bool showHomeMovies = true;
  bool showHomeSeries = true;
  bool verboseRefreshInfo = false;
  CatalogImportProgress? importProgress;
  AppIssue? activeIssue;

  static const _activePlaylistSettingKey = 'active_playlist_id';
  static const _verboseRefreshInfoSettingKey = 'verbose_refresh_info';

  int get catalogItemCount => catalogView.itemCount;

  PrimaryNavItem get activeNavItem {
    return switch (screen) {
      AppScreen.home => PrimaryNavItem.home,
      AppScreen.liveCatalog => PrimaryNavItem.liveTv,
      AppScreen.movieCatalog => PrimaryNavItem.movies,
      AppScreen.seriesCatalog ||
      AppScreen.seasonCatalog ||
      AppScreen.episodeCatalog => PrimaryNavItem.series,
      AppScreen.search => PrimaryNavItem.search,
      _ => PrimaryNavItem.home,
    };
  }

  Future<void> initialize() async {
    await AppStorageBootstrap.instance.initialize();
    await refreshHomeSectionVisibility();
    await refreshVerboseRefreshInfoSetting();
    await refreshPlaylists();
    final savedActivePlaylistId = await _settingsRepository.getAppSetting(
      _activePlaylistSettingKey,
    );
    final initialPlaylist = playlists
        .where((playlist) => playlist.playlistId == savedActivePlaylistId)
        .firstOrNull;
    if (initialPlaylist != null && !catalogView.hasContent) {
      await loadPlaylist(
        initialPlaylist.playlistId,
        policy: CatalogLoadPolicy.cacheOnly,
        allowEmptyCatalog: true,
      );
    }
  }

  Future<void> refreshPlaylists() async {
    playlists = await _settingsRepository.listPlaylists();
    if (playlists.isEmpty) {
      activePlaylistId = null;
      if (!catalogView.hasContent) screen = AppScreen.home;
    }
    notifyListeners();
  }

  Future<void> refreshHomeSectionVisibility() async {
    final live = await _settingsRepository.getAppSetting('show_home_live_tv');
    final movies = await _settingsRepository.getAppSetting('show_home_movies');
    final series = await _settingsRepository.getAppSetting('show_home_series');

    showHomeLiveTv = _parseBoolOrDefault(live, defaultValue: true);
    showHomeMovies = _parseBoolOrDefault(movies, defaultValue: true);
    showHomeSeries = _parseBoolOrDefault(series, defaultValue: true);
    notifyListeners();
  }

  Future<void> setHomeSectionVisibility({
    required String settingKey,
    required bool enabled,
  }) async {
    await _settingsRepository.setAppSetting(
      settingKey,
      enabled ? 'true' : 'false',
    );
    await refreshHomeSectionVisibility();
  }

  Future<void> refreshVerboseRefreshInfoSetting() async {
    final stored = await _settingsRepository.getAppSetting(
      _verboseRefreshInfoSettingKey,
    );
    verboseRefreshInfo = _parseBoolOrDefault(stored, defaultValue: false);
    notifyListeners();
  }

  Future<void> setVerboseRefreshInfo(bool enabled) async {
    await _settingsRepository.setAppSetting(
      _verboseRefreshInfoSettingKey,
      enabled ? 'true' : 'false',
    );
    await refreshVerboseRefreshInfoSetting();
  }

  Future<bool> savePlaylist(String value) async {
    final normalized = value.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      errorMessage = 'Enter a valid playlist URL.';
      playlistStatus = LoadStatus.error;
      notifyListeners();
      return false;
    }

    playlistStatus = LoadStatus.loading;
    errorMessage = null;
    activeIssue = null;
    notifyListeners();
    _logger.info(
      'playlist_import_started',
      context: {'source': 'setup', 'playlistHost': uri.host},
    );
    try {
      final saved = await _settingsRepository.upsertPlaylist(
        PlaylistSourceConfig.url(
          name: uri.host.isNotEmpty ? uri.host : 'Playlist',
          url: normalized,
        ),
      );
      final loaded = await loadPlaylist(
        saved.playlistId,
        policy: CatalogLoadPolicy.networkOnly,
        logContext: {'source': 'setup', 'playlistHost': uri.host},
      );
      if (!loaded) return false;
      _logger.info(
        'playlist_import_succeeded',
        context: {
          'source': 'setup',
          'playlistHost': uri.host,
          'items': catalogView.itemCount,
        },
      );
      notifyListeners();
      return true;
    } on AppIssueException catch (error, stackTrace) {
      _applyIssue(error.issue);
      _logger.error(
        'playlist_import_failed',
        error: error.cause ?? error,
        stackTrace: error.stackTrace ?? stackTrace,
        context: {
          'source': error.issue.source.name,
          'kind': error.issue.kind.name,
          'playlistHost': uri.host,
          'retryable': error.issue.retryable,
        },
      );
      return false;
    } catch (_) {
      final issue = const AppIssue(
        kind: AppIssueKind.unknown,
        source: AppIssueSource.setup,
        title: 'Import failed',
        message: 'Could not load that playlist. Try again.',
      );
      _applyIssue(issue);
      _logger.error(
        'playlist_import_failed',
        context: {
          'source': issue.source.name,
          'kind': issue.kind.name,
          'playlistHost': uri.host,
          'retryable': issue.retryable,
        },
      );
      return false;
    }
  }

  Future<bool> savePlaylistUrl({
    String? playlistId,
    required String name,
    required String url,
  }) async {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      errorMessage = 'Enter a valid playlist URL.';
      playlistStatus = LoadStatus.error;
      notifyListeners();
      return false;
    }

    try {
      await _settingsRepository.upsertPlaylist(
        PlaylistSourceConfig.url(
          playlistId: playlistId,
          name: name.trim().isEmpty ? uri.host : name.trim(),
          url: normalized,
        ),
      );
      await refreshPlaylists();
      errorMessage = null;
      activeIssue = null;
      playlistStatus = LoadStatus.ready;
      notifyListeners();
      return true;
    } on AppIssueException catch (error, stackTrace) {
      _applyIssue(error.issue);
      _logger.error(
        'playlist_import_failed',
        error: error.cause ?? error,
        stackTrace: error.stackTrace ?? stackTrace,
        context: {
          'source': error.issue.source.name,
          'kind': error.issue.kind.name,
          'playlistHost': uri.host,
          'retryable': error.issue.retryable,
        },
      );
      return false;
    } catch (_) {
      final issue = const AppIssue(
        kind: AppIssueKind.unknown,
        source: AppIssueSource.setup,
        title: 'Import failed',
        message: 'Could not load that playlist. Try again.',
      );
      _applyIssue(issue);
      _logger.error(
        'playlist_import_failed',
        context: {
          'source': issue.source.name,
          'kind': issue.kind.name,
          'playlistHost': uri.host,
          'retryable': issue.retryable,
        },
      );
      return false;
    }
  }

  Future<bool> saveXtreamPlaylist({
    String? playlistId,
    required String name,
    required String server,
    required String username,
    required String password,
  }) async {
    final normalizedServer = server.trim();
    if (normalizedServer.isEmpty ||
        username.trim().isEmpty ||
        password.isEmpty) {
      errorMessage = 'Enter the server, username, and password.';
      playlistStatus = LoadStatus.error;
      notifyListeners();
      return false;
    }

    try {
      await _settingsRepository.upsertPlaylist(
        PlaylistSourceConfig.xtream(
          playlistId: playlistId,
          name: name.trim().isEmpty
              ? Uri.tryParse(normalizedServer)?.host ?? 'Playlist'
              : name.trim(),
          server: normalizedServer,
          username: username.trim(),
          password: password,
        ),
      );
      await refreshPlaylists();
      errorMessage = null;
      activeIssue = null;
      playlistStatus = LoadStatus.ready;
      notifyListeners();
      return true;
    } on AppIssueException catch (error, stackTrace) {
      _applyIssue(error.issue);
      _logger.error(
        'playlist_import_failed',
        error: error.cause ?? error,
        stackTrace: error.stackTrace ?? stackTrace,
        context: {
          'source': error.issue.source.name,
          'kind': error.issue.kind.name,
          'playlistHost':
              Uri.tryParse(normalizedServer)?.host ?? normalizedServer,
          'retryable': error.issue.retryable,
        },
      );
      return false;
    } catch (_) {
      final issue = const AppIssue(
        kind: AppIssueKind.unknown,
        source: AppIssueSource.setup,
        title: 'Import failed',
        message: 'Could not load that playlist. Try again.',
      );
      _applyIssue(issue);
      _logger.error(
        'playlist_import_failed',
        context: {
          'source': issue.source.name,
          'kind': issue.kind.name,
          'playlistHost':
              Uri.tryParse(normalizedServer)?.host ?? normalizedServer,
          'retryable': issue.retryable,
        },
      );
      return false;
    }
  }

  Future<bool> loadPlaylist(
    String playlistId, {
    CatalogLoadPolicy policy = CatalogLoadPolicy.networkOnly,
    bool activateScreen = true,
    bool allowEmptyCatalog = false,
    bool updateActivePlaylist = true,
    bool updateActiveCatalog = true,
    Map<String, Object?>? logContext,
  }) async {
    final playlist = await _settingsRepository.getPlaylist(playlistId);
    if (playlist == null) {
      errorMessage = 'Playlist settings could not be found.';
      playlistStatus = LoadStatus.error;
      notifyListeners();
      return false;
    }

    final playlistUrl = await _settingsRepository.resolvePlaylistUrl(
      playlistId,
    );
    if (playlistUrl == null || playlistUrl.isEmpty) {
      errorMessage = 'Playlist source is missing.';
      playlistStatus = LoadStatus.error;
      notifyListeners();
      return false;
    }

    playlistStatus = LoadStatus.loading;
    errorMessage = null;
    activeIssue = null;
    importProgress = null;
    notifyListeners();

    final context = <String, Object?>{'playlistId': playlistId, ...?logContext};
    _logger.info('playlist_import_started', context: context);

    // Notifying on every callback would rebuild the whole screen far more
    // often than any device can render for a huge playlist; cap it to a
    // frame-friendly rate regardless of how many items are being imported.
    DateTime? lastProgressNotifyAt;
    const minProgressNotifyGap = Duration(milliseconds: 200);

    try {
      final result = await _catalogRepository.load(
        playlistUrl: playlistUrl,
        playlistId: playlistId,
        playlistName: playlist.name,
        policy: policy,
        onProgress: verboseRefreshInfo
            ? (progress) {
                importProgress = progress;
                final now = DateTime.now();
                if (lastProgressNotifyAt == null ||
                    now.difference(lastProgressNotifyAt!) >=
                        minProgressNotifyGap) {
                  lastProgressNotifyAt = now;
                  notifyListeners();
                }
              }
            : null,
      );
      if (result.itemCount == 0 && !allowEmptyCatalog) {
        throw const FormatException('The playlist is empty.');
      }

      if (updateActivePlaylist) {
        this.playlistUrl = playlistUrl;
        await _setActivePlaylist(playlistId);
      }
      if (updateActiveCatalog) {
        await _bindCatalogView(playlistId);
      }
      await refreshHomeSectionVisibility();
      await refreshPlaylists();
      if (updateActiveCatalog) {
        selectedSeries = null;
        selectedSeason = null;
      }
      playlistStatus = LoadStatus.ready;
      if (activateScreen) {
        screen = AppScreen.home;
      }
      _logger.info(
        'playlist_import_succeeded',
        context: {...context, 'items': result.itemCount},
      );
      notifyListeners();
      return true;
    } on AppIssueException catch (error, stackTrace) {
      _applyIssue(error.issue);
      _logger.error(
        'playlist_import_failed',
        error: error.cause ?? error,
        stackTrace: error.stackTrace ?? stackTrace,
        context: {
          ...context,
          'source': error.issue.source.name,
          'kind': error.issue.kind.name,
          'retryable': error.issue.retryable,
        },
      );
      return false;
    } catch (error, stackTrace) {
      final issue = AppIssue(
        kind: error is FormatException
            ? AppIssueKind.playlistFormatInvalid
            : AppIssueKind.unknown,
        source: AppIssueSource.playlistImport,
        title: error is FormatException
            ? 'Playlist format invalid'
            : 'Import failed',
        message: error is FormatException
            ? 'The playlist could not be parsed.'
            : 'Could not load that playlist. Try again.',
        details: error.toString(),
      );
      _applyIssue(issue);
      _logger.error(
        'playlist_import_failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          ...context,
          'source': issue.source.name,
          'kind': issue.kind.name,
          'retryable': issue.retryable,
        },
      );
      return false;
    } finally {
      importProgress = null;
      notifyListeners();
    }
  }

  Future<bool> refreshPlaylist(String playlistId) async {
    if (refreshingPlaylistId != null) return false;

    final refreshesActivePlaylist = playlistId == activePlaylistId;
    refreshingPlaylistId = playlistId;
    errorMessage = null;
    activeIssue = null;
    notifyListeners();
    try {
      final refreshed = await loadPlaylist(
        playlistId,
        policy: CatalogLoadPolicy.networkOnly,
        activateScreen: false,
        updateActivePlaylist: refreshesActivePlaylist,
        updateActiveCatalog: refreshesActivePlaylist,
        logContext: {'source': 'manual_refresh'},
      );
      if (refreshed &&
          !refreshesActivePlaylist &&
          activePlaylistId == playlistId) {
        await loadPlaylist(
          playlistId,
          policy: CatalogLoadPolicy.cacheOnly,
          activateScreen: false,
          allowEmptyCatalog: true,
          logContext: {'source': 'manual_refresh_completed'},
        );
      }
      return refreshed;
    } finally {
      refreshingPlaylistId = null;
      notifyListeners();
    }
  }

  Future<bool> selectPlaylist(String playlistId) async {
    if (playlistId == activePlaylistId && catalogView.hasContent) {
      openHome();
      return true;
    }

    return loadPlaylist(
      playlistId,
      policy: CatalogLoadPolicy.cacheOnly,
      allowEmptyCatalog: true,
      logContext: {'source': 'playlist_selection'},
    );
  }

  Future<bool> deletePlaylist(String playlistId) async {
    await _settingsRepository.deletePlaylist(playlistId);
    await refreshPlaylists();
    if (activePlaylistId == playlistId) {
      activePlaylistId = null;
      await _settingsRepository.setAppSetting(_activePlaylistSettingKey, '');
      playlistUrl = null;
      catalogView.unbind();
      selectedSeries = null;
      selectedSeason = null;
      playlistStatus = LoadStatus.idle;
      if (playlists.isNotEmpty) {
        await loadPlaylist(
          playlists.first.playlistId,
          policy: CatalogLoadPolicy.cacheFirst,
        );
      } else {
        screen = AppScreen.home;
        notifyListeners();
      }
    }
    return true;
  }

  Future<void> _setActivePlaylist(String playlistId) async {
    activePlaylistId = playlistId;
    await _settingsRepository.setAppSetting(
      _activePlaylistSettingKey,
      playlistId,
    );
  }

  Future<void> retryActiveIssue({String? playlistInput}) async {
    final issue = activeIssue;
    if (issue == null || !issue.retryable) return;
    if (issue.source == AppIssueSource.playlistImport &&
        playlistInput != null) {
      await savePlaylist(playlistInput);
    }
  }

  void openCatalog(ContentType type) {
    if (type == ContentType.live) {
      openLiveTv();
      return;
    }
    openMovies();
  }

  void openHome() {
    screen = AppScreen.home;
    catalogType = null;
    selectedSeries = null;
    selectedSeason = null;
    notifyListeners();
  }

  void openLiveTv() {
    screen = AppScreen.liveCatalog;
    catalogType = ContentType.live;
    selectedSeries = null;
    selectedSeason = null;
    notifyListeners();
    catalogView.showItems(CatalogItemKind.live);
  }

  void openMovies() {
    screen = AppScreen.movieCatalog;
    catalogType = ContentType.vod;
    selectedSeries = null;
    selectedSeason = null;
    notifyListeners();
    catalogView.showItems(CatalogItemKind.movie);
  }

  void openSeries() {
    screen = AppScreen.seriesCatalog;
    catalogType = ContentType.vod;
    selectedSeason = null;
    notifyListeners();
    catalogView.showSeries();
  }

  void openSearch() {
    screen = AppScreen.search;
    notifyListeners();
  }

  void openSeriesSeasons(SeriesSummary series) {
    selectedSeries = series;
    selectedSeason = null;
    screen = AppScreen.seasonCatalog;
    notifyListeners();
    catalogView.showSeasons(series);
  }

  void openSeriesEpisodes(SeasonSummary season) {
    selectedSeason = season;
    screen = AppScreen.episodeCatalog;
    notifyListeners();
    catalogView.showEpisodes(season);
  }

  void openDetails(ContentItem item) {
    selectedItem = item;
    screen = AppScreen.details;
    notifyListeners();
  }

  /// Grids only carry summaries, so the full row is fetched on selection.
  Future<void> openDetailsById(String itemId) async {
    final item = await catalogView.itemById(itemId);
    if (item == null) return;
    openDetails(item);
  }

  Future<void> openPlayer() async {
    final item = selectedItem;
    if (item == null) return;
    await _openPlayerFor(item);
  }

  Future<void> openPlaybackSpike() async {
    selectedItem = playbackSpikeItem;
    await _openPlayerFor(playbackSpikeItem);
  }

  Future<void> _openPlayerFor(ContentItem item) async {
    screen = AppScreen.player;
    notifyListeners();
    try {
      await playbackAdapter.load(item);
      notifyListeners();
    } catch (_) {
      notifyListeners();
    }
  }

  void openSettings() {
    screen = AppScreen.settings;
    notifyListeners();
  }

  void goHome() {
    openHome();
  }

  void goBack() {
    switch (screen) {
      case AppScreen.home:
        return;
      case AppScreen.liveCatalog:
      case AppScreen.movieCatalog:
      case AppScreen.seriesCatalog:
      case AppScreen.search:
        openHome();
      case AppScreen.seasonCatalog:
        openSeries();
      case AppScreen.episodeCatalog:
        final selected = selectedSeries;
        if (selected != null) {
          openSeriesSeasons(selected);
          return;
        }
        openSeries();
      case AppScreen.details:
        if (selectedSeason != null) {
          screen = AppScreen.episodeCatalog;
        } else if (selectedSeries != null) {
          screen = AppScreen.seasonCatalog;
        } else {
          screen = switch (catalogType) {
            ContentType.live => AppScreen.liveCatalog,
            ContentType.vod => AppScreen.movieCatalog,
            null => AppScreen.home,
          };
        }
        notifyListeners();
      case AppScreen.player:
        screen = AppScreen.details;
        notifyListeners();
      case AppScreen.settings:
        screen = switch (activeNavItem) {
          PrimaryNavItem.home => AppScreen.home,
          PrimaryNavItem.liveTv => AppScreen.liveCatalog,
          PrimaryNavItem.movies => AppScreen.movieCatalog,
          PrimaryNavItem.series =>
            selectedSeason != null
                ? AppScreen.episodeCatalog
                : (selectedSeries != null
                      ? AppScreen.seasonCatalog
                      : AppScreen.seriesCatalog),
          PrimaryNavItem.search => AppScreen.search,
        };
        notifyListeners();
    }
  }

  /// Points the view state at the freshly imported playlist.
  ///
  /// The in-memory fallback exists only for repositories that cannot answer
  /// queries themselves (fixtures, plain M3U); it goes away with `load()`.
  Future<void> _bindCatalogView(String playlistId) async {
    if (_injectedQueryService == null &&
        _catalogRepository is! CatalogQueryService) {
      throw StateError(
        'A non-query catalog repository requires an injected query service.',
      );
    }
    final service = _queryService;
    if (service == null) return;
    await catalogView.bind(service: service, playlistId: playlistId);
  }

  bool _parseBoolOrDefault(String? value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'off':
        return false;
      default:
        return defaultValue;
    }
  }

  void _applyIssue(AppIssue issue) {
    activeIssue = issue;
    errorMessage = issue.message;
    playlistStatus = LoadStatus.error;
    notifyListeners();
  }

  @override
  void dispose() {
    catalogView.dispose();
    playbackAdapter.dispose();
    super.dispose();
  }
}
