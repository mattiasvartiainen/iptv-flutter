import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/logging/app_logger.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/xtream/xtream_api_client.dart';
import 'package:iptv_flutter/services/xtream/xtream_authentication.dart';

void main() {
  for (final oversized in [false, true]) {
    test('real HTTP authentication oversized=$oversized', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final subscription = server.listen((request) {
        expect(request.uri.path, '/panel/player_api.php');
        expect(
          request.uri.queryParameters.keys,
          unorderedEquals(['username', 'password']),
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'user_info': {
              'auth': 1,
              'status': 'Active',
              'password': 'must-not-escape',
            },
          }),
        );
        unawaited(request.response.close());
      });
      addTearDown(subscription.cancel);
      final client = XtreamApiClient(
        resolveCredentials: (playlistId, revision) async {
          expect(playlistId, 'expected-playlist');
          expect(revision, 7);
          return XtreamCredentials(
            endpoint: Uri.parse(
              'http://127.0.0.1:${server.port}/panel/player_api.php',
            ),
            username: 'user',
            password: 'pass',
            confirmed: true,
          );
        },
        maxResponseBytes: oversized ? 8 : 2048,
      );
      final result = await client.authenticate(
        playlistId: 'expected-playlist',
        connectionRevision: 7,
      );
      expect(
        result.failure,
        oversized ? XtreamAuthFailure.responseTooLarge : isNull,
      );
      if (!oversized) {
        expect(result.verification, SourceVerificationState.verified);
      }
    });
  }

  for (final retryAfter in [
    'invalid',
    '-1',
    '999999999',
    HttpDate.format(DateTime.utc(2000)),
  ]) {
    test('Retry-After is bounded ${retryAfter.length}', () async {
      final transport = _Transport({})
        ..response = XtreamAuthResponse(
          statusCode: 503,
          retryAfter: retryAfter,
          body: const Stream.empty(),
        );
      final result = await _authenticate(transport);
      if (retryAfter == 'invalid' || retryAfter == '-1') {
        expect(result.retryAfter, isNull);
      } else {
        expect(result.retryAfter!.inSeconds, inInclusiveRange(0, 86400));
      }
    });
  }
  for (final auth in [1, '1']) {
    for (final status in [
      'Active',
      'Expired',
      'Disabled',
      'Banned',
      'Unexpected',
    ]) {
      test('auth $auth is independent of account status $status', () async {
        final result = await _authenticate(
          _Transport({
            'user_info': {
              'auth': auth,
              'status': status,
              'exp_date': '1827868694',
              'active_cons': '0',
              'max_connections': 2,
            },
          }),
        );
        expect(result.verification, SourceVerificationState.verified);
        expect(result.accountState, switch (status) {
          'Active' => SourceAccountState.active,
          'Expired' => SourceAccountState.expired,
          'Disabled' => SourceAccountState.disabled,
          'Banned' => SourceAccountState.banned,
          _ => SourceAccountState.unknown,
        });
        expect(
          result.expiresAt,
          DateTime.fromMillisecondsSinceEpoch(1827868694000, isUtc: true),
        );
        expect(result.activeConnections, 0);
        expect(result.maxConnections, 2);
      });
    }
  }
  for (final auth in [0, '0']) {
    test('denied auth $auth is not unsupported API', () async {
      final result = await _authenticate(
        _Transport({
          'user_info': {'auth': auth},
        }),
      );
      expect(result.verification, SourceVerificationState.invalidCredentials);
      expect(result.failure, XtreamAuthFailure.denied);
    });
  }
  var fixtureNumber = 0;
  for (final payload in [
    {},
    {'server_info': {}},
    {'user_info': null},
    {'user_info': []},
    {
      'user_info': {'auth': true},
    },
    {
      'user_info': {'auth': 'true'},
    },
    {
      'user_info': {'auth': 1.0},
    },
    {
      'user_info': {'status': 'Active'},
    },
    [],
  ]) {
    test('rejects malformed auth fixture ${fixtureNumber++}', () async {
      expect(
        (await _authenticate(_Transport(payload))).failure,
        XtreamAuthFailure.malformedResponse,
      );
    });
  }
  for (final status in [
    301,
    302,
    307,
    308,
    401,
    403,
    407,
    404,
    429,
    500,
    503,
  ]) {
    test('HTTP $status is mapped without retry or body reading', () async {
      var bodyRead = false;
      final transport = _Transport({})
        ..response = XtreamAuthResponse(
          statusCode: status,
          retryAfter: '120',
          body: Stream.multi((controller) {
            bodyRead = true;
            controller.close();
          }),
        );
      final result = await _authenticate(transport);
      expect(result.failure, switch (status) {
        301 || 302 || 307 || 308 => XtreamAuthFailure.redirectRejected,
        401 || 403 => XtreamAuthFailure.denied,
        407 => XtreamAuthFailure.proxyAuthentication,
        404 => XtreamAuthFailure.unsupported,
        429 => XtreamAuthFailure.rateLimited,
        _ => XtreamAuthFailure.serverUnavailable,
      });
      expect(result.statusCode, status);
      expect(result.retryAfter, const Duration(seconds: 120));
      expect(transport.calls, 1);
      expect(bodyRead, isFalse);
      expect(transport.closed, isTrue);
    });
  }
  for (final bytes in [
    utf8.encode('<html>Login</html>'),
    utf8.encode('{'),
    [255],
  ]) {
    test('rejects invalid response bytes ${bytes.length}', () async {
      final transport = _Transport({})
        ..response = XtreamAuthResponse(
          statusCode: 200,
          body: Stream.value(bytes),
        );
      expect(
        (await _authenticate(transport)).failure,
        XtreamAuthFailure.malformedResponse,
      );
    });
  }
  for (final announced in [true, false]) {
    test('response byte cap announced=$announced', () async {
      final transport = _Transport({})
        ..response = XtreamAuthResponse(
          statusCode: 200,
          contentLength: announced ? 9 : null,
          body: Stream.fromIterable([
            [1, 2, 3],
            [4, 5, 6],
          ]),
        );
      final client = _client(transport, maxResponseBytes: 5);
      expect(
        (await client.authenticate(
          playlistId: 'p',
          connectionRevision: 1,
        )).failure,
        XtreamAuthFailure.responseTooLarge,
      );
      expect(transport.closed, isTrue);
    });
  }
  test(
    'malformed optional fields stay unknown and formats are immutable',
    () async {
      final result = await _authenticate(
        _Transport({
          'user_info': {
            'auth': 1,
            'status': null,
            'exp_date': '9999999999999999999',
            'active_cons': -1,
            'max_connections': 1.2,
            'allowed_output_formats': [null, 'evil', 'ts', 'ts'],
          },
        }),
      );
      expect(result.accountState, SourceAccountState.unknown);
      expect(result.expiresAt, isNull);
      expect(result.activeConnections, isNull);
      expect(result.maxConnections, isNull);
      expect(result.allowedOutputFormats, ['ts']);
      expect(() => result.allowedOutputFormats.clear(), throwsUnsupportedError);
    },
  );
  test(
    'logs only safe enums even when transport errors echo credentials',
    () async {
      final logger = _Logger();
      final transport = _Transport({})
        ..error = const SocketException(
          'password=secret https://user:pass@provider.example',
        );
      final result = await _client(
        transport,
        logger: logger,
      ).authenticate(playlistId: 'sensitive-name', connectionRevision: 1);
      expect(result.failure, XtreamAuthFailure.network);
      expect(logger.events.single, contains('network'));
      for (final secret in [
        'secret',
        'password',
        'provider.example',
        'sensitive-name',
        'user:pass',
      ]) {
        expect(logger.events.join(), isNot(contains(secret)));
        expect(result.toString(), isNot(contains(secret)));
      }
    },
  );
  test('TLS errors are distinct and not retried', () async {
    final transport = _Transport({})
      ..error = const HandshakeException('untrusted certificate');
    expect((await _authenticate(transport)).failure, XtreamAuthFailure.tls);
    expect(transport.calls, 1);
    expect(transport.closed, isTrue);
  });
  test('missing and unconfirmed credentials never open a transport', () async {
    for (final credentials in [
      null,
      XtreamCredentials(
        endpoint: _credentials.endpoint,
        username: 'u',
        password: 'p',
        confirmed: false,
      ),
    ]) {
      final client = XtreamApiClient(
        resolveCredentials: (_, _) async => credentials,
        createTransport: () => throw StateError('Must not open transport'),
      );
      expect(
        (await client.authenticate(
          playlistId: 'p',
          connectionRevision: 0,
        )).failure,
        credentials == null
            ? XtreamAuthFailure.missingCredentials
            : XtreamAuthFailure.confirmationRequired,
      );
    }
  });
  for (final endpoint in [
    'ftp://provider.example/player_api.php',
    'https://u:p@provider.example/player_api.php',
    'https://provider.example/player_api.php?token=secret',
    'https://provider.example/player_api.php#fragment',
    'https://provider.example/other.php',
  ]) {
    test(
      'invalid endpoint rejected before request ${fixtureNumber++}',
      () async {
        final client = XtreamApiClient(
          resolveCredentials: (_, _) async => XtreamCredentials(
            endpoint: Uri.parse(endpoint),
            username: 'u',
            password: 'p',
            confirmed: true,
          ),
          createTransport: () => throw StateError('Must not send secrets'),
        );
        expect(
          (await client.authenticate(
            playlistId: 'p',
            connectionRevision: 0,
          )).failure,
          XtreamAuthFailure.invalidEndpoint,
        );
      },
    );
  }
  test('cancellation during lookup prevents late request', () async {
    final credentials = Completer<XtreamCredentials?>();
    final cancellation = XtreamCancellation();
    var transports = 0;
    final client = XtreamApiClient(
      resolveCredentials: (_, _) => credentials.future,
      createTransport: () {
        transports++;
        return _Transport({});
      },
    );
    final pending = client.authenticate(
      playlistId: 'p',
      connectionRevision: 0,
      cancellation: cancellation,
    );
    cancellation.cancel();
    expect((await pending).failure, XtreamAuthFailure.cancelled);
    credentials.complete(_credentials);
    await Future<void>.value();
    expect(transports, 0);
  });
  test('pre-cancelled request does not resolve secrets', () async {
    final cancellation = XtreamCancellation()..cancel();
    final client = XtreamApiClient(
      resolveCredentials: (_, _) => throw StateError('No secrets needed'),
    );
    expect(
      (await client.authenticate(
        playlistId: 'p',
        connectionRevision: 0,
        cancellation: cancellation,
      )).failure,
      XtreamAuthFailure.cancelled,
    );
  });
  test('deadline includes lookup and prevents late request', () async {
    final credentials = Completer<XtreamCredentials?>();
    var transports = 0;
    final client = XtreamApiClient(
      resolveCredentials: (_, _) => credentials.future,
      createTransport: () {
        transports++;
        return _Transport({});
      },
      deadline: const Duration(milliseconds: 10),
    );
    expect(
      (await client.authenticate(
        playlistId: 'p',
        connectionRevision: 0,
      )).failure,
      XtreamAuthFailure.timeout,
    );
    credentials.complete(_credentials);
    await Future<void>.value();
    expect(transports, 0);
  });
  for (final cancel in [true, false]) {
    test('stalled response closes transport cancel=$cancel', () async {
      final opened = Completer<void>();
      final body = StreamController<List<int>>.broadcast();
      final transport = _Transport({})
        ..response = XtreamAuthResponse(statusCode: 200, body: body.stream);
      final cancellation = XtreamCancellation();
      final client = XtreamApiClient(
        resolveCredentials: (_, _) async => _credentials,
        createTransport: () {
          opened.complete();
          return transport;
        },
        deadline: const Duration(milliseconds: 30),
      );
      final pending = client.authenticate(
        playlistId: 'p',
        connectionRevision: 0,
        cancellation: cancellation,
      );
      await opened.future;
      if (cancel) cancellation.cancel();
      expect(
        (await pending).failure,
        cancel ? XtreamAuthFailure.cancelled : XtreamAuthFailure.timeout,
      );
      expect(transport.closed, isTrue);
      await body.close();
    });
  }
  test('real transport does not forward credentials across redirect', () async {
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => target.close(force: true));
    addTearDown(() => server.close(force: true));
    var targetRequests = 0;
    final subscription = target.listen((request) {
      targetRequests++;
      unawaited(request.response.close());
    });
    addTearDown(subscription.cancel);
    final requestSeen = Completer<Uri>();
    final serverSubscription = server.listen((request) {
      requestSeen.complete(request.uri);
      request.response.statusCode = 302;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'http://127.0.0.1:${target.port}/player_api.php',
      );
      unawaited(request.response.close());
    });
    addTearDown(serverSubscription.cancel);
    final client = XtreamApiClient(
      resolveCredentials: (_, _) async => XtreamCredentials(
        endpoint: Uri.parse(
          'http://127.0.0.1:${server.port}/panel/player_api.php',
        ),
        username: 'user +',
        password: ' pass& ',
        confirmed: true,
      ),
    );
    final result = await client.authenticate(
      playlistId: 'p',
      connectionRevision: 0,
    );
    expect(result.failure, XtreamAuthFailure.redirectRejected);
    expect((await requestSeen.future).queryParameters, {
      'username': 'user +',
      'password': ' pass& ',
    });
    expect(targetRequests, 0);
  });
}

final _credentials = XtreamCredentials(
  endpoint: Uri.parse('https://provider.example/panel/player_api.php'),
  username: 'user +',
  password: ' pass& ',
  confirmed: true,
);

class _Transport implements XtreamAuthTransport {
  _Transport(this.payload);
  final Object payload;
  int calls = 0;
  bool closed = false;
  Exception? error;
  XtreamAuthResponse? response;
  @override
  Future<XtreamAuthResponse> get(Uri authenticatedUri) async {
    calls++;
    if (error != null) throw error!;
    return response ??
        XtreamAuthResponse(
          statusCode: 200,
          body: Stream.value(utf8.encode(jsonEncode(payload))),
        );
  }

  @override
  void close() {
    closed = true;
  }
}

XtreamApiClient _client(
  _Transport transport, {
  int maxResponseBytes = 2 * 1024 * 1024,
  AppLogger logger = const DebugAppLogger(),
}) => XtreamApiClient(
  resolveCredentials: (_, _) async => _credentials,
  createTransport: () => transport,
  maxResponseBytes: maxResponseBytes,
  logger: logger,
);

Future<XtreamAuthResult> _authenticate(_Transport transport) =>
    _client(transport).authenticate(playlistId: 'p', connectionRevision: 1);

class _Logger implements AppLogger {
  final events = <String>[];
  @override
  void info(String message, {Map<String, Object?> context = const {}}) =>
      events.add('$message $context');
  @override
  void warning(String message, {Map<String, Object?> context = const {}}) =>
      events.add('$message $context');
  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) => events.add('$message $error $stackTrace $context');
}
