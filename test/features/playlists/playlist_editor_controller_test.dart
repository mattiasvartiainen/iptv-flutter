import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/features/playlists/playlist_editor_controller.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/sources/source_verifier.dart';

const _url =
    'https://provider.example/panel/get.php?username=User&password=%20Secret%20&output=ts&token=keep';
const _success = XtreamAuthResult(
  verification: SourceVerificationState.verified,
  accountState: SourceAccountState.active,
);

void main() {
  late _Verifier verifier;
  late PlaylistEditorController controller;
  final checkedAt = DateTime.utc(2026, 10, 15);

  setUp(() {
    verifier = _Verifier();
    controller = PlaylistEditorController(
      verifier: verifier,
      now: () => checkedAt,
    );
  });
  tearDown(() => controller.dispose());

  test('URL detection is local, defaults off and previews only a host', () {
    expect(controller.sourceKind, PlaylistSourceKind.url);
    expect(controller.apiEnabled, isFalse);
    expect(controller.canVerify, isFalse);
    controller.updateUrl(_url);
    expect(controller.apiEnabled, isTrue);
    expect(controller.candidatePreview, 'provider.example');
    expect(controller.insecure, isFalse);
    expect(controller.requiresConfirmation, isFalse);
    expect(controller.canVerify, isTrue);
    expect(controller.connectionConfirmed, isFalse);
    expect(verifier.requests, isEmpty);
    expect(controller.result, isNull);
    expect(controller.verificationRecord, isNull);
  });

  test(
    'verification preserves URL, kind, options and produces a safe record',
    () async {
      controller.updateName(' My playlist ');
      controller.updateUrl(_url);
      final pending = controller.verify();
      expect(controller.checking, isTrue);
      expect(controller.canVerify, isFalse);
      expect(controller.verificationText, 'Checking connection...');
      await controller.verify();
      expect(verifier.requests, hasLength(1));
      final request = verifier.requests.single;
      expect(request.config.url, _url);
      expect(request.confirmed, isTrue);
      request.completion.complete(_success);
      await pending;
      expect(controller.checking, isFalse);
      expect(controller.result, same(_success));
      expect(controller.canVerify, isTrue);
      expect(controller.verificationText, 'API verified.');
      expect(controller.accountText, 'Active');
      final record = controller.verificationRecord!;
      expect(record.verification, SourceVerificationState.verified);
      expect(record.accountState, SourceAccountState.active);
      expect(record.checkedAt, checkedAt);
      expect(record.connectionRevision, controller.connectionRevision);
      expect(record.apiEnabled, isTrue);
      final config = controller.buildConfig('assigned-id');
      expect(config.playlistId, 'assigned-id');
      expect(config.name, 'My playlist');
      expect(config.kind, PlaylistSourceKind.url);
      expect(config.url, _url);
      expect(config.resolvedUrl, _url);
    },
  );

  for (final input in [
    'http://provider.example/get.php?username=u&password=p',
    'https://provider.example/custom.cgi?username=u&password=p',
  ]) {
    test(
      'HTTP and unknown URL endpoints require explicit confirmation: $input',
      () async {
        controller.updateUrl(input);
        expect(controller.requiresConfirmation, isTrue);
        expect(controller.canVerify, isFalse);
        expect(controller.insecure, input.startsWith('http:'));
        await controller.verify();
        expect(verifier.requests, isEmpty);
        controller.updateConnectionConfirmed(true);
        final pending = controller.verify();
        expect(verifier.requests.single.confirmed, isTrue);
        verifier.requests.single.completion.complete(_success);
        await pending;
      },
    );
  }

  test(
    'explicit fields preserve exact password and normalize bare server only after confirmation',
    () async {
      controller.updateSourceKind(PlaylistSourceKind.xtream);
      controller.updateName('Account');
      controller.updateServer('provider.example:8080/panel/');
      controller.updateUsername(' User ');
      controller.updatePassword(' Pass+&/% ');
      expect(controller.apiEnabled, isTrue);
      expect(controller.requiresConfirmation, isTrue);
      expect(controller.candidatePreview, 'provider.example');
      expect(controller.server, 'provider.example:8080/panel/');
      expect(() => controller.buildConfig(null), throwsStateError);
      await controller.verify();
      expect(verifier.requests, isEmpty);
      controller.updateConnectionConfirmed(true);
      final config = controller.buildConfig(null);
      expect(config.server, 'https://provider.example:8080/panel/');
      expect(config.username, 'User');
      expect(config.password, ' Pass+&/% ');
      final pending = controller.verify();
      expect(
        verifier.requests.single.config.server,
        'provider.example:8080/panel/',
      );
      verifier.requests.single.completion.complete(_success);
      await pending;
      controller.updateApiEnabled(false);
      expect(controller.apiEnabled, isTrue);
    },
  );

  test(
    'name edits and identical values preserve confirmation and verification',
    () async {
      controller.updateUrl(_url);
      controller.updateConnectionConfirmed(true);
      final revision = controller.connectionRevision;
      final pending = controller.verify();
      controller.updateName('Renamed during request');
      expect(verifier.requests.single.cancellation.isCancelled, isFalse);
      verifier.requests.single.completion.complete(_success);
      await pending;
      final record = controller.verificationRecord;
      controller.updateName('Renamed after request');
      controller.updateUrl(_url);
      controller.updateConnectionConfirmed(true);
      expect(controller.connectionRevision, revision);
      expect(controller.connectionConfirmed, isTrue);
      expect(controller.result, same(_success));
      expect(controller.verificationRecord, same(record));
    },
  );

  final edits = <String, void Function(PlaylistEditorController)>{
    'url': (editor) => editor.updateUrl('$_url&changed=1'),
    'server': (editor) => editor.updateServer('https://new.example'),
    'username': (editor) => editor.updateUsername('new'),
    'password': (editor) => editor.updatePassword('new'),
    'kind': (editor) => editor.updateSourceKind(PlaylistSourceKind.xtream),
    'opt-out': (editor) => editor.updateApiEnabled(false),
  };
  for (final edit in edits.entries) {
    test('${edit.key} edit cancels and suppresses late success', () async {
      controller.updateUrl(_url);
      controller.updateConnectionConfirmed(true);
      final revision = controller.connectionRevision;
      final pending = controller.verify();
      final request = verifier.requests.single;
      edit.value(controller);
      expect(request.cancellation.isCancelled, isTrue);
      expect(controller.checking, isFalse);
      expect(controller.connectionConfirmed, isFalse);
      expect(controller.connectionRevision, revision + 1);
      request.completion.complete(_success);
      await pending;
      expect(controller.result, isNull);
      expect(controller.verificationRecord, isNull);
      expect(controller.errorMessage, isNull);
    });

    test('${edit.key} edit clears completed verification', () async {
      controller.updateUrl(_url);
      controller.updateConnectionConfirmed(true);
      final pending = controller.verify();
      verifier.requests.single.completion.complete(_success);
      await pending;
      edit.value(controller);
      expect(controller.result, isNull);
      expect(controller.verificationRecord, isNull);
      expect(controller.connectionConfirmed, isFalse);
    });
  }

  test(
    'URL-only opt-out stays off across edits and can explicitly re-enable',
    () async {
      controller.updateUrl(_url);
      controller.updateApiEnabled(false);
      controller.updateUrl('$_url&changed=1');
      expect(controller.apiEnabled, isFalse);
      expect(controller.canVerify, isFalse);
      await controller.verify();
      expect(verifier.requests, isEmpty);
      controller.updateApiEnabled(true);
      expect(controller.canVerify, isTrue);
    },
  );

  test(
    'cancel allows retry and old success cannot overwrite newer failure',
    () async {
      controller.updateUrl(_url);
      final old = controller.verify();
      controller.cancelVerification();
      expect(verifier.requests.first.cancellation.isCancelled, isTrue);
      final retry = controller.verify();
      verifier.requests.last.completion.complete(
        const XtreamAuthResult(
          verification: SourceVerificationState.invalidCredentials,
          failure: XtreamAuthFailure.denied,
        ),
      );
      await retry;
      verifier.requests.first.completion.complete(_success);
      await old;
      expect(controller.result!.failure, XtreamAuthFailure.denied);
      expect(controller.verificationRecord, isNull);
      expect(
        controller.errorMessage,
        'The account credentials were not accepted.',
      );
      expect(controller.url, _url);
      expect(controller.canVerify, isTrue);
    },
  );

  test(
    'late exception cannot clear a newer request or expose credentials',
    () async {
      controller.updateUrl(_url);
      final old = controller.verify();
      controller.cancelVerification();
      final retry = controller.verify();
      verifier.requests.first.completion.completeError(
        StateError('$_url password=Secret'),
      );
      await old;
      expect(controller.checking, isTrue);
      expect(controller.errorMessage, isNull);
      verifier.requests.last.completion.complete(_success);
      await retry;
      expect(controller.result, same(_success));
    },
  );

  test(
    'disposal for closing or deleting a draft cancels without late notifications',
    () async {
      controller.updateUrl(_url);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final pending = controller.verify();
      final beforeDispose = notifications;
      controller.dispose();
      expect(verifier.requests.single.cancellation.isCancelled, isTrue);
      verifier.requests.single.completion.complete(_success);
      await pending;
      expect(notifications, beforeDispose);
      expect(controller.result, isNull);
      expect(controller.verificationRecord, isNull);
      expect(controller.checking, isFalse);
      expect(controller.canVerify, isFalse);
      await controller.verify();
      expect(verifier.requests, hasLength(1));
    },
  );

  test('confirmation revocation cancels the request', () async {
    controller.updateUrl(_url.replaceFirst('https:', 'http:'));
    controller.updateConnectionConfirmed(true);
    final pending = controller.verify();
    controller.updateConnectionConfirmed(false);
    expect(verifier.requests.single.cancellation.isCancelled, isTrue);
    verifier.requests.single.completion.complete(_success);
    await pending;
    expect(controller.canVerify, isFalse);
    expect(controller.result, isNull);
  });

  test(
    'synchronous verifier exception is sanitized and retry remains explicit',
    () async {
      controller.dispose();
      controller = PlaylistEditorController(verifier: _ThrowingVerifier());
      controller.updateUrl(_url);
      await controller.verify();
      expect(
        controller.errorMessage,
        'Could not verify the connection. Try again.',
      );
      expect(controller.verificationText, isNot(contains('Secret')));
      expect(controller.checking, isFalse);
      expect(controller.canVerify, isTrue);
      expect(controller.url, _url);
    },
  );

  test(
    'invalid and noncandidate sources do not verify or leak preview text',
    () async {
      for (final input in [
        'invalid password=Secret',
        'https://u:Secret@provider.example/get.php',
        'https://provider.example/live/u/Secret/42.ts',
        'https://provider.example/get.php?username=u&username=v&password=Secret',
      ]) {
        controller.updateUrl(input);
        expect(controller.candidatePreview, isNull);
        expect(controller.canVerify, isFalse);
        await controller.verify();
      }
      expect(verifier.requests, isEmpty);
    },
  );

  test('initial saved source keeps ID, enabled and fields with no request', () {
    controller.dispose();
    controller = PlaylistEditorController(
      verifier: verifier,
      initial: _initial(),
      connectionRevision: 7,
    );
    expect(controller.name, 'Saved');
    expect(controller.url, _url);
    expect(controller.connectionRevision, 7);
    expect(controller.buildConfig(null).playlistId, 'saved-id');
    expect(controller.buildConfig(null).enabled, isFalse);
    expect(controller.result, isNull);
    expect(verifier.requests, isEmpty);
  });

  test('saved explicit credentials are not auto-verified or confirmed', () {
    controller.dispose();
    controller = PlaylistEditorController(
      verifier: verifier,
      initial: const ManagedPlaylist(
        playlistId: 'explicit-id',
        name: 'Account',
        enabled: true,
        sourceConfig: PlaylistSourceConfig.xtream(
          name: 'Account',
          server: 'http://provider.example/panel',
          username: 'User',
          password: ' Secret ',
        ),
        sourceKind: PlaylistSourceKind.xtream,
        sourceSummary: 'provider.example',
        resolvedUrl: '',
        sourceUrlRedacted: null,
        lastImportStatus: null,
        lastImportWarning: null,
        lastImportCompletedAt: null,
        refreshSettings: null,
      ),
    );
    expect(controller.sourceKind, PlaylistSourceKind.xtream);
    expect(controller.apiEnabled, isTrue);
    expect(controller.insecure, isTrue);
    expect(controller.requiresConfirmation, isTrue);
    expect(controller.connectionConfirmed, isFalse);
    expect(controller.canVerify, isFalse);
    expect(controller.server, 'http://provider.example/panel');
    expect(controller.username, 'User');
    expect(controller.password, ' Secret ');
    expect(controller.buildConfig(null).password, ' Secret ');
    expect(verifier.requests, isEmpty);
  });

  for (final failure in XtreamAuthFailure.values) {
    test(
      'failure ${failure.name} has only fixed safe text and allows retry',
      () async {
        controller.updateUrl(_url);
        final pending = controller.verify();
        verifier.requests.single.completion.complete(
          XtreamAuthResult(
            verification: SourceVerificationState.temporarilyUnavailable,
            failure: failure,
          ),
        );
        await pending;
        expect(controller.errorMessage, isNotEmpty);
        expect(controller.errorMessage, isNot(contains('Secret')));
        expect(
          controller.verificationText,
          isNot(contains('provider.example')),
        );
        expect(controller.accountText, 'Unknown');
        expect(controller.verificationRecord, isNull);
        expect(controller.canVerify, isTrue);
        expect(verifier.requests, hasLength(1));
      },
    );
  }

  test(
    'listener cancellation at checking notification prevents dispatch',
    () async {
      controller.updateUrl(_url);
      controller.addListener(() {
        if (controller.checking) controller.cancelVerification();
      });
      await controller.verify();
      expect(verifier.requests, isEmpty);
      expect(controller.checking, isFalse);
      expect(controller.result, isNull);
    },
  );

  test('negative revision and invalid config builds are rejected safely', () {
    expect(
      () =>
          PlaylistEditorController(verifier: verifier, connectionRevision: -1),
      throwsArgumentError,
    );
    expect(() => controller.buildConfig(null), throwsStateError);
    controller.updateName('Name');
    expect(() => controller.buildConfig(null), throwsStateError);
    controller.updateSourceKind(PlaylistSourceKind.xtream);
    controller.updateServer('https://user:Secret@provider.example');
    controller.updateUsername('u');
    controller.updatePassword('p');
    expect(() => controller.buildConfig(null), throwsStateError);
  });
}

ManagedPlaylist _initial() => const ManagedPlaylist(
  playlistId: 'saved-id',
  name: 'Saved',
  enabled: false,
  sourceConfig: PlaylistSourceConfig.url(
    name: 'Saved',
    url: _url,
    enabled: false,
  ),
  sourceKind: PlaylistSourceKind.url,
  sourceSummary: 'provider.example',
  resolvedUrl: _url,
  sourceUrlRedacted: null,
  lastImportStatus: null,
  lastImportWarning: null,
  lastImportCompletedAt: null,
  refreshSettings: null,
);

class _Request {
  _Request(this.config, this.confirmed, this.cancellation);
  final PlaylistSourceConfig config;
  final bool confirmed;
  final XtreamCancellation cancellation;
  final completion = Completer<XtreamAuthResult>();
}

class _Verifier implements SourceVerifier {
  final requests = <_Request>[];

  @override
  Future<XtreamAuthResult> verify(
    PlaylistSourceConfig config, {
    required bool confirmed,
    required XtreamCancellation cancellation,
  }) {
    final request = _Request(config, confirmed, cancellation);
    requests.add(request);
    return request.completion.future;
  }
}

class _ThrowingVerifier implements SourceVerifier {
  @override
  Future<XtreamAuthResult> verify(
    PlaylistSourceConfig config, {
    required bool confirmed,
    required XtreamCancellation cancellation,
  }) => throw StateError('password=Secret');
}
