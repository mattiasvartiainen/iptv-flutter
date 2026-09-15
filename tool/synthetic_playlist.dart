import 'dart:math';

/// Generates a synthetic but realistic M3U playlist for load-testing the
/// download/parse/import pipeline (see docs/improvements-1.md perf notes).
///
/// The mix of live channels, movies, and series episodes exercises every
/// reconcile path (categories/series/seasons/episodes), not just flat
/// media_items rows.
String generateSyntheticPlaylist({
  required int itemCount,
  int seed = 42,
  double liveFraction = 0.2,
  double seriesFraction = 0.5,
  int categoryCount = 40,
  String urlPrefix = 'https://example.invalid',
}) {
  final random = Random(seed);
  final buffer = StringBuffer('#EXTM3U\n');
  final categories = List.generate(categoryCount, (i) => 'Category $i');
  final seriesCount = (itemCount / 40).ceil().clamp(10, 5000);
  final seriesTitles = List.generate(seriesCount, (i) => 'Series $i');

  for (var i = 0; i < itemCount; i++) {
    final roll = random.nextDouble();
    final group = categories[random.nextInt(categories.length)];

    if (roll < liveFraction) {
      buffer.writeln(
        '#EXTINF:-1 tvg-id="live-$i" tvg-name="Live Channel $i" '
        'tvg-logo="$urlPrefix/logo/$i.png" group-title="$group",Live Channel $i',
      );
      buffer.writeln('$urlPrefix/live/stream-$i.m3u8');
    } else if (roll < liveFraction + seriesFraction) {
      final series = seriesTitles[random.nextInt(seriesTitles.length)];
      final season = random.nextInt(10) + 1;
      final episode = random.nextInt(24) + 1;
      final seasonPadded = season.toString().padLeft(2, '0');
      final episodePadded = episode.toString().padLeft(2, '0');
      buffer.writeln(
        '#EXTINF:-1 tvg-id="ep-$i" group-title="$group",'
        '$series S${seasonPadded}E$episodePadded',
      );
      buffer.writeln('$urlPrefix/series/episode-$i.m3u8');
    } else {
      buffer.writeln(
        '#EXTINF:-1 tvg-id="vod-$i" group-title="$group",Movie Title $i',
      );
      buffer.writeln('$urlPrefix/vod/movie-$i.m3u8');
    }
  }

  return buffer.toString();
}

/// Rewrites [original] so a fixed [churnFraction] of entries look different
/// (title changed) while the rest are byte-identical. Used to benchmark a
/// "warm refresh" where most rows are unchanged. Note: since title feeds
/// every identity strategy (id/provider-hash/signature), a churned row is
/// reconciled as delete+insert rather than update-in-place — a pessimistic
/// but useful stress case for the "some rows changed" refresh path.
String churnSyntheticPlaylist(
  String original, {
  double churnFraction = 0.05,
  int seed = 7,
}) {
  final random = Random(seed);
  final lines = original.split('\n');
  final result = StringBuffer();

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('#EXTINF') && random.nextDouble() < churnFraction) {
      result.writeln('$line [updated]');
    } else {
      result.writeln(line);
    }
  }

  return result.toString();
}
