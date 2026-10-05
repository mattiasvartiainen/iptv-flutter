import 'package:flutter/foundation.dart';

import '../app/navigation/app_route.dart';
import '../app/navigation/navigation_controller.dart';
import '../services/catalog/catalog_import_worker.dart';
import '../services/catalog/catalog_query_service.dart';
import '../services/catalog/catalog_repository.dart';
import '../services/errors/app_issue.dart';
import '../services/logging/app_logger.dart';
import '../services/security/url_redaction.dart';
import '../services/settings/settings_repository.dart';
import 'app_preferences_controller.dart';
import 'catalog_view_state.dart';

enum LoadStatus { idle, loading, ready, error }

enum PlaylistLoadIntent {
  startup,
  activate,
  refreshActive,
  refreshInactive,
  setup,
  activateNext,
  refreshCompleted,
}

class PlaylistsController extends ChangeNotifier {
  PlaylistsController({
    required CatalogRepository catalogRepository,
    CatalogQueryService? catalogQueryService,
    required SettingsRepository settingsRepository,
    required CatalogViewState catalogView,
    required NavigationController navigationController,
    required AppPreferencesController preferencesController,
    AppLogger logger = const DebugAppLogger(),
  }) : _catalogRepository = catalogRepository,
       _injectedQueryService = catalogQueryService,
       _settingsRepository = settingsRepository,
       _catalogView = catalogView,
       _navigationController = navigationController,
       _preferencesController = preferencesController,
       _logger = logger {
    _queryService =
        _injectedQueryService ??
        (_catalogRepository is CatalogQueryService
            ? _catalogRepository as CatalogQueryService
            : null);
  }

  final CatalogRepository _catalogRepository;
  final CatalogQueryService? _injectedQueryService;
  final SettingsRepository _settingsRepository;
  final CatalogViewState _catalogView;
  final NavigationController _navigationController;
  final AppPreferencesController _preferencesController;
  final AppLogger _logger;

  CatalogQueryService? _queryService;

  LoadStatus playlistStatus = LoadStatus.idle;
  String? playlistUrl;
  String? activePlaylistId;
  String? refreshingPlaylistId;
  String? errorMessage;
  List<ManagedPlaylist> playlists = const [];
  CatalogImportProgress? importProgress;
  AppIssue? activeIssue;

  static const _activePlaylistSettingKey = 'active_playlist_id';

  Future<void> initialize() async {
    await refreshPlaylists();
    final savedActivePlaylistId = await _settingsRepository.getAppSetting(
      _activePlaylistSettingKey,
    );
    final initialPlaylist = playlists
        .where((playlist) => playlist.playlistId == savedActivePlaylistId)
        .firstOrNull;
    if (initialPlaylist != null && !_catalogView.hasContent) {
      await loadPlaylist(
        initialPlaylist.playlistId,
        intent: PlaylistLoadIntent.startup,
      );
    }
  }

  Future<void> refreshPlaylists() async {
    playlists = await _settingsRepository.listPlaylists();
    if (playlists.isEmpty) {
      activePlaylistId = null;
      if (!_catalogView.hasContent) {
        _navigationController.resetTo(const HomeRoute());
      }
    }
    notifyListeners();
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
        intent: PlaylistLoadIntent.setup,
        logContext: {'source': 'setup', 'playlistHost': uri.host},
      );
      if (!loaded) return false;
      _logger.info(
        'playlist_import_succeeded',
        context: {
          'source': 'setup',
          'playlistHost': uri.host,
          'items': _catalogView.itemCount,
        },
      );
      notifyListeners();
      return true;
    } on AppIssueException catch (error, stackTrace) {
      _applyIssue(error.issue);
      _logger.error(
        'playlist_import_failed',
        error: redactSensitiveText((error.cause ?? error).toString()),
        stackTrace: StackTrace.fromString(
          redactSensitiveText((error.stackTrace ?? stackTrace).toString()),
        ),
        context: {
          'source': error.issue.source.name,
          'kind': error.issue.kind.name,
          'playlistHost': uri.host,
          'retryable': error.issue.retryable,
        },
      );
      return false;
    } catch (_) {
      const issue = AppIssue(
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
      _logSaveFailure(error, stackTrace, uri.host);
      return false;
    } catch (_) {
      _applyGenericSetupIssue(uri.host);
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

    final host = Uri.tryParse(normalizedServer)?.host ?? normalizedServer;
    try {
      await _settingsRepository.upsertPlaylist(
        PlaylistSourceConfig.xtream(
          playlistId: playlistId,
          name: name.trim().isEmpty ? host : name.trim(),
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
      _logSaveFailure(error, stackTrace, host);
      return false;
    } catch (_) {
      _applyGenericSetupIssue(host);
      return false;
    }
  }

  Future<bool> loadPlaylist(
    String playlistId, {
    required PlaylistLoadIntent intent,
    Map<String, Object?>? logContext,
  }) async {
    final policy = switch (intent) {
      PlaylistLoadIntent.startup ||
      PlaylistLoadIntent.activate ||
      PlaylistLoadIntent.refreshCompleted => CatalogLoadPolicy.cacheOnly,
      PlaylistLoadIntent.activateNext => CatalogLoadPolicy.cacheFirst,
      PlaylistLoadIntent.setup ||
      PlaylistLoadIntent.refreshActive ||
      PlaylistLoadIntent.refreshInactive => CatalogLoadPolicy.networkOnly,
    };
    final allowEmptyCatalog =
        intent == PlaylistLoadIntent.startup ||
        intent == PlaylistLoadIntent.activate ||
        intent == PlaylistLoadIntent.refreshCompleted;
    final updatesActiveCatalog = intent != PlaylistLoadIntent.refreshInactive;
    final activateScreen =
        intent == PlaylistLoadIntent.startup ||
        intent == PlaylistLoadIntent.activate ||
        intent == PlaylistLoadIntent.activateNext ||
        intent == PlaylistLoadIntent.setup;
    final playlist = await _settingsRepository.getPlaylist(playlistId);
    if (playlist == null) {
      errorMessage = 'Playlist settings could not be found.';
      playlistStatus = LoadStatus.error;
      notifyListeners();
      return false;
    }

    final resolvedUrl = await _settingsRepository.resolvePlaylistUrl(
      playlistId,
    );
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
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
    DateTime? lastProgressNotifyAt;
    const minProgressNotifyGap = Duration(milliseconds: 200);

    try {
      final result = await _catalogRepository.load(
        playlistUrl: resolvedUrl,
        playlistId: playlistId,
        playlistName: playlist.name,
        policy: policy,
        onProgress: _preferencesController.verboseRefreshInfo
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

      if (updatesActiveCatalog) {
        playlistUrl = resolvedUrl;
        await _setActivePlaylist(playlistId);
      }
      if (updatesActiveCatalog) await _bindCatalogView(playlistId);
      await _preferencesController.refreshHomeSectionVisibility();
      await refreshPlaylists();
      playlistStatus = LoadStatus.ready;
      if (activateScreen) _navigationController.resetTo(const HomeRoute());
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
        error: redactSensitiveText((error.cause ?? error).toString()),
        stackTrace: StackTrace.fromString(
          redactSensitiveText((error.stackTrace ?? stackTrace).toString()),
        ),
        context: {
          ...context,
          'source': error.issue.source.name,
          'kind': error.issue.kind.name,
          'retryable': error.issue.retryable,
        },
      );
      return false;
    } on CatalogImportWorkerException catch (error, stackTrace) {
      final authorizationFailure =
          error.errorType == 'HttpException' &&
          RegExp(r'\b(?:401|403)\b').hasMatch(error.message);
      final kind = switch (error.errorType) {
        'TimeoutException' => AppIssueKind.timeout,
        'SocketException' => AppIssueKind.networkUnavailable,
        'HttpException' when authorizationFailure =>
          AppIssueKind.authorizationFailure,
        _ => AppIssueKind.unknown,
      };
      final issue = AppIssue(
        kind: kind,
        source: AppIssueSource.playlistImport,
        title: switch (kind) {
          AppIssueKind.timeout => 'Playlist request timed out',
          AppIssueKind.networkUnavailable => 'Network unavailable',
          AppIssueKind.authorizationFailure => 'Access denied',
          _ => 'Import failed',
        },
        message: switch (kind) {
          AppIssueKind.timeout =>
            'The playlist server took too long to respond.',
          AppIssueKind.networkUnavailable =>
            'Could not connect to the playlist server.',
          AppIssueKind.authorizationFailure =>
            'The playlist server rejected the request.',
          _ => 'Could not load that playlist. Try again.',
        },
      );
      _applyIssue(issue);
      _logger.error(
        'playlist_import_failed',
        stackTrace: error.workerStackTrace.isEmpty
            ? stackTrace
            : StackTrace.fromString(error.workerStackTrace),
        context: {
          ...context,
          'source': issue.source.name,
          'kind': issue.kind.name,
          'workerErrorType': error.errorType,
          'retryable': issue.retryable,
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
        details: redactSensitiveText(error.toString()),
      );
      _applyIssue(issue);
      _logger.error(
        'playlist_import_failed',
        error: redactSensitiveText(error.toString()),
        stackTrace: StackTrace.fromString(
          redactSensitiveText(stackTrace.toString()),
        ),
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
        intent: refreshesActivePlaylist
            ? PlaylistLoadIntent.refreshActive
            : PlaylistLoadIntent.refreshInactive,
        logContext: {'source': 'manual_refresh'},
      );
      if (refreshed &&
          !refreshesActivePlaylist &&
          activePlaylistId == playlistId) {
        await loadPlaylist(
          playlistId,
          intent: PlaylistLoadIntent.refreshCompleted,
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
    if (playlistId == activePlaylistId && _catalogView.hasContent) {
      _navigationController.resetTo(const HomeRoute());
      return true;
    }
    return loadPlaylist(
      playlistId,
      intent: PlaylistLoadIntent.activate,
      logContext: {'source': 'playlist_selection'},
    );
  }

  Future<bool> deletePlaylist(String playlistId) async {
    final deletesActivePlaylist = activePlaylistId == playlistId;
    await _settingsRepository.deletePlaylist(playlistId);
    await refreshPlaylists();
    if (!deletesActivePlaylist) return true;

    activePlaylistId = null;
    await _settingsRepository.setAppSetting(_activePlaylistSettingKey, '');
    playlistUrl = null;
    _catalogView.unbind();
    playlistStatus = LoadStatus.idle;
    if (playlists.isNotEmpty) {
      await loadPlaylist(
        playlists.first.playlistId,
        intent: PlaylistLoadIntent.activateNext,
      );
    } else {
      _navigationController.resetTo(const HomeRoute());
      notifyListeners();
    }
    return true;
  }

  Future<void> retryActiveIssue({String? playlistInput}) async {
    final issue = activeIssue;
    if (issue == null || !issue.retryable) return;
    if (issue.source == AppIssueSource.playlistImport &&
        playlistInput != null) {
      await savePlaylist(playlistInput);
    }
  }

  Future<void> _setActivePlaylist(String playlistId) async {
    activePlaylistId = playlistId;
    await _settingsRepository.setAppSetting(
      _activePlaylistSettingKey,
      playlistId,
    );
  }

  Future<void> _bindCatalogView(String playlistId) async {
    if (_injectedQueryService == null &&
        _catalogRepository is! CatalogQueryService) {
      throw StateError(
        'A non-query catalog repository requires an injected query service.',
      );
    }
    final service = _queryService;
    if (service == null) return;
    await _catalogView.bind(service: service, playlistId: playlistId);
  }

  void _applyIssue(AppIssue issue) {
    activeIssue = AppIssue(
      kind: issue.kind,
      source: issue.source,
      title: issue.title,
      message: redactSensitiveText(issue.message),
      details: issue.details == null
          ? null
          : redactSensitiveText(issue.details!),
      retryable: issue.retryable,
    );
    errorMessage = activeIssue!.message;
    playlistStatus = LoadStatus.error;
    notifyListeners();
  }

  void _applyGenericSetupIssue(String host) {
    const issue = AppIssue(
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
        'playlistHost': host,
        'retryable': issue.retryable,
      },
    );
  }

  void _logSaveFailure(
    AppIssueException error,
    StackTrace stackTrace,
    String host,
  ) {
    _applyIssue(error.issue);
    _logger.error(
      'playlist_import_failed',
      error: redactSensitiveText((error.cause ?? error).toString()),
      stackTrace: StackTrace.fromString(
        redactSensitiveText((error.stackTrace ?? stackTrace).toString()),
      ),
      context: {
        'source': error.issue.source.name,
        'kind': error.issue.kind.name,
        'playlistHost': host,
        'retryable': error.issue.retryable,
      },
    );
  }
}
