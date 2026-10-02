import 'package:flutter/foundation.dart';

import 'catalog_normalizer.dart';
import 'catalog_query.dart';

enum CatalogGroupKind { live, movie, series }

@immutable
class CatalogClassification {
  const CatalogClassification({
    required this.itemKind,
    required this.groupKind,
    this.episodeMatch,
    required this.reason,
  });

  final CatalogItemKind itemKind;
  final CatalogGroupKind groupKind;
  final SeriesEpisodeMatch? episodeMatch;
  final String reason;
}

/// Applies the target v8 classifier in strict priority order.
CatalogClassification classifyCatalogItem({
  required String streamUrl,
  required String groupTitle,
  required String title,
  String? providerType,
}) {
  final xtreamKind = _xtreamKind(streamUrl);
  if (xtreamKind != null) {
    final episodeMatch = CatalogNormalizer.parseSeriesEpisodeTitle(title);
    return switch (xtreamKind) {
      CatalogGroupKind.live => const CatalogClassification(
        itemKind: CatalogItemKind.live,
        groupKind: CatalogGroupKind.live,
        reason: 'xtream_live_path',
      ),
      CatalogGroupKind.movie => const CatalogClassification(
        itemKind: CatalogItemKind.movie,
        groupKind: CatalogGroupKind.movie,
        reason: 'xtream_movie_path',
      ),
      CatalogGroupKind.series => CatalogClassification(
        itemKind: CatalogItemKind.episode,
        groupKind: CatalogGroupKind.series,
        episodeMatch: episodeMatch,
        reason: 'xtream_series_path',
      ),
    };
  }

  final extensionKind = _extensionKind(streamUrl);
  if (extensionKind != null) {
    return _classificationFor(extensionKind, reason: 'url_extension');
  }

  final hints = [
    providerType,
    groupTitle,
  ].whereType<String>().map((value) => value.toLowerCase()).join(' ');
  if (_movieHint.hasMatch(hints)) {
    return const CatalogClassification(
      itemKind: CatalogItemKind.movie,
      groupKind: CatalogGroupKind.movie,
      reason: 'group_or_provider_hint',
    );
  }
  if (_seriesHint.hasMatch(hints)) {
    return CatalogClassification(
      itemKind: CatalogItemKind.episode,
      groupKind: CatalogGroupKind.series,
      episodeMatch: CatalogNormalizer.parseSeriesEpisodeTitle(title),
      reason: 'group_or_provider_hint',
    );
  }

  final episodeMatch = CatalogNormalizer.parseSeriesEpisodeTitle(title);
  if (episodeMatch != null) {
    return CatalogClassification(
      itemKind: CatalogItemKind.episode,
      groupKind: CatalogGroupKind.series,
      episodeMatch: episodeMatch,
      reason: 'episode_title',
    );
  }

  return const CatalogClassification(
    itemKind: CatalogItemKind.live,
    groupKind: CatalogGroupKind.live,
    reason: 'default_live',
  );
}

final RegExp _movieHint = RegExp(r'\b(vod|movie|movies|film|films)\b');
final RegExp _seriesHint = RegExp(r'\b(series|serie|tv show|tv shows)\b');

CatalogGroupKind? _xtreamKind(String streamUrl) {
  final uri = Uri.tryParse(streamUrl);
  if (uri == null) return null;
  for (final segment in uri.pathSegments) {
    switch (segment.toLowerCase()) {
      case 'live':
        return CatalogGroupKind.live;
      case 'movie':
        return CatalogGroupKind.movie;
      case 'series':
        return CatalogGroupKind.series;
    }
  }
  return null;
}

CatalogGroupKind? _extensionKind(String streamUrl) {
  final path = Uri.tryParse(streamUrl)?.path.toLowerCase() ?? '';
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  final extension = path.substring(dot + 1);
  if (const {
    'mp4',
    'mkv',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm',
  }.contains(extension)) {
    return CatalogGroupKind.movie;
  }
  if (const {'ts', 'm3u8'}.contains(extension)) {
    return CatalogGroupKind.live;
  }
  return null;
}

CatalogClassification _classificationFor(
  CatalogGroupKind kind, {
  required String reason,
}) => switch (kind) {
  CatalogGroupKind.live => CatalogClassification(
    itemKind: CatalogItemKind.live,
    groupKind: kind,
    reason: reason,
  ),
  CatalogGroupKind.movie => CatalogClassification(
    itemKind: CatalogItemKind.movie,
    groupKind: kind,
    reason: reason,
  ),
  CatalogGroupKind.series => CatalogClassification(
    itemKind: CatalogItemKind.episode,
    groupKind: kind,
    reason: reason,
  ),
};
