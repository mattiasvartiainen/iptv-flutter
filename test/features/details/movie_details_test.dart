import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/features/details/movie_details_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/metadata/movie_metadata.dart';
import 'package:iptv_flutter/ui/widgets/media_artwork.dart';

import '../../support/app_harness.dart';

const movie = ContentItem(
  id: 'movie-one',
  title: 'Fixture Movie',
  type: ContentType.vod,
  streamUrl: 'https://fixture.test/movie.mp4',
  group: 'Movies',
  description: 'Imported synopsis.',
);

MovieMetadataResult enriched() => MovieMetadataResult(
  metadata: MovieMetadata(
    fields: {
      MovieMetadataField.plot: 'Provider synopsis with detailed information.',
      MovieMetadataField.releaseDate: '2025-01-02',
      MovieMetadataField.runtime: '120 min',
      MovieMetadataField.genres: 'Drama',
      MovieMetadataField.rating: '8.2/10 (Xtream)',
      MovieMetadataField.director: 'Fixture Director',
      MovieMetadataField.cast: 'First Actor, Second Actor',
    },
    sources: {for (final field in MovieMetadataField.values) field: 'xtream'},
  ),
);

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(800, 360),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('movie Details fits $size text $scale with local/API data', (
        tester,
      ) async {
        final repository = _Repository();
        addTearDown(repository.close);
        final harness = await pumpIptvApp(
          tester,
          size: size,
          textScale: scale,
          movieMetadataRepository: repository,
        );
        harness.controllers.app.openDetails(movie);
        await tester.pumpAndSettle();
        expect(find.text('Imported synopsis.'), findsOneWidget);
        expect(find.text('Loading movie information...'), findsOneWidget);
        final play = find.byWidgetPredicate(
          (widget) => widget is ElevatedButton,
        );
        expect(tester.widget<ElevatedButton>(play).onPressed, isNotNull);
        expect(tester.widget<ElevatedButton>(play).focusNode!.hasFocus, isTrue);
        final before = tester.widget<ElevatedButton>(play).focusNode;
        repository.requests.single.add(enriched());
        await tester.pumpAndSettle();
        expect(find.text('120 min'), findsOneWidget);
        expect(find.text('8.2/10 (Xtream)'), findsOneWidget);
        expect(find.text('Fixture Director'), findsOneWidget);
        expect(tester.widget<ElevatedButton>(play).focusNode, same(before));
        expect(before!.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
        // Validate playback separately from the existing compact player layout.
        tester.view.physicalSize = const Size(1440, 900);
        await tester.pumpAndSettle();
        tester.widget<ElevatedButton>(play).focusNode!.requestFocus();
        await tester.pump();
        await tester.ensureVisible(play);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          harness.controllers.app.navigationController.currentRoute,
          isA<PlayerRoute>(),
        );
        expect(
          harness.controllers.app.navigationController.stack
              .whereType<PlayerRoute>(),
          hasLength(1),
        );
        harness.controllers.app.goBack();
        await tester.pumpAndSettle();
        expect(
          harness.controllers.app.navigationController.currentRoute,
          isA<DetailsRoute>(),
        );
        expect(
          find.text('Provider synopsis with detailed information.'),
          findsOneWidget,
        );
      });
    }
  }

  for (final (label, size, sideBySide) in [
    ('compact', const Size(390, 844), false),
    ('wide', const Size(1440, 900), true),
    ('short landscape', const Size(1000, 360), false),
  ]) {
    testWidgets('$label Details lays out long local content and artwork', (
      tester,
    ) async {
      final harness = await pumpIptvApp(tester, size: size, textScale: 2);
      final title = List.filled(12, 'A long movie title').join(' ');
      final description = List.filled(30, 'A long synopsis.').join(' ');
      final item = ContentItem(
        id: 'long-movie',
        title: title,
        type: ContentType.vod,
        streamUrl: 'https://fixture.test/movie.mp4',
        group: '',
        description: description,
        logoUrl: 'https://example.invalid/portrait.png',
      );
      harness.controllers.app.openDetails(item);
      await tester.pumpAndSettle();
      final artwork = find.byType(MediaArtwork, skipOffstage: false);
      expect(tester.widget<MediaArtwork>(artwork).imageUrl, item.logoUrl);
      final play = find.byWidgetPredicate(
        (widget) => widget is ElevatedButton,
        skipOffstage: false,
      );
      expect(
        tester.widget<ElevatedButton>(play).focusNode!.hasPrimaryFocus,
        isTrue,
      );
      final viewport = find
          .ancestor(of: play, matching: find.byType(SingleChildScrollView))
          .first;
      expect(
        tester.getRect(viewport).contains(tester.getTopLeft(play)),
        isTrue,
      );
      expect(
        tester.getRect(play).bottom,
        lessThanOrEqualTo(tester.getRect(viewport).bottom),
      );
      expect(
        tester.getRect(play).right,
        lessThanOrEqualTo(tester.getRect(viewport).right),
      );
      final contentTitle = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text(title, skipOffstage: false),
        skipOffstage: false,
      );
      expect(contentTitle, findsOneWidget);
      final artworkRect = tester.getRect(artwork);
      final titleRect = tester.getRect(contentTitle);
      if (sideBySide) {
        expect(artworkRect.right, lessThan(titleRect.left));
      } else {
        expect(artworkRect.top, greaterThan(titleRect.bottom));
      }
      await tester.ensureVisible(find.text(description, skipOffstage: false));
      await tester.pumpAndSettle();
      expect(find.text(description), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(play).focusNode!.hasFocus, isFalse);
      tester.widget<ElevatedButton>(play).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(viewport).contains(tester.getTopLeft(play)),
        isTrue,
      );
      expect(
        tester.getRect(play).bottom,
        lessThanOrEqualTo(tester.getRect(viewport).bottom),
      );
      expect(
        tester.getRect(play).right,
        lessThanOrEqualTo(tester.getRect(viewport).right),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty group, description and artwork have local fallbacks', (
    tester,
  ) async {
    final harness = await pumpIptvApp(tester, size: const Size(390, 844));
    harness.controllers.app.openDetails(
      const ContentItem(
        id: 'empty-movie',
        title: 'No details',
        type: ContentType.vod,
        streamUrl: 'https://fixture.test/movie.mp4',
        group: '',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No description available yet.'), findsOneWidget);
    expect(
      tester.widget<MediaArtwork>(find.byType(MediaArtwork)).imageUrl,
      isNull,
    );
    expect(find.byIcon(Icons.ondemand_video), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('metadata failure has retry while Play remains usable', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.close);
    final harness = await pumpIptvApp(
      tester,
      movieMetadataRepository: repository,
    );
    harness.controllers.app.openDetails(movie);
    await tester.pumpAndSettle();
    repository.requests.single.add(
      const MovieMetadataResult(failure: MetadataFailure.network),
    );
    await tester.pumpAndSettle();
    expect(find.text('Imported synopsis.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      Focus.of(tester.element(find.text('Retry movie information'))).hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(repository.force.last, isTrue);
    repository.requests.last.add(enriched());
    await tester.pumpAndSettle();
    expect(find.text('120 min'), findsOneWidget);
    expect(find.text('Retry movie information'), findsNothing);
  });

  testWidgets('leaving for playback cancels loading and restarts on return', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.close);
    final harness = await pumpIptvApp(
      tester,
      size: const Size(1440, 900),
      movieMetadataRepository: repository,
    );
    harness.controllers.app.openDetails(movie);
    await tester.pumpAndSettle();
    final opening = harness.controllers.player.openPlayer(movie);
    await tester.pumpAndSettle();
    await opening;
    expect(repository.cancellations.first.isCancelled, isTrue);
    repository.requests.first.add(enriched());
    harness.controllers.app.goBack();
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(2));
    expect(find.text('120 min'), findsNothing);
    repository.requests.last.add(enriched());
    await tester.pumpAndSettle();
    expect(find.text('120 min'), findsOneWidget);
  });

  testWidgets('Back cancels metadata and restores originating movie focus', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.close);
    final harness = await pumpIptvApp(
      tester,
      movieMetadataRepository: repository,
    );
    harness.controllers.app.openMovies();
    await tester.pumpAndSettle();
    final titles = find.text('Northbound');
    expect(titles, findsOneWidget);
    await tester.tap(titles);
    await tester.pumpAndSettle();
    expect(
      harness.controllers.app.navigationController.currentRoute,
      isA<DetailsRoute>(),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      harness.controllers.app.navigationController.currentRoute,
      isA<CatalogRoute>(),
    );
    expect(repository.cancellations.single.isCancelled, isTrue);
    expect(find.text('Northbound'), findsOneWidget);
  });

  testWidgets('ordinary M3U and failed artwork have useful local Details', (
    tester,
  ) async {
    final harness = await pumpIptvApp(tester, size: const Size(360, 800));
    harness.controllers.app.openDetails(
      const ContentItem(
        id: 'plain',
        title: 'Plain movie',
        type: ContentType.vod,
        streamUrl: 'https://plain.example/stream.m3u8',
        group: 'Movies',
        posterUrl: 'https://images.example/missing.jpg',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No description available yet.'), findsOneWidget);
    expect(find.byType(MediaArtwork), findsOneWidget);
    expect(find.byIcon(Icons.ondemand_video), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'controller ignores cancelled requests and stale item completion',
    () async {
      final repository = _Repository();
      addTearDown(repository.close);
      final controller = MovieDetailsController(
        repository: repository,
        subject: const MovieMetadataSubject(playlistId: 'p', itemId: '42'),
      );
      controller.load();
      controller.load(forceRefresh: true);
      expect(repository.cancellations.first.isCancelled, isTrue);
      repository.requests.first.add(enriched());
      await Future<void>.delayed(Duration.zero);
      expect(controller.metadata, isNull);
      repository.requests.last.add(enriched());
      await Future<void>.delayed(Duration.zero);
      expect(controller.metadata![MovieMetadataField.runtime], '120 min');
      controller.dispose();
      expect(repository.cancellations.last.isCancelled, isTrue);
    },
  );
}

class _Repository implements MovieMetadataRepository {
  final requests = <StreamController<MovieMetadataResult>>[];
  final cancellations = <MetadataCancellation>[];
  final force = <bool>[];
  @override
  Stream<MovieMetadataResult> resolve(
    MovieMetadataSubject subject, {
    required MetadataCancellation cancellation,
    bool forceRefresh = false,
  }) {
    final controller = StreamController<MovieMetadataResult>();
    requests.add(controller);
    cancellations.add(cancellation);
    force.add(forceRefresh);
    return controller.stream;
  }

  void close() {
    for (final controller in requests) {
      unawaited(controller.close());
    }
  }
}
