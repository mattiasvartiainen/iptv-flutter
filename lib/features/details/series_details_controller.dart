import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/catalog/catalog_query.dart';
import '../../services/catalog/catalog_query_service.dart';
import '../../services/logging/app_logger.dart';
import '../../services/metadata/series_metadata.dart';
import '../../services/security/url_redaction.dart';
import '../../state/catalog_view_state.dart';

class SeriesDetailsController extends ChangeNotifier {
  SeriesDetailsController({
    required this.queries,
    required this.subject,
    this.repository,
    this.logger = const DebugAppLogger(),
  }) : episodes = PagedCollection(logger: logger);

  final CatalogQueryService queries;
  final SeriesMetadataSubject subject;
  final SeriesMetadataRepository? repository;
  final AppLogger logger;
  final PagedCollection<CatalogItemSummary> episodes;
  List<SeasonSummary> seasons = const [];
  SeasonSummary? selectedSeason;
  ContentMetadata? metadata;
  MetadataFailure? metadataFailure;
  bool loadingSeasons = true;
  bool seasonsFailed = false;
  bool loadingMetadata = false;
  bool staleMetadata = false;
  int _seasonGeneration = 0;
  int _metadataGeneration = 0;
  bool _disposed = false;
  MetadataCancellation? _cancellation;
  StreamSubscription<SeriesMetadataResult>? _subscription;

  Future<void> loadSeasons() async {
    final generation = ++_seasonGeneration;
    loadingSeasons = true;
    seasonsFailed = false;
    _notify();
    try {
      final loaded = await queries.seasons(subject.seriesId);
      if (_disposed || generation != _seasonGeneration) return;
      seasons = loaded;
    } catch (error, stackTrace) {
      if (_disposed || generation != _seasonGeneration) return;
      seasonsFailed = true;
      logger.error('series_seasons_load_failed',
        error: redactSensitiveText(error.toString()),
        stackTrace: StackTrace.fromString(redactSensitiveText(stackTrace.toString())));
    }
    loadingSeasons = false;
    _notify();
  }

  Future<void> selectSeason(SeasonSummary season) {
    if (_disposed || !seasons.contains(season)) return Future<void>.value();
    selectedSeason = season;
    episodes.clear();
    _notify();
    return episodes.load(
      (offset, limit) =>
          queries.episodes(season.id, offset: offset, limit: limit),
    );
  }

  void loadMetadata({bool forceRefresh = false}) {
    final service = repository;
    if (_disposed || service == null) return;
    suspendMetadata();
    final generation = ++_metadataGeneration;
    final cancellation = MetadataCancellation();
    _cancellation = cancellation;
    loadingMetadata = true;
    metadataFailure = null;
    _notify();
    _subscription = service
        .resolve(
          subject,
          cancellation: cancellation,
          forceRefresh: forceRefresh,
        )
        .listen(
          (result) {
            if (_disposed || generation != _metadataGeneration) return;
            metadata = result.metadata ?? metadata;
            metadataFailure = result.failure;
            loadingMetadata = result.isRefreshing;
            staleMetadata = result.isStale;
            _notify();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_disposed || generation != _metadataGeneration) return;
            metadataFailure = MetadataFailure.storage;
            loadingMetadata = false;
            logger.error('series_metadata_resolution_failed');
            _notify();
          },
          onDone: () {
            if (_disposed || generation != _metadataGeneration) return;
            loadingMetadata = false;
            _notify();
          },
        );
  }

  void suspendMetadata({bool clear = false}) {
    _metadataGeneration++;
    _cancellation?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    loadingMetadata = false;
    if (clear) {
      metadata = null;
      metadataFailure = null;
      staleMetadata = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _seasonGeneration++;
    suspendMetadata();
    episodes.dispose();
    super.dispose();
  }
}
