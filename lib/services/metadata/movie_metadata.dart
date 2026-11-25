import 'dart:async';

enum MovieMetadataField {
  title,
  plot,
  poster,
  backdrop,
  genres,
  releaseDate,
  runtime,
  cast,
  director,
  rating,
  tmdbId,
}

class MovieMetadata {
  MovieMetadata({
    Map<MovieMetadataField, String> fields = const {},
    Map<MovieMetadataField, String> sources = const {},
  }) : fields = Map.unmodifiable(fields),
       sources = Map.unmodifiable(sources);

  final Map<MovieMetadataField, String> fields;
  final Map<MovieMetadataField, String> sources;

  String? operator [](MovieMetadataField field) => fields[field];

  MovieMetadata fillMissing(MovieMetadata other) => MovieMetadata(
    fields: {...other.fields, ...fields},
    sources: {...other.sources, ...sources},
  );
}

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

enum MetadataFailure {
  unverified,
  unmapped,
  notMovie,
  notFound,
  unsupported,
  denied,
  malformed,
  rateLimited,
  network,
  timeout,
  cancelled,
  tooLarge,
  storage,
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

class MetadataCancellation {
  final _completion = Completer<void>();
  bool get isCancelled => _completion.isCompleted;
  Future<void> get whenCancelled => _completion.future;
  void cancel() {
    if (!isCancelled) _completion.complete();
  }
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

String? safeArtworkUrl(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  try {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.queryParameters.keys.any(
          (key) => RegExp(
            r'password|username|token|auth|key|signature|credential',
            caseSensitive: false,
          ).hasMatch(key),
        ) ||
        uri.pathSegments.any(
          const [
            'live',
            'movie',
            'series',
            'get.php',
            'player_api.php',
          ].contains,
        )) {
      return null;
    }
    return uri.toString();
  } on FormatException {
    return null;
  }
}
