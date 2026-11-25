import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/features/settings/widgets/playlist_card.dart';
import 'package:iptv_flutter/features/settings/widgets/playlist_error_details.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_worker.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/ui/widgets/inline_issue.dart';

import '../../support/app_harness.dart';
import '../../support/catalog_fixtures.dart';
import '../../support/in_memory_settings_repository.dart';

void main() {
  testWidgets(
    'playlist HTTP 511 stays on its card and supports remote retry and Back',
    (tester) async {
      final settings = InMemorySettingsRepository();
      for (final id in ['first', 'second']) {
        await settings.upsertPlaylist(
          PlaylistSourceConfig.url(
            playlistId: id,
            name: id,
            url: 'https://fixture.test/$id.m3u',
          ),
        );
      }
      final repository = _FailingRepository();
      final harness = await pumpIptvApp(
        tester,
        settingsRepository: settings,
        catalogRepository: repository,
        loadFixturePlaylist: false,
        size: const Size(1440, 1000),
      );
      final controllers = harness.controllers;
      await controllers.playlists.refreshPlaylists();
      controllers.app.navigationController.resetToHomeAndPush(
        const SettingsRoute(),
      );
      await tester.pumpAndSettle();
      Finder card(String id) => find.byWidgetPredicate(
        (widget) => widget is PlaylistCard && widget.playlist.playlistId == id,
      );
      Finder refresh(String id) => find.descendant(
        of: card(id),
        matching: find.widgetWithText(OutlinedButton, 'Refresh'),
      );

      await tester.ensureVisible(refresh('first'));
      Focus.of(
        tester.element(
          find.descendant(of: refresh('first'), matching: find.byType(Text)),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final firstPanel = find.descendant(
        of: card('first'),
        matching: find.byType(InlineIssue),
      );
      expect(firstPanel, findsOneWidget);
      final announcement = tester.widget<Semantics>(
        find.descendant(of: firstPanel, matching: find.byType(Semantics)).first,
      );
      expect(announcement.properties.liveRegion, isTrue);
      expect(find.byType(InlineIssue), findsOneWidget);
      expect(
        find.descendant(of: card('second'), matching: find.byType(InlineIssue)),
        findsNothing,
      );
      expect(find.text('Network sign-in may be required'), findsOneWidget);
      expect(find.textContaining('HTTP 511'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PlaylistErrorDetails), findsNothing);
      expect(
        tester.getTopLeft(firstPanel).dy,
        greaterThan(tester.getBottomLeft(refresh('first')).dy),
      );
      expect(
        Focus.of(
          tester.element(
            find.descendant(of: refresh('first'), matching: find.byType(Text)),
          ),
        ).hasFocus,
        isTrue,
      );

      await controllers.playlists.refreshPlaylist('second');
      await tester.pumpAndSettle();
      expect(find.byType(InlineIssue), findsNWidgets(2));
      repository.fail = false;
      await tester.ensureVisible(refresh('second'));
      Focus.of(
        tester.element(
          find.descendant(of: refresh('second'), matching: find.byType(Text)),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(InlineIssue), findsOneWidget);
      expect(firstPanel, findsOneWidget);
      expect(
        controllers.app.navigationController.currentRoute,
        isA<SettingsRoute>(),
      );

      await controllers.preferences.setVerboseRefreshInfo(true);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: card('first'),
          matching: find.byType(PlaylistErrorDetails),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        controllers.app.navigationController.currentRoute,
        isA<HomeRoute>(),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _FailingRepository implements CatalogRepository {
  bool fail = true;

  @override
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  }) async {
    if (fail) {
      throw const CatalogImportWorkerException(
        errorType: 'HttpException',
        message: 'HTTP 511',
        workerStackTrace: 'worker stack',
        diagnostics: {'http.response.status_code': 511},
      );
    }
    return CatalogLoadResult(
      playlistId: playlistId,
      itemCount: fixtureCatalog.length,
    );
  }
}
