import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/ui/widgets/media_artwork.dart';

import '../../support/visual_fixture_http.dart';

void main() {
  late Uint8List oversizedImage;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 1280, 720),
      Paint()..color = const Color(0xff4385a0),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(1280, 720);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode artwork fixture.');
    oversizedImage = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    image.dispose();
    picture.dispose();
  });

  void artworkTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      installVisualFixtureHttp(extraImages: {'/large.png': oversizedImage});
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final semantics = tester.ensureSemantics();
      try {
        await body(tester);
      } finally {
        semantics.dispose();
        uninstallVisualFixtureHttp();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
    });
  }

  Future<void> pumpArtwork(
    WidgetTester tester, {
    required Size size,
    String? url,
    BoxFit fit = BoxFit.contain,
    int decodeWidth = 320,
    int decodeHeight = 480,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Semantics(
              container: true,
              label: 'Artwork container',
              child: SizedBox.fromSize(
                size: size,
                child: MediaArtwork(
                  imageUrl: url,
                  fit: fit,
                  decodeWidth: decodeWidth,
                  decodeHeight: decodeHeight,
                  fallbackIcon: Icons.movie,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (
      var attempt = 0;
      attempt < 100 && finder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(finder, findsOneWidget);
  }

  for (final (label, image, size, fit, decodeWidth, decodeHeight) in [
    ('poster', 'portrait', const Size(160, 240), BoxFit.contain, 320, 480),
    ('landscape', 'landscape', const Size(320, 180), BoxFit.cover, 640, 360),
    ('logo', 'portrait', const Size(48, 48), BoxFit.contain, 640, 360),
  ]) {
    artworkTest('$label fits bounded decorative artwork', (tester) async {
      await pumpArtwork(
        tester,
        size: size,
        url: 'https://example.invalid/$image.png',
        fit: fit,
        decodeWidth: decodeWidth,
        decodeHeight: decodeHeight,
      );
      final widget = tester.widget<Image>(find.byType(Image));
      final provider = widget.image as ResizeImage;
      expect(provider.width, decodeWidth);
      expect(provider.height, decodeHeight);
      expect(widget.fit, fit);
      expect(widget.excludeFromSemantics, isTrue);
      final before = tester.getSize(find.byType(MediaArtwork));
      final raw = find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image != null,
      );
      await waitFor(tester, raw);
      final rendered = tester.widget<RawImage>(raw);
      expect(rendered.fit, fit);
      expect(rendered.image!.width, lessThanOrEqualTo(decodeWidth));
      expect(rendered.image!.height, lessThanOrEqualTo(decodeHeight));
      expect(
        rendered.image!.width / rendered.image!.height,
        closeTo(image == 'portrait' ? 0.5 : 2, 0.05),
      );
      expect(tester.getSize(find.byType(MediaArtwork)), before);
      expect(before, size);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Artwork container')),
        matchesSemantics(label: 'Artwork container'),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  artworkTest('absent and failed images retain fallback and geometry', (
    tester,
  ) async {
    const size = Size(160, 240);
    for (final url in [null, '   ', 'https://example.invalid/missing.png']) {
      await pumpArtwork(tester, size: size, url: url);
      if (url != null && url.isNotEmpty && url.trim().isNotEmpty) {
        var failed = false;
        final stream = tester
            .widget<Image>(find.byType(Image))
            .image
            .resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (_, _) {},
          onError: (Object error, StackTrace? stackTrace) => failed = true,
        );
        stream.addListener(listener);
        try {
          for (var attempt = 0; attempt < 100 && !failed; attempt++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(failed, isTrue);
        } finally {
          stream.removeListener(listener);
        }
      }
      await waitFor(tester, find.byIcon(Icons.movie));
      expect(tester.getSize(find.byType(MediaArtwork)), size);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Artwork container')),
        matchesSemantics(label: 'Artwork container'),
      );
      expect(tester.takeException(), isNull);
    }
  });

  artworkTest('loading uses the same fallback until the image is ready', (
    tester,
  ) async {
    await pumpArtwork(
      tester,
      size: const Size(160, 240),
      url: 'https://example.invalid/portrait.png',
    );
    final image = tester.widget<Image>(find.byType(Image));
    const child = Text('loaded');
    final context = tester.element(find.byType(Image));
    final loading = image.loadingBuilder!(
      context,
      child,
      const ImageChunkEvent(cumulativeBytesLoaded: 1, expectedTotalBytes: 2),
    );
    expect(loading, isA<Icon>());
    expect((loading as Icon).icon, Icons.movie);
    expect(image.loadingBuilder!(context, child, null), same(child));
    await waitFor(
      tester,
      find.byWidgetPredicate((w) => w is RawImage && w.image != null),
    );
  });

  artworkTest('oversized source is decoded within the requested bounds', (
    tester,
  ) async {
    await pumpArtwork(
      tester,
      size: const Size(320, 180),
      url: 'https://example.invalid/large.png',
      decodeWidth: 320,
      decodeHeight: 180,
    );
    final raw = find.byWidgetPredicate(
      (widget) => widget is RawImage && widget.image != null,
    );
    await waitFor(tester, raw);
    final image = tester.widget<RawImage>(raw).image!;
    expect(image.width, 320);
    expect(image.height, 180);
    expect(tester.takeException(), isNull);
  });
}
