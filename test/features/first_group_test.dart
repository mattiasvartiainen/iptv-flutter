import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';

import '../support/app_harness.dart';
import '../support/catalog_fixtures.dart';

void main() {
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
    expect(Focus.of(tester.element(find.text('All groups'))).hasFocus, isTrue);
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
}
