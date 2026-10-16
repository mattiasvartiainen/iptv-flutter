import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/xtream/xtream_api_client.dart';
import 'package:iptv_flutter/services/xtream/xtream_authentication.dart';
import 'package:iptv_flutter/services/xtream/xtream_source_verifier.dart';

void main() {
  test('draft URL preserves credentials and uses same-origin API only', () async {
    final transport = _Transport();
    final verifier = _verifier(transport);
    final result = await verifier.verify(
      const PlaylistSourceConfig.url(
        name: 'Draft',
        url:
            'https://provider.example:8443/panel/get.php?username=User%2B&password=%20Pass%26%20&output=ts&token=keep',
      ),
      confirmed: false,
      cancellation: XtreamCancellation(),
    );
    expect(result.verification, SourceVerificationState.verified);
    expect(transport.uri!.path, '/panel/player_api.php');
    expect(transport.uri!.port, 8443);
    expect(transport.uri!.host, 'provider.example');
    expect(transport.uri!.queryParameters, {
      'username': 'User+',
      'password': ' Pass& ',
    });
    expect(transport.closed, isTrue);
  });

  for (final server in [
    'provider.example:8080/panel',
    'http://provider.example:8080/panel',
    'https://[::1]:8443/a%20b/',
  ]) {
    test(
      'explicit server parses and preserves exact password: $server',
      () async {
        final transport = _Transport();
        final result = await _verifier(transport).verify(
          PlaylistSourceConfig.xtream(
            name: 'Draft',
            server: server,
            username: ' User ',
            password: ' Pass+&/% ',
          ),
          confirmed: true,
          cancellation: XtreamCancellation(),
        );
        expect(result.verification, SourceVerificationState.verified);
        expect(transport.uri!.queryParameters['username'], 'User');
        expect(transport.uri!.queryParameters['password'], ' Pass+&/% ');
        expect(transport.uri!.pathSegments.last, 'player_api.php');
        if (server.contains('a%20b')) {
          expect(transport.uri!.pathSegments, ['a b', 'player_api.php']);
        } else {
          expect(transport.uri!.path, '/panel/player_api.php');
        }
      },
    );
  }

  final guarded = [
    const PlaylistSourceConfig.xtream(
      name: 'Draft',
      server: 'provider.example',
      username: 'u',
      password: 'p',
    ),
    const PlaylistSourceConfig.xtream(
      name: 'Draft',
      server: 'http://provider.example',
      username: 'u',
      password: 'p',
    ),
    const PlaylistSourceConfig.url(
      name: 'Draft',
      url: 'https://provider.example/custom.php?username=u&password=p',
    ),
    const PlaylistSourceConfig.url(
      name: 'Draft',
      url: 'http://provider.example/get.php?username=u&password=p',
    ),
  ];
  for (var index = 0; index < guarded.length; index++) {
    test('confirmation guard $index never creates a client', () async {
      final verifier = XtreamSourceVerifier(
        createClient: (_) => throw StateError('Client must not be created'),
      );
      final result = await verifier.verify(
        guarded[index],
        confirmed: false,
        cancellation: XtreamCancellation(),
      );
      expect(result.failure, XtreamAuthFailure.confirmationRequired);
    });
  }

  test('invalid and pre-cancelled drafts never create a client', () async {
    var creations = 0;
    final verifier = XtreamSourceVerifier(
      createClient: (_) {
        creations++;
        throw StateError('No client');
      },
    );
    const config = PlaylistSourceConfig.url(name: 'Draft', url: 'invalid');
    expect(
      (await verifier.verify(
        config,
        confirmed: true,
        cancellation: XtreamCancellation(),
      )).failure,
      XtreamAuthFailure.invalidEndpoint,
    );
    expect(
      (await verifier.verify(
        config,
        confirmed: true,
        cancellation: XtreamCancellation()..cancel(),
      )).failure,
      XtreamAuthFailure.cancelled,
    );
    expect(creations, 0);
  });

  test('cancellation force-closes the real client transport', () async {
    final transport = _Transport()..pending = Completer<XtreamAuthResponse>();
    final cancellation = XtreamCancellation();
    final pending = _verifier(transport).verify(
      const PlaylistSourceConfig.xtream(
        name: 'Draft',
        server: 'https://provider.example',
        username: 'u',
        password: 'p',
      ),
      confirmed: false,
      cancellation: cancellation,
    );
    await transport.started.future;
    cancellation.cancel();
    expect((await pending).failure, XtreamAuthFailure.cancelled);
    expect(transport.closed, isTrue);
    transport.pending!.complete(
      const XtreamAuthResponse(statusCode: 200, body: Stream.empty()),
    );
  });

  test('factory failures do not expose exception text', () async {
    final result =
        await XtreamSourceVerifier(
          createClient: (_) => throw StateError('password=secret'),
        ).verify(
          const PlaylistSourceConfig.xtream(
            name: 'Draft',
            server: 'https://provider.example',
            username: 'u',
            password: 'p',
          ),
          confirmed: false,
          cancellation: XtreamCancellation(),
        );
    expect(result.failure, XtreamAuthFailure.network);
    expect(result.toString(), isNot(contains('secret')));
  });
}

XtreamSourceVerifier _verifier(_Transport transport) => XtreamSourceVerifier(
  createClient: (resolver) => XtreamApiClient(
    resolveCredentials: resolver,
    createTransport: () => transport,
  ),
);

class _Transport implements XtreamAuthTransport {
  Uri? uri;
  bool closed = false;
  final started = Completer<void>();
  Completer<XtreamAuthResponse>? pending;

  @override
  Future<XtreamAuthResponse> get(Uri authenticatedUri) async {
    uri = authenticatedUri;
    started.complete();
    if (pending != null) return pending!.future;
    return XtreamAuthResponse(
      statusCode: 200,
      body: Stream.value(
        utf8.encode(
          jsonEncode({
            'user_info': {'auth': 1, 'status': 'Active'},
          }),
        ),
      ),
    );
  }

  @override
  void close() {
    closed = true;
  }
}
