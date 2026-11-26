import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/features/catalog/widgets/compact_group_strip.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';

import '../support/app_harness.dart';
import '../support/catalog_fixtures.dart';

Finder chip(String text) => find.widgetWithText(ChoiceChip, text);

void main() {
  testWidgets('compact groups select with keyboard and persist across resize', (
    tester,
  ) async {
    final service = InMemoryCatalogQueryService(
      'test-fixture-playlist',
      const M3uParser().parse(firstGroupsPlaylistText),
    );
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: service,
      size: const Size(390, 844),
    );
    harness.controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(CompactGroupStrip), findsOneWidget);
    expect(find.text('Groups: Sweden'), findsOneWidget);
    expect(find.text('Welcome channel'), findsOneWidget);
    expect(
      tester.getTopLeft(chip('Favourites')).dx,
      lessThan(tester.getTopLeft(chip('All groups')).dx),
    );
    Focus.of(tester.element(find.text('Favourites'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(harness.controllers.app.catalogView.favoriteGroupSelected, isTrue);
    expect(tester.widget<ChoiceChip>(chip('Favourites')).selected, isTrue);
    expect(find.text('No favourites in this section yet.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('All groups'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(chip('All groups')).selected, isTrue);
    expect(find.text('Welcome channel'), findsOneWidget);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(CompactGroupStrip), findsNothing);
    expect(harness.controllers.app.catalogView.selectedGroupId, isNull);
    expect(find.text('Welcome channel'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(chip('All groups')).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact strip scrolls, uses real group order and works at 2x text',
    (tester) async {
      final playlist =
          '#EXTM3U\n${List.generate(20, (index) => '#EXTINF:-1 group-title="Group $index",Channel $index\nhttps://example.invalid/$index\n').join()}';
      final service = InMemoryCatalogQueryService(
        'test-fixture-playlist',
        const M3uParser().parse(playlist),
      );
      final harness = await pumpIptvApp(
        tester,
        catalogQueryService: service,
        size: const Size(390, 844),
        textScale: 2,
      );
      harness.controllers.app.openLiveTv();
      await tester.pumpAndSettle();
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byType(CompactGroupStrip)),
        ).scale(20),
        40,
      );
      expect(find.text('Channel 0'), findsOneWidget);
      final strip = find.descendant(
        of: find.byType(CompactGroupStrip),
        matching: find.byType(ListView),
      );
      await tester.scrollUntilVisible(
        chip('Group 19'),
        250,
        scrollable: find.descendant(
          of: strip,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(chip('Group 19'));
      await tester.pumpAndSettle();
      expect(find.text('Channel 19'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(chip('Group 19')).selected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact movie and series chips preserve explicit selection', (
    tester,
  ) async {
    final service = InMemoryCatalogQueryService(
      'test-fixture-playlist',
      const M3uParser().parse(adultLabelsPlaylistText),
    );
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: service,
      size: const Size(390, 844),
    );
    harness.controllers.app.openMovies();
    await tester.pumpAndSettle();
    expect(find.text('Marked film [xXx]'), findsNothing);
    await tester.tap(chip('All groups'));
    await tester.pumpAndSettle();
    expect(find.text('Marked film [xXx]'), findsOneWidget);
    harness.controllers.app.openSeries();
    await tester.pumpAndSettle();
    expect(find.text('Ordinary Show'), findsOneWidget);
    expect(find.text('Marked Show'), findsNothing);
    await tester.tap(chip('All groups'));
    await tester.pumpAndSettle();
    expect(find.text('Marked Show'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
