import 'package:flutter/foundation.dart';

import '../app/navigation/app_route.dart';
import '../app/navigation/navigation_controller.dart';
import '../services/catalog/catalog_import_worker.dart';
import '../services/catalog/catalog_query_service.dart';
import '../services/catalog/catalog_repository.dart';
import '../services/errors/app_issue.dart';
import '../services/errors/exception_diagnostics.dart';
import '../services/errors/playlist_issue_mapper.dart';
import '../services/logging/app_logger.dart';
import '../services/security/url_redaction.dart';
import '../services/settings/app_preferences.dart';
import '../services/settings/settings_repository.dart';
import '../services/sources/source_contracts.dart';
import '../services/sources/source_verifier.dart';
import 'app_preferences_controller.dart';
import 'catalog_view_state.dart';

enum LoadStatus { idle, loading, ready, error }

class _UnavailableSourceVerifier implements SourceVerifier {
  const _UnavailableSourceVerifier();

  @override
  Future<XtreamAuthResult> verify(
    PlaylistSourceConfig config, {
    required bool confirmed,
    required XtreamCancellation cancellation,
  }) async => const XtreamAuthResult(
    verification: SourceVerificationState.temporarilyUnavailable,
    failure: XtreamAuthFailure.unsupported,
  );
}

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
    SourceVerifier? sourceVerifier,
  }) : _catalogRepository = catalogRepository,
       _injectedQueryService = catalogQueryService,
       _settingsRepository = settingsRepository,
       _preferences = AppPreferences(settingsRepository: settingsRepository),
       _catalogView = catalogView,
       _navigationController = navigationController,
       _preferencesController = preferencesController,
       _logger = logger,
       _sourceVerifier = sourceVerifier {
    _queryService =
        _injectedQueryService ??
        (_catalogRepository is CatalogQueryService
            ? _catalogRepository as CatalogQueryService
            : null);
  }

  final CatalogRepository _catalogRepository;
  final CatalogQueryService? _injectedQueryService;
  final SettingsRepository _settingsRepository;
  final AppPreferences _preferences;
  final CatalogViewState _catalogView;
  final NavigationController _navigationController;
  final AppPreferencesController _preferencesController;
  final AppLogger _logger;
  final SourceVerifier? _sourceVerifier;

  SourceVerifier get sourceVerifier =>
      _sourceVerifier ?? const _UnavailableSourceVerifier();

  Future<bool> savePlaylistConfig(
    PlaylistSourceConfig config, {
    int? expectedRevision,
  }) async {
    return _runPlaylistOperation(
      'playlist_save',
      host: Uri.tryParse(config.server ?? config.url ?? '')?.host ?? '',
      body: () async {
        if (config.playlistId != null && expectedRevision != null) {
          final current = await _settingsRepository.getPlaylist(
            config.playlistId!,
          );
          if (current == null ||
              current.connectionRevision != expectedRevision) {
            throw StateError('Source changed while editing.');
          }
        }
        await _settingsRepository.upsertPlaylist(config);
        if (config.playlistId case final id?) _clearPlaylistIssue(id);
        await refreshPlaylists();
        errorMessage = null;
        activeIssue = null;
        playlistStatus = LoadStatus.ready;
        notifyListeners();
      },
    );
  }

  CatalogQueryService? _queryService;

  LoadStatus playlistStatus = LoadStatus.idle;
  String? playlistUrl;
  String? activePlaylistId;
  String? refreshingPlaylistId;
  String? errorMessage;
  List<ManagedPlaylist> playlists = const [];
  CatalogImportProgress? importProgress;
  AppIssue? activeIssue;
  String? _errorDiagnostics;
  String? _issuePlaylistId;
  final _playlistFailures = <String, ({AppIssue issue, String diagnostics})>{};
  final _playlistIssueOperations = <String, Object>{};

  String? get issuePlaylistId => _issuePlaylistId;

  AppIssue? issueForPlaylist(String playlistId) =>
      _playlistFailures[playlistId]?.issue;

  String? diagnosticsForPlaylist(String playlistId) =>
      verboseErrorsEnabled ? _playlistFailures[playlistId]?.diagnostics : null;

  bool get verboseErrorsEnabled => _preferencesController.verboseRefreshInfo;

  String? get errorDiagnostics =>
      verboseErrorsEnabled && errorMessage != null ? _errorDiagnostics : null;

  Future<void> initialize() async {
    await refreshPlaylists();
    final savedActivePlaylistId = await _preferences.activePlaylistId();
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
    final savedIds = playlists.map((playlist) => playlist.playlistId).toSet();
    for (final id in _playlistFailures.keys.toList()) {
      if (!savedIds.contains(id)) _clearPlaylistIssue(id);
    }
    if (playlists.isEmpty) {
      activePlaylistId = null;
      if (!_catalogView.hasContent) {
        _navigationController.resetTo(const HomeRoute());
      }
    }
    notifyListeners();
  }

  Future<bool> savePlaylistUrl({
    String? playlistId,
    required String name,
    required String url,
  }) async {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _errorDiagnostics = null;
      _applyIssue(
        const AppIssue(
          kind: AppIssueKind.invalidUrl,
          source: AppIssueSource.setup,
          title: 'Invalid playlist URL',
          message: 'Enter a valid playlist URL.',
        ),
      );
      return false;
    }

    return _runPlaylistOperation(
      'playlist_import',
      host: uri.host,
      body: () async {
        await _settingsRepository.upsertPlaylist(
          PlaylistSourceConfig.url(
            playlistId: playlistId,
            name: name.trim().isEmpty ? uri.host : name.trim(),
            url: normalized,
          ),
        );
        if (playlistId != null) _clearPlaylistIssue(playlistId);
        await refreshPlaylists();
        errorMessage = null;
        activeIssue = null;
        playlistStatus = LoadStatus.ready;
        notifyListeners();
      },
    );
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
      _errorDiagnostics = null;
      _applyIssue(
        const AppIssue(
          kind: AppIssueKind.invalidUrl,
          source: AppIssueSource.setup,
          title: 'Connection details missing',
          message: 'Enter the server, username, and password.',
        ),
      );
      return false;
    }

    final host = Uri.tryParse(normalizedServer)?.host ?? normalizedServer;
    return _runPlaylistOperation(
      'playlist_import',
      host: host,
      body: () async {
        await _settingsRepository.upsertPlaylist(
          PlaylistSourceConfig.xtream(
            playlistId: playlistId,
            name: name.trim().isEmpty ? host : name.trim(),
            server: normalizedServer,
            username: username.trim(),
            password: password,
          ),
        );
        if (playlistId != null) _clearPlaylistIssue(playlistId);
        await refreshPlaylists();
        errorMessage = null;
        activeIssue = null;
        playlistStatus = LoadStatus.ready;
        notifyListeners();
      },
    );
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
    _clearPlaylistIssue(playlistId);
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
      return await _runPlaylistOperation(
        'playlist_import',
        host: '',
        playlistId: playlistId,
        source: AppIssueSource.playlistImport,
        context: context,
        body: () async {
          final playlist = await _settingsRepository.getPlaylist(playlistId);
          if (playlist == null) {
            throw const AppIssueException(
              AppIssue(
                kind: AppIssueKind.storageUnavailable,
                source: AppIssueSource.playlistImport,
                title: 'Playlist unavailable',
                message: 'Playlist settings could not be found.',
              ),
            );
          }
          final resolvedUrl = await _settingsRepository.resolvePlaylistUrl(
            playlistId,
          );
          if (resolvedUrl == null || resolvedUrl.isEmpty) {
            throw const AppIssueException(
              AppIssue(
                kind: AppIssueKind.invalidUrl,
                source: AppIssueSource.playlistImport,
                title: 'Playlist source missing',
                message: 'Playlist source is missing.',
              ),
            );
          }
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
        },
      );
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
        return await loadPlaylist(
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
    _clearPlaylistIssue(playlistId);
    await refreshPlaylists();
    if (!deletesActivePlaylist) return true;

    activePlaylistId = null;
    await _preferences.setActivePlaylistId(null);
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

  Future<void> _setActivePlaylist(String playlistId) async {
    activePlaylistId = playlistId;
    await _preferences.setActivePlaylistId(playlistId);
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

  void _clearPlaylistIssue(String playlistId) {
    _playlistIssueOperations.remove(playlistId);
    _playlistFailures.remove(playlistId);
    if (_issuePlaylistId == playlistId) {
      activeIssue = null;
      errorMessage = null;
      _errorDiagnostics = null;
      _issuePlaylistId = null;
    }
  }

  void _applyIssue(AppIssue issue, {String? playlistId}) {
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
    _issuePlaylistId = playlistId;
    if (playlistId != null) {
      _playlistFailures[playlistId] = (
        issue: activeIssue!,
        diagnostics: _errorDiagnostics!,
      );
    }
    playlistStatus = LoadStatus.error;
    notifyListeners();
  }

  Future<bool> _runPlaylistOperation(
    String op, {
    required String host,
    required Future<void> Function() body,
    AppIssueSource source = AppIssueSource.setup,
    String? playlistId,
    Map<String, Object?> context = const {},
  }) async {
    _errorDiagnostics = null;
    _issuePlaylistId = null;
    final issueOperation = Object();
    if (playlistId != null) {
      _playlistIssueOperations[playlistId] = issueOperation;
    }
    try {
      await body();
      return true;
    } catch (error, stackTrace) {
      final isImport = source == AppIssueSource.playlistImport;
      final workerError = isImport && error is CatalogImportWorkerException
          ? error
          : null;
      final issue = playlistIssueFor(error, source: source);
      final loggedError = error is AppIssueException
          ? (error.cause ?? error).toString()
          : isImport && workerError == null
          ? error.toString()
          : null;
      final loggedStack = error is AppIssueException
          ? error.stackTrace ?? stackTrace
          : workerError != null && workerError.workerStackTrace.isNotEmpty
          ? StackTrace.fromString(workerError.workerStackTrace)
          : isImport
          ? stackTrace
          : null;
      if (playlistId == null ||
          identical(_playlistIssueOperations[playlistId], issueOperation)) {
        _errorDiagnostics = formatExceptionDiagnostics(error, stackTrace);
        _applyIssue(issue, playlistId: playlistId);
      }
      _logger.error(
        '${op}_failed',
        error: loggedError == null ? null : redactSensitiveText(loggedError),
        stackTrace: loggedStack == null
            ? null
            : StackTrace.fromString(
                redactSensitiveText(loggedStack.toString()),
              ),
        context: {
          ...context,
          'source': issue.source.name,
          'kind': issue.kind.name,
          if (!isImport) 'playlistHost': redactSensitiveText(host),
          if (workerError != null) 'workerErrorType': workerError.errorType,
          'retryable': issue.retryable,
        },
      );
      return false;
    } finally {
      if (playlistId != null &&
          identical(_playlistIssueOperations[playlistId], issueOperation)) {
        _playlistIssueOperations.remove(playlistId);
      }
    }
  }
}
