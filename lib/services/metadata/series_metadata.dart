import 'content_metadata.dart';

export 'content_metadata.dart'
    show
        ContentMetadata,
        ContentMetadataField,
        MetadataCancellation,
        MetadataFailure,
        safeArtworkUrl;

class SeriesMetadataSubject {
  const SeriesMetadataSubject({
    required this.playlistId,
    required this.seriesId,
    this.locale = 'en',
  });
  final String playlistId;
  final String seriesId;
  final String locale;
}

class SeriesMetadataResult {
  const SeriesMetadataResult({
    this.metadata,
    this.failure,
    this.providerSeriesId,
    this.isStale = false,
    this.isRefreshing = false,
    this.retryAfter,
  });
  final ContentMetadata? metadata;
  final MetadataFailure? failure;
  final String? providerSeriesId;
  final bool isStale;
  final bool isRefreshing;
  final Duration? retryAfter;
}

abstract interface class SeriesMetadataRepository {
  Stream<SeriesMetadataResult> resolve(
    SeriesMetadataSubject subject, {
    required MetadataCancellation cancellation,
    bool forceRefresh = false,
  });
}
