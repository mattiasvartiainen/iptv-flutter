import 'dart:isolate';

import '../metadata/movie_metadata.dart';
import '../security/url_redaction.dart';
import 'bounded_xtream_json.dart';
import 'xtream_authentication.dart';

MovieMetadataResult decodeTransferredXtreamVod(
  (TransferableTypedData, String, XtreamCredentials) request,
) => decodeXtreamVodBytes((
  request.$1.materialize().asUint8List(), request.$2, request.$3,
));

MovieMetadataResult decodeXtreamVodBytes(
  (List<int>, String, XtreamCredentials) request,
) {
  final (bytes, id, credentials) = request;
  final payload = decodeBoundedXtreamJson(bytes);
  if (payload is! Map<String, dynamic>) {
    return const MovieMetadataResult(failure: MetadataFailure.malformed);
  }
  return normalizeXtreamVod(payload, id, credentials);
}

String? positiveProviderId(Object? value) {
  final text = value is int
      ? value.toString()
      : value is String
      ? value
      : null;
  if (text == null || !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(text)) {
    return null;
  }
  return text;
}

MovieMetadataResult normalizeXtreamVod(
  Map<String, dynamic> payload,
  String requestedId,
  XtreamCredentials credentials,
) {
  final movie = payload['movie_data'];
  final info = payload['info'];
  final user = payload['user_info'];
  if (user is Map<String, dynamic> &&
      (user['auth'] == 0 || user['auth'] == '0')) {
    return const MovieMetadataResult(failure: MetadataFailure.denied);
  }
  if (movie is! Map<String, dynamic> ||
      positiveProviderId(movie['stream_id']) != requestedId ||
      (movie['stream_type'] != null && movie['stream_type'] != 'movie') ||
      info is! Map<String, dynamic>) {
    return const MovieMetadataResult(failure: MetadataFailure.malformed);
  }
  return MovieMetadataResult(
    metadata: normalizeXtreamDescription(
      info,
      credentials,
      fallbackName: movie['name'],
    ),
  );
}

ContentMetadata normalizeXtreamDescription(
  Map<String, dynamic> info,
  XtreamCredentials credentials, {
  Object? fallbackName,
}) {
  final fields = <ContentMetadataField, String>{};
  String? text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        const [
          'null',
          'n/a',
          'na',
          'unknown',
          '0',
        ].contains(trimmed.toLowerCase()) ||
        trimmed.length > 16000) {
      return null;
    }
    // Provider descriptions can contain account echoes as well as URLs.
    return redactSensitiveText(trimmed)
        .replaceAll(credentials.username, '[redacted]')
        .replaceAll(credentials.password, '[redacted]')
        .replaceAll(Uri.encodeComponent(credentials.username), '[redacted]')
        .replaceAll(Uri.encodeComponent(credentials.password), '[redacted]');
  }

  void put(MovieMetadataField field, List<Object?> values) {
    for (final value in values) {
      final normalized = text(value);
      if (normalized != null) {
        fields[field] = normalized;
        return;
      }
    }
  }

  void artwork(MovieMetadataField field, Object? value) {
    if (value is! String ||
        value.contains(credentials.username) ||
        value.contains(credentials.password)) {
      return;
    }
    final normalized = safeArtworkUrl(value);
    if (normalized != null) fields[field] = normalized;
  }

  put(MovieMetadataField.title, [info['name'], fallbackName]);
  put(MovieMetadataField.plot, [info['plot'], info['description']]);
  put(MovieMetadataField.genres, [info['genre']]);
  put(MovieMetadataField.cast, [info['cast'], info['actors']]);
  put(MovieMetadataField.director, [info['director']]);
  final date = text(info['releasedate'] ?? info['release_date']);
  final parsedDate = date == null ? null : DateTime.tryParse(date);
  if (date != null &&
      RegExp(r'^\d{4}(?:-\d{2}-\d{2})?$').hasMatch(date) &&
      (date.length == 4 ||
          (parsedDate != null &&
              parsedDate.toIso8601String().startsWith(date)))) {
    fields[MovieMetadataField.releaseDate] = date;
  }
  final seconds = int.tryParse('${info['duration_secs']}');
  if (seconds != null && seconds > 0 && seconds <= 86400) {
    fields[MovieMetadataField.runtime] = '${(seconds / 60).ceil()} min';
  } else {
    final duration = text(info['duration']);
    if (duration != null &&
        RegExp(r'^\d{1,2}:[0-5]\d:[0-5]\d$').hasMatch(duration)) {
      fields[MovieMetadataField.runtime] = duration;
    }
  }
  final rating = num.tryParse('${info['rating']}');
  if (rating != null && rating.isFinite && rating > 0 && rating <= 10) {
    fields[MovieMetadataField.rating] = '$rating/10 (Xtream)';
  }
  final tmdb = positiveProviderId(info['tmdb_id']);
  if (tmdb != null) fields[MovieMetadataField.tmdbId] = tmdb;
  artwork(MovieMetadataField.poster, info['movie_image']);
  if (!fields.containsKey(MovieMetadataField.poster)) {
    artwork(MovieMetadataField.poster, info['cover_big']);
  }
  final backdrops = info['backdrop_path'];
  if (backdrops is List) {
    for (final image in backdrops.take(10)) {
      artwork(MovieMetadataField.backdrop, image);
      if (fields.containsKey(MovieMetadataField.backdrop)) break;
    }
  } else {
    artwork(MovieMetadataField.backdrop, backdrops);
  }
  return ContentMetadata(
    fields: fields,
    sources: {for (final field in fields.keys) field: 'xtream'},
  );
}
