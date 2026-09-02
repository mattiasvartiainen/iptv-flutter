class SeriesEpisodeMatch {
  const SeriesEpisodeMatch({
    required this.seriesTitle,
    required this.seasonNumber,
    required this.episodeNumber,
  });

  final String seriesTitle;
  final int seasonNumber;
  final int episodeNumber;
}

class CatalogNormalizer {
  const CatalogNormalizer._();

  static final RegExp seriesEpisodePattern = RegExp(
    r'^(.*?)\s+[sS](\d{1,2})\s*[eE](\d{1,3})(?:\b|\D.*)$',
  );

  static String canonicalGroup(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Uncategorized' : trimmed;
  }

  static String normalizeText(String value) => value.toLowerCase().trim();

  static SeriesEpisodeMatch? parseSeriesEpisodeTitle(String title) {
    final match = seriesEpisodePattern.firstMatch(title);
    if (match == null) return null;

    final seriesTitle = (match.group(1) ?? '').trim();
    final seasonNumber = int.tryParse(match.group(2) ?? '');
    final episodeNumber = int.tryParse(match.group(3) ?? '');
    if (seriesTitle.isEmpty ||
        seasonNumber == null ||
        seasonNumber <= 0 ||
        episodeNumber == null ||
        episodeNumber <= 0) {
      return null;
    }

    return SeriesEpisodeMatch(
      seriesTitle: seriesTitle,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
  }

  static String mediaSignature({
    required String streamUrl,
    required String title,
    required int sourceIndex,
  }) {
    return '$streamUrl|$title|$sourceIndex';
  }

  static String providerItemHash({
    required String streamUrl,
    required String title,
    required String group,
  }) {
    return '$streamUrl|$title|$group';
  }
}
