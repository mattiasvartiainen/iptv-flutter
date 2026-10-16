import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/settings/widgets/playlist_editor_dialog.dart';
import 'package:iptv_flutter/features/settings/widgets/playlist_error_details.dart';
import 'package:iptv_flutter/features/settings/widgets/playlist_section.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/sources/source_verifier.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';

import '../../support/in_memory_settings_repository.dart';

const _url =
    'https://provider.test/get.php?username=private-user&password=private-pass&type=m3u_plus&output=ts&custom=keep';
const _verified = XtreamAuthResult(
  verification: SourceVerificationState.verified,
  accountState: SourceAccountState.active,
);

void main() {
  for (final verbose in [false, true]) {
    for (final editing in [false, true]) {
      testWidgets('save diagnostics verbose=$verbose editing=$editing', (
        tester,
      ) async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        await fixture.preferences.setVerboseRefreshInfo(verbose);
        final initial = editing
            ? await fixture.settings.upsertPlaylist(
                const PlaylistSourceConfig.url(name: 'Existing', url: _url),
              )
            : null;
        fixture.settings.fail = true;
        await fixture.open(tester, playlist: initial);
        await _enter(tester, 'Name', 'Save failure');
        await _enter(tester, 'Playlist URL', _url);
        await _tap(tester, find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.byType(PlaylistErrorDetails),
          verbose ? findsOneWidget : findsNothing,
        );
        if (verbose) {
          final diagnostics = tester
              .widget<PlaylistErrorDetails>(find.byType(PlaylistErrorDetails))
              .diagnostics;
          expect(diagnostics, contains('Exception: Bad state:'));
          expect(diagnostics, contains('Stack trace:'));
          expect(diagnostics, contains('_Settings.upsertPlaylist'));
          expect(diagnostics, isNot(contains('private-user')));
          expect(diagnostics, isNot(contains('private-pass')));
        }
        if (!verbose) _expectSafeStatus(tester);
        fixture.settings.fail = false;
        await _tap(tester, find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(fixture.playlists.errorDiagnostics, isNull);
      });
    }

    testWidgets('refresh diagnostics verbose=$verbose', (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.preferences.setVerboseRefreshInfo(verbose);
      await fixture.settings.upsertPlaylist(
        const PlaylistSourceConfig.url(name: 'Refresh me', url: _url),
      );
      await fixture.playlists.refreshPlaylists();
      fixture.catalog.failure = StateError('Refresh failed $_url');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: Listenable.merge([
                fixture.playlists,
                fixture.preferences,
              ]),
              builder: (context, _) => SingleChildScrollView(
                child: PlaylistSection(
                  controller: fixture.playlists,
                  preferencesController: fixture.preferences,
                  onEdit: (_) {},
                  onDelete: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await _tap(tester, find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(
        find.byType(PlaylistErrorDetails),
        verbose ? findsOneWidget : findsNothing,
      );
      if (verbose) {
        final details = find.byType(PlaylistErrorDetails);
        final diagnostics = tester
            .widget<PlaylistErrorDetails>(details)
            .diagnostics;
        expect(diagnostics, contains('Refresh failed'));
        expect(diagnostics, contains('Stack trace:'));
        expect(diagnostics, isNot(contains('private-pass')));
        final focus = tester.widget<Focus>(
          find.descendant(of: details, matching: find.byType(Focus)).first,
        );
        Focus.of(
          tester.element(
            find.descendant(of: details, matching: find.byType(Text)).first,
          ),
        ).requestFocus();
        await tester.pumpAndSettle();
        expect(focus.onKeyEvent, isNotNull);
        final scroll = tester
            .widget<SingleChildScrollView>(
              find.descendant(
                of: details,
                matching: find.byType(SingleChildScrollView),
              ),
            )
            .controller!;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        await fixture.preferences.setVerboseRefreshInfo(false);
        await tester.pumpAndSettle();
        expect(find.byType(PlaylistErrorDetails), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Name has initial focus and plain URL saves without verification',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester);
      expect(find.text('Add playlist'), findsOneWidget);
      expect(find.text('Name / URL'), findsOneWidget);
      final name = tester.widget<TextField>(_field('Name'));
      expect(name.focusNode!.hasFocus, isTrue);
      await _enter(tester, 'Name', 'Plain');
      await _enter(tester, 'Playlist URL', 'https://provider.test/list.m3u');
      expect(find.text('Verify connection'), findsNothing);
      await _tap(tester, find.text('Save'));
      await tester.pumpAndSettle();
      expect(fixture.verifier.requests, isEmpty);
      expect(fixture.settings.saved.single.name, 'Plain');
      expect(fixture.catalog.loads, 0);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'detection is local, Enter verifies, save preserves URL options',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester);
      await _enter(tester, 'Name', 'Provider');
      await _enter(tester, 'Playlist URL', _url);
      expect(find.text('API host: provider.test'), findsOneWidget);
      expect(find.text('Use Xtream API'), findsOneWidget);
      expect(fixture.verifier.requests, isEmpty);
      _expectSafeStatus(tester);
      final verify = find.widgetWithText(OutlinedButton, 'Verify connection');
      await tester.ensureVisible(verify);
      final focus = Focus.of(tester.element(find.text('Verify connection')));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fixture.verifier.requests, hasLength(1));
      expect(find.text('Checking connection...'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      fixture.verifier.requests.single.result.complete(_verified);
      await tester.pumpAndSettle();
      expect(find.text('API verified.'), findsOneWidget);
      expect(find.text('Account: Active'), findsOneWidget);
      expect(fixture.settings.saved, isEmpty);
      expect(fixture.catalog.loads, 0);
      await _tap(tester, find.text('Save'));
      await tester.pumpAndSettle();
      final saved = fixture.settings.saved.single;
      expect(saved.kind, PlaylistSourceKind.url);
      expect(saved.url, _url);
      expect(
        saved.verificationRecord?.verification,
        SourceVerificationState.verified,
      );
      expect(saved.verificationRecord?.apiEnabled, isTrue);
      expect(fixture.verifier.requests, hasLength(1));
      expect(fixture.catalog.loads, 0);
    },
  );

  testWidgets(
    'safe failure retains fields, retries, and permits URL-only save',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester);
      await _enter(tester, 'Name', 'Keep me');
      await _enter(tester, 'Playlist URL', _url);
      await _tap(tester, find.text('Verify connection'));
      fixture.verifier.requests.single.result.completeError(StateError(_url));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not verify the connection. Try again.'),
        findsOneWidget,
      );
      expect(_text(tester, 'Name'), 'Keep me');
      expect(_text(tester, 'Playlist URL'), _url);
      _expectSafeStatus(tester);
      await _tap(tester, find.text('Retry verification'));
      fixture.verifier.requests.last.result.complete(
        const XtreamAuthResult(
          verification: SourceVerificationState.unsupported,
          failure: XtreamAuthFailure.unsupported,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('API verification is not supported.'), findsOneWidget);
      await _tap(tester, find.text('Use Xtream API'));
      expect(find.text('Retry verification'), findsNothing);
      await _tap(tester, find.text('Save'));
      await tester.pumpAndSettle();
      expect(fixture.settings.saved.single.url, _url);
      expect(
        fixture.settings.saved.single.verificationRecord?.apiEnabled,
        isFalse,
      );
      expect(fixture.verifier.requests, hasLength(2));
      expect(fixture.catalog.loads, 0);
    },
  );

  for (final address in [
    _url.replaceFirst('https:', 'http:'),
    _url.replaceFirst('get.php', 'custom.php'),
  ]) {
    testWidgets(
      'confirmation gates verification for ${Uri.parse(address).path} ${Uri.parse(address).scheme}',
      (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        await fixture.open(tester);
        await _enter(tester, 'Playlist URL', address);
        expect(find.text('Confirm this server connection'), findsOneWidget);
        final button = find.widgetWithText(OutlinedButton, 'Verify connection');
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        if (address.startsWith('http:')) {
          expect(
            find.text('HTTP is not encrypted. Credentials may be exposed.'),
            findsOneWidget,
          );
        }
        await _tap(tester, find.text('Confirm this server connection'));
        await _tap(tester, find.text('Verify connection'));
        expect(fixture.verifier.requests.single.confirmed, isTrue);
        await _tap(tester, find.text('Cancel verification'));
        expect(
          fixture.verifier.requests.single.cancellation.isCancelled,
          isTrue,
        );
        fixture.verifier.requests.single.result.complete(_verified);
        await tester.pumpAndSettle();
        expect(find.text('API verified.'), findsNothing);
        await _tap(tester, find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'explicit Xtream has obscured password and bare-host confirmation',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester);
      await _enter(tester, 'Name', 'Explicit');
      await _tap(
        tester,
        find.byType(DropdownButtonFormField<PlaylistSourceKind>),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Xtream Codes').last);
      await tester.pumpAndSettle();
      await _enter(tester, 'Server', 'provider.test');
      await _enter(tester, 'Username', 'private-user');
      await _enter(tester, 'Password', ' private-pass ');
      final password = find.descendant(
        of: _field('Password'),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(password).obscureText, isTrue);
      expect(find.text('API host: provider.test'), findsOneWidget);
      expect(find.text('Confirm this server connection'), findsOneWidget);
      await _tap(tester, find.text('Confirm this server connection'));
      await _tap(tester, find.text('Save'));
      await tester.pumpAndSettle();
      expect(fixture.settings.saved.single.password, ' private-pass ');
      expect(fixture.settings.saved.single.server, 'https://provider.test');
      expect(fixture.verifier.requests, isEmpty);
      expect(fixture.catalog.loads, 0);
    },
  );

  testWidgets(
    'editing retains identity, disabled state, and exact source URL',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final initial = await fixture.settings.upsertPlaylist(
        const PlaylistSourceConfig.url(
          playlistId: 'existing-playlist',
          name: 'Original',
          url: _url,
          enabled: false,
        ),
      );
      fixture.settings.saved.clear();
      await fixture.open(tester, playlist: initial);
      expect(find.text('Edit playlist'), findsOneWidget);
      expect(_text(tester, 'Playlist URL'), _url);
      await _enter(tester, 'Name', 'Renamed');
      await _tap(tester, find.text('Save'));
      await tester.pumpAndSettle();
      final saved = fixture.settings.saved.single;
      expect(saved.playlistId, 'existing-playlist');
      expect(saved.enabled, isFalse);
      expect(saved.name, 'Renamed');
      expect(saved.url, _url);
      expect(fixture.verifier.requests, isEmpty);
      expect(fixture.catalog.loads, 0);
    },
  );

  for (final back in [false, true]) {
    testWidgets(
      'closing with back=$back cancels and ignores late verification',
      (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        await fixture.open(tester);
        await _enter(tester, 'Playlist URL', _url);
        await _tap(tester, find.text('Verify connection'));
        if (back) {
          await tester.binding.handlePopRoute();
        } else {
          await _tap(tester, find.text('Cancel'));
        }
        await tester.pumpAndSettle();
        expect(
          fixture.verifier.requests.single.cancellation.isCancelled,
          isTrue,
        );
        fixture.verifier.requests.single.result.complete(_verified);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        expect(fixture.settings.saved, isEmpty);
      },
    );
  }

  testWidgets(
    'save failure stays open and can be retried without verification',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.settings.fail = true;
      await fixture.open(tester);
      await _enter(tester, 'Name', 'Still here');
      await _enter(tester, 'Playlist URL', _url);
      await _tap(tester, find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_text(tester, 'Name'), 'Still here');
      expect(_text(tester, 'Playlist URL'), _url);
      expect(find.textContaining('Could not'), findsWidgets);
      _expectSafeStatus(tester);
      fixture.settings.fail = false;
      await _tap(tester, find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.verifier.requests, isEmpty);
      expect(fixture.catalog.loads, 0);
    },
  );

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets('verification form fits $size at 2x text', (tester) async {
      tester.view.reset();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.open(tester, textScale: 2);
      await _enter(tester, 'Name', 'Responsive');
      await _enter(
        tester,
        'Playlist URL',
        _url.replaceFirst('https:', 'http:'),
      );
      await _tap(tester, find.text('Confirm this server connection'));
      await _tap(tester, find.text('Verify connection'));
      expect(fixture.verifier.requests, hasLength(1));
      await _tap(tester, find.text('Cancel verification'));
      fixture.verifier.requests.single.result.complete(_verified);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

Future<void> _enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), value);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void _expectSafeStatus(WidgetTester tester) {
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .join(' ');
  expect(visibleText, isNot(contains('private-user')));
  expect(visibleText, isNot(contains('private-pass')));
  expect(visibleText, isNot(contains('get.php?')));
}

class _Fixture {
  _Fixture() {
    preferences = AppPreferencesController(settingsRepository: settings);
    playlists = PlaylistsController(
      catalogRepository: catalog,
      settingsRepository: settings,
      catalogView: view,
      navigationController: navigation,
      preferencesController: preferences,
      sourceVerifier: verifier,
    );
  }

  final settings = _Settings();
  final catalog = _Catalog();
  final verifier = _Verifier();
  final view = CatalogViewState();
  final navigation = NavigationController();
  late final AppPreferencesController preferences;
  late final PlaylistsController playlists;

  Future<void> open(
    WidgetTester tester, {
    double textScale = 1,
    ManagedPlaylist? playlist,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlaylistEditor(
                context,
                controller: playlists,
                playlist: playlist,
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  void dispose() {
    playlists.dispose();
    preferences.dispose();
    view.dispose();
    navigation.dispose();
  }
}

class _Settings extends InMemorySettingsRepository {
  final saved = <PlaylistSourceConfig>[];
  bool fail = false;

  @override
  Future<ManagedPlaylist> upsertPlaylist(PlaylistSourceConfig config) async {
    if (fail) throw StateError(_url);
    saved.add(config);
    return super.upsertPlaylist(config);
  }
}

class _Catalog implements CatalogRepository {
  int loads = 0;
  Object? failure;

  @override
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  }) async {
    loads++;
    if (failure case final error?) throw error;
    return CatalogLoadResult(playlistId: playlistId, itemCount: 0);
  }
}

class _Verifier implements SourceVerifier {
  final requests =
      <
        ({
          PlaylistSourceConfig config,
          bool confirmed,
          XtreamCancellation cancellation,
          Completer<XtreamAuthResult> result,
        })
      >[];

  @override
  Future<XtreamAuthResult> verify(
    PlaylistSourceConfig config, {
    required bool confirmed,
    required XtreamCancellation cancellation,
  }) {
    final result = Completer<XtreamAuthResult>();
    requests.add((
      config: config,
      confirmed: confirmed,
      cancellation: cancellation,
      result: result,
    ));
    return result.future;
  }
}
