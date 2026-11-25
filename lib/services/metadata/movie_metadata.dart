import 'content_metadata.dart';

export 'content_metadata.dart';

typedef MovieMetadataField = ContentMetadataField;
typedef MovieMetadata = ContentMetadata;

class MovieMetadataSubject {
  const MovieMetadataSubject({
    required this.playlistId,
    required this.itemId,
    this.locale = 'en',
    this.connectionRevision = 0,
    this.providerMovieId,
  });

  final String playlistId;
  final String itemId;
  final String locale;
  final int connectionRevision;
  final String? providerMovieId;
}

class MovieMetadataResult {
  const MovieMetadataResult({
    this.metadata,
    this.failure,
    this.isStale = false,
    this.isRefreshing = false,
    this.retryAfter,
  });

  final MovieMetadata? metadata;
  final MetadataFailure? failure;
  final bool isStale;
  final bool isRefreshing;
  final Duration? retryAfter;
}

abstract interface class MovieMetadataProvider {
  String get id;
  bool supports(MovieMetadataSubject subject);
  Future<MovieMetadataResult> fetch(
    MovieMetadataSubject subject,
    MetadataCancellation cancellation,
  );
}

abstract interface class MovieMetadataRepository {
  Stream<MovieMetadataResult> resolve(
    MovieMetadataSubject subject, {
    required MetadataCancellation cancellation,
    bool forceRefresh = false,
  });
}
