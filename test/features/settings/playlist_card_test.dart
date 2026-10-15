import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/features/settings/widgets/playlist_card.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_progress.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/ui/theme/app_theme.dart';

void main() {
  for (final viewport in [
    const Size(320, 800),
    const Size(360, 800),
    const Size(390, 844),
    const Size(800, 360),
    const Size(1440, 900),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('playlist refresh fits $viewport at scale $textScale', (
        tester,
      ) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var editCount = 0;
        var deleteCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(36),
                children: [
                  PlaylistCard(
                    playlist: const ManagedPlaylist(
                      playlistId: 'portrait-playlist',
                      name: 'My saved television playlist',
                      enabled: true,
                      sourceConfig: null,
                      sourceKind: PlaylistSourceKind.url,
                      sourceSummary: 'https://playlist.example.com',
                      resolvedUrl: '',
                      sourceUrlRedacted: null,
                      lastImportStatus: null,
                      lastImportWarning: null,
                      lastImportCompletedAt: null,
                      refreshSettings: null,
                    ),
                    isActive: true,
                    isRefreshing: true,
                    progress: CatalogImportProgress(
                      phase: CatalogImportPhase.importing,
                      startedAt: DateTime.now(),
                      current: 1200,
                      total: 5000,
                    ),
                    onSelect: () {},
                    onRefresh: () {},
                    onEdit: () => editCount++,
                    onDelete: () => deleteCount++,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.text('https://playlist.example.com')).width,
          greaterThan(200),
        );
        final actionsBelow = viewport.width - 104 < 600 * textScale;
        final refreshTop = tester.getTopLeft(find.text('Refreshing')).dy;
        final detailsBottom = tester
            .getBottomLeft(find.byType(LinearProgressIndicator))
            .dy;
        expect(
          refreshTop,
          actionsBelow ? greaterThan(detailsBottom) : lessThan(detailsBottom),
        );
        final refreshButton = find.widgetWithText(OutlinedButton, 'Refreshing');
        expect(tester.widget<OutlinedButton>(refreshButton).onPressed, isNull);
        final editButton = find.widgetWithText(OutlinedButton, 'Edit');
        await tester.pump();
        await tester.ensureVisible(editButton);
        await tester.pump();
        await tester.tap(editButton);
        expect(editCount, 1);
        Focus.of(tester.element(find.text('Edit'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(editCount, 2);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(deleteCount, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
