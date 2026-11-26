import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';

import '../support/app_harness.dart';
import '../support/catalog_fixtures.dart';

void main() {
  testWidgets(
    'automatic sections hide markers until an explicit group choice',
    (tester) async {
      final service = InMemoryCatalogQueryService(
        'test-fixture-playlist',
        const M3uParser().parse(adultLabelsPlaylistText),
      );
      final harness = await pumpIptvApp(
        tester,
        catalogQueryService: service,
        size: const Size(1440, 900),
      );
      expect(find.text('Restricted film [XXX]'), findsNothing);
      expect(find.text('Marked film [xXx]'), findsNothing);
      expect(find.text('Ordinary channel'), findsOneWidget);
      harness.controllers.app.openMovies();
      await tester.pumpAndSettle();
      expect(find.text('Ordinary film'), findsOneWidget);
      expect(find.text('Marked film [xXx]'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'Family Movies'));
      await tester.pumpAndSettle();
      expect(find.text('Marked film [xXx]'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Adults (VOD)'));
      await tester.pumpAndSettle();
      expect(find.text('Restricted film [XXX]'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('adult-only automatic view offers deliberate group selection', (
    tester,
  ) async {
    final onlyAdult = const M3uParser()
        .parse(adultLabelsPlaylistText)
        .where(
          (item) => item.group.contains('Adults') || item.group.contains('XXX'),
        )
        .toList();
    final service = InMemoryCatalogQueryService(
      'test-fixture-playlist',
      onlyAdult,
    );
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: service,
      size: const Size(360, 800),
    );
    expect(find.text('Restricted channel'), findsNothing);
    harness.controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    expect(find.text('Restricted channel'), findsNothing);
    expect(
      find.text('No automatically selected group. Choose a group to browse.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Groups: Choose a group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All groups'));
    await tester.pumpAndSettle();
    expect(find.text('Restricted channel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home previews and section entry follow playlist group order', (
    tester,
  ) async {
    final service = InMemoryCatalogQueryService(
      'test-fixture-playlist',
      const M3uParser().parse(firstGroupsPlaylistText),
    );
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: service,
      size: const Size(1440, 900),
    );
    final view = harness.controllers.app.catalogView;
    expect(find.text('Sweden'), findsWidgets);
    expect(find.text('Zulu Movies'), findsWidgets);
    expect(find.text('Zulu Series'), findsWidgets);
    expect(find.text('A channel'), findsNothing);
    expect(view.homeLive.map((item) => item.title), [
      'Welcome channel',
      'SVT channel',
    ]);
    harness.controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    expect(find.text('Welcome channel'), findsOneWidget);
    expect(find.text('A channel'), findsNothing);
    expect(view.selectedGroupId, view.browseGroups.first.id);
    await tester.tap(find.widgetWithText(ListTile, 'Alpha Live'));
    await tester.pumpAndSettle();
    expect(find.text('A channel'), findsOneWidget);
    harness.controllers.app.openMovies();
    await tester.pumpAndSettle();
    expect(find.text('Z movie'), findsOneWidget);
    expect(find.text('A movie'), findsNothing);
    harness.controllers.app.openSeries();
    await tester.pumpAndSettle();
    expect(find.text('Z Show'), findsOneWidget);
    expect(find.text('A Show'), findsNothing);
  });

  testWidgets('compact group selector supports keyboard, Back and All groups', (
    tester,
  ) async {
    final service = InMemoryCatalogQueryService(
      'test-fixture-playlist',
      const M3uParser().parse(firstGroupsPlaylistText),
    );
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: service,
      size: const Size(360, 800),
    );
    harness.controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    final selector = find.text('Groups: Sweden');
    Focus.of(tester.element(selector)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Groups'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Groups'), findsNothing);
    expect(find.text('Welcome channel'), findsOneWidget);
    expect(Focus.of(tester.element(selector)).hasFocus, isTrue);

    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.text('Groups'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    final otherGroup = find.text('Alpha Live');
    expect(otherGroup, findsOneWidget);
    expect(Focus.of(tester.element(find.text('Favourites'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(Focus.of(tester.element(otherGroup)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('A channel'), findsOneWidget);
    expect(
      Focus.of(tester.element(find.text('Groups: Alpha Live'))).hasFocus,
      isTrue,
    );
    await tester.tap(find.text('Groups: Alpha Live'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'All groups'));
    await tester.pumpAndSettle();
    expect(find.text('A channel'), findsOneWidget);
    expect(find.text('Welcome channel'), findsOneWidget);
    expect(harness.controllers.app.catalogView.selectedGroupId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Favourites is first in wide and compact group pickers', (
    tester,
  ) async {
    final items = const M3uParser().parse(firstGroupsPlaylistText);
    final ids = {items.firstWhere((item) => item.title == 'A channel').id};
    final service = InMemoryCatalogQueryService(
      'test-fixture-playlist',
      items,
      favoriteItemIds: ids,
    );
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: service,
      size: const Size(1440, 900),
    );
    harness.controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Favourites')).dy,
      lessThan(tester.getTopLeft(find.text('All groups')).dy),
    );
    await tester.tap(find.widgetWithText(ListTile, 'Favourites'));
    await tester.pumpAndSettle();
    expect(find.text('A channel'), findsOneWidget);
    expect(find.text('Welcome channel'), findsNothing);
    expect(harness.controllers.app.catalogView.favoriteGroupSelected, isTrue);
    harness.controllers.app.openMovies();
    await tester.pumpAndSettle();
    expect(find.text('Z movie'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Favourites'));
    await tester.pumpAndSettle();
    expect(find.text('No favourites in this section yet.'), findsOneWidget);

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groups: Favourites'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Favourites')).dy,
      lessThan(tester.getTopLeft(find.text('All groups')).dy),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Groups: Favourites'), findsOneWidget);
    await tester.tap(find.text('Groups: Favourites'));
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Favourites'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Groups: Favourites'), findsOneWidget);
    expect(find.text('No favourites in this section yet.'), findsOneWidget);
  });
}
