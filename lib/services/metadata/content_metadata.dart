import 'dart:async';

enum ContentMetadataField {
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

class ContentMetadata {
  ContentMetadata({
    Map<ContentMetadataField, String> fields = const {},
    Map<ContentMetadataField, String> sources = const {},
  }) : fields = Map.unmodifiable(fields),
       sources = Map.unmodifiable(sources);

  final Map<ContentMetadataField, String> fields;
  final Map<ContentMetadataField, String> sources;
  String? operator [](ContentMetadataField field) => fields[field];

  ContentMetadata fillMissing(ContentMetadata other) => ContentMetadata(
    fields: {...other.fields, ...fields},
    sources: {...other.sources, ...sources},
  );
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

class MetadataCancellation {
  final _completion = Completer<void>();
  bool get isCancelled => _completion.isCompleted;
  Future<void> get whenCancelled => _completion.future;
  void cancel() {
    if (!isCancelled) _completion.complete();
  }
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
          const ['live', 'movie', 'series', 'get.php', 'player_api.php'].contains,
        )) {
      return null;
    }
    return uri.toString();
  } on FormatException {
    return null;
  }
}
