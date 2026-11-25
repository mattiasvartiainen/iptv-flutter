import 'dart:convert';

import '../metadata/series_metadata.dart';
import 'xtream_authentication.dart';
import 'xtream_vod_metadata.dart';

class XtreamSeriesRequest {
  const XtreamSeriesRequest({
    required this.bytes,
    required this.action,
    required this.credentials,
    this.title,
    this.group,
    this.seriesId,
    this.episodeIds = const {},
  });
  final List<int> bytes;
  final String action;
  final XtreamCredentials credentials;
  final String? title;
  final String? group;
  final String? seriesId;
  final Set<String> episodeIds;
}

class XtreamSeriesResponse {
  const XtreamSeriesResponse({
    this.ids = const [],
    this.result,
    this.failure,
    this.retryAfter,
    this.episodeIds = const {},
  });
  final List<String> ids;
  final SeriesMetadataResult? result;
  final MetadataFailure? failure;
  final Duration? retryAfter;
  final Set<String> episodeIds;
}

String normalizeSeriesName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

XtreamSeriesResponse decodeXtreamSeries(XtreamSeriesRequest request) {
  final payload = jsonDecode(utf8.decode(request.bytes));
  if (payload is Map<String, dynamic>) {
    final user = payload['user_info'];
    if (user is Map && (user['auth'] == 0 || user['auth'] == '0')) {
      return const XtreamSeriesResponse(failure: MetadataFailure.denied);
    }
  }
  if (request.action != 'get_series_info') {
    if (payload is! List) {
      return const XtreamSeriesResponse(failure: MetadataFailure.malformed);
    }
    final ids = <String>{};
    for (final entry in payload) {
      if (entry is! Map<String, dynamic>) continue;
      final categories = request.action == 'get_series_categories';
      final name = entry[categories ? 'category_name' : 'name'];
      final id = positiveProviderId(
        entry[categories ? 'category_id' : 'series_id'],
      );
      if (name is String &&
          id != null &&
          normalizeSeriesName(name) ==
              normalizeSeriesName(
                categories ? request.group! : request.title!,
              )) {
        ids.add(id);
        if (ids.length > (categories ? 3 : 10)) {
          return const XtreamSeriesResponse(failure: MetadataFailure.unmapped);
        }
      }
    }
    return XtreamSeriesResponse(ids: ids.toList());
  }
  if (payload is! Map<String, dynamic> ||
      payload['info'] is! Map<String, dynamic> ||
      payload['episodes'] is! Map<String, dynamic>) {
    return const XtreamSeriesResponse(failure: MetadataFailure.malformed);
  }
  final info = payload['info'] as Map<String, dynamic>;
  final declaredId = info['series_id'] ?? payload['series_id'];
  if (declaredId != null &&
      positiveProviderId(declaredId) != request.seriesId) {
    return const XtreamSeriesResponse(failure: MetadataFailure.malformed);
  }
  final name = info['name'];
  if (name is! String ||
      normalizeSeriesName(name) != normalizeSeriesName(request.title!)) {
    return const XtreamSeriesResponse(failure: MetadataFailure.unmapped);
  }
  final episodeIds = <String>{};
  for (final season in (payload['episodes'] as Map<String, dynamic>).entries) {
    final number = int.tryParse(season.key);
    if (number == null || number < 0 || season.value is! List) {
      return const XtreamSeriesResponse(failure: MetadataFailure.malformed);
    }
    for (final episode in season.value as List) {
      if (episode is! Map<String, dynamic>) {
        return const XtreamSeriesResponse(failure: MetadataFailure.malformed);
      }
      final id = positiveProviderId(episode['id']);
      final ordinal = int.tryParse('${episode['episode_num']}');
      final seasonNumber = episode['season'] == null
          ? number
          : int.tryParse('${episode['season']}');
      if (id == null ||
          !episodeIds.add(id) ||
          ordinal == null ||
          ordinal < 0 ||
          seasonNumber != number) {
        return const XtreamSeriesResponse(failure: MetadataFailure.malformed);
      }
    }
  }
  if (request.episodeIds.isEmpty ||
      !request.episodeIds.every(episodeIds.contains)) {
    return const XtreamSeriesResponse(failure: MetadataFailure.unmapped);
  }
  final normalized = normalizeXtreamDescription({
    ...info,
    'movie_image': info['cover'],
    'releasedate': info['releaseDate'] ?? info['releasedate'] ?? info['release_date'],
    'duration_secs': null,
    'duration': null,
  }, request.credentials);
  return XtreamSeriesResponse(
    episodeIds: episodeIds,
    result: SeriesMetadataResult(
      metadata: normalized,
      providerSeriesId: request.seriesId,
    ),
  );
}
