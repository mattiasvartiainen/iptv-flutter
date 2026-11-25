import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/metadata/movie_metadata.dart';
import 'package:iptv_flutter/services/xtream/bounded_xtream_json.dart';
import 'package:iptv_flutter/services/xtream/xtream_api_client.dart';
import 'package:iptv_flutter/services/xtream/xtream_authentication.dart';
import 'package:iptv_flutter/services/xtream/xtream_movie_metadata_provider.dart';
import 'package:iptv_flutter/services/xtream/xtream_vod_metadata.dart';

final credentials = XtreamCredentials(
  endpoint: Uri.parse('https://provider.example/panel/player_api.php'),
  username: 'account+name',
  password: 'secret & value',
  confirmed: true,
);

Map<String, Object?> vodPayload({Object id = '42'}) => {
  'movie_data': {'stream_id': id, 'name': 'Fixture Movie'},
  'info': {
    'plot': 'A real synopsis.',
    'genre': 'Drama',
    'releasedate': '2025-03-04',
    'duration_secs': '7200',
    'rating': '8.2',
    'director': 'Fixture Director',
    'cast': 'First Actor, Second Actor',
    'tmdb_id': '123',
    'movie_image': 'https://images.example/poster.jpg',
    'backdrop_path': ['https://images.example/backdrop.jpg'],
  },
};

void main() {
  test('tiny chunks and exact byte threshold decode without a boxed growable buffer', () async {
    final bytes = utf8.encode(jsonEncode(vodPayload()));
    final transport = _Transport(vodPayload())..chunks = bytes.map((byte) => Uint8List.fromList([byte]));
    final client = XtreamApiClient(resolveCredentials: (_, _) async => credentials,
      createTransport: () => transport);
    expect((await client.getVodInfo(playlistId: 'p', connectionRevision: 1,
      movieId: '42', cancellation: XtreamCancellation(), byteLimit: bytes.length)).metadata, isNotNull);
    final oversized = _Transport(vodPayload())..chunks = [Uint8List.fromList([...bytes, 32])];
    expect((await XtreamApiClient(resolveCredentials: (_, _) async => credentials,
      createTransport: () => oversized).getVodInfo(playlistId: 'p', connectionRevision: 1,
      movieId: '42', cancellation: XtreamCancellation(), byteLimit: bytes.length)).failure,
      MetadataFailure.tooLarge);
    expect(oversized.closed, isTrue);
  });
  for (final excessive in [
    List.filled(maxXtreamJsonNodes, 0),
    'x' * (maxXtreamJsonStringBytes + 1),
    List.generate(maxXtreamJsonDepth + 1, (_) => 0).fold<Object>(0, (value, _) => [value]),
  ]) {
    test('allocation-heavy JSON below wire cap surfaces tooLarge (${excessive.runtimeType})', () async {
      final transport = _Transport(excessive);
      expect((await _fetch(transport)).failure, MetadataFailure.tooLarge);
      expect(transport.closed, isTrue);
    });
  }
  test('movie identity matches verified origin/base path/account and kind', () {
    final movie = Uri(
      scheme: 'https',
      host: 'provider.example',
      pathSegments: [
        'panel',
        'movie',
        credentials.username,
        credentials.password,
        '42.mp4',
      ],
    ).toString();
    expect(xtreamMovieId(movie, credentials), '42');
    for (final invalid in [
      movie.replaceFirst('https:', 'http:'),
      movie.replaceFirst('provider.example', 'other.example'),
      movie.replaceFirst('/panel/', '/other/'),
      movie.replaceFirst('/movie/', '/series/'),
      Uri.parse(movie)
          .replace(
            pathSegments: [
              'panel',
              'movie',
              'other',
              credentials.password,
              '42.mp4',
            ],
          )
          .toString(),
      'https://provider.example/panel/42',
      '$movie?token=unknown',
      movie.replaceFirst('42.mp4', '0.mp4'),
      movie.replaceFirst('42.mp4', '{XUI_ID}.mp4'),
    ]) {
      expect(
        xtreamMovieId(invalid, credentials),
        isNull,
        reason: 'Invalid mapping',
      );
    }
  });

  test(
    'normalizes optional fields, runtime/rating and field provenance',
    () async {
      final transport = _Transport(vodPayload(id: 42));
      final result = await _fetch(transport);
      expect(result.failure, isNull);
      expect(result.metadata![MovieMetadataField.plot], 'A real synopsis.');
      expect(result.metadata![MovieMetadataField.runtime], '120 min');
      expect(result.metadata![MovieMetadataField.rating], '8.2/10 (Xtream)');
      expect(result.metadata!.sources.values.toSet(), {'xtream'});
      expect(transport.uri!.path, '/panel/player_api.php');
      expect(transport.uri!.queryParameters, {
        'username': credentials.username,
        'password': credentials.password,
        'action': 'get_vod_info',
        'vod_id': '42',
      });
      expect(transport.closed, isTrue);
    },
  );

  test(
    'metadata cannot echo credentials or credential-bearing artwork',
    () async {
      final payload = vodPayload();
      payload['info'] = {
        'plot':
            '${credentials.username} ${credentials.password} '
            'https://provider.example/movie/u/p/42.mp4',
        'movie_image': 'https://images.example/cover?token=secret',
        'backdrop_path': ['https://provider.example/movie/u/p/backdrop.jpg'],
        'username': credentials.username,
        'password': credentials.password,
      };
      final result = await _fetch(_Transport(payload));
      final values = result.metadata!.fields.values.join(' ');
      expect(values, isNot(contains(credentials.username)));
      expect(values, isNot(contains(credentials.password)));
      expect(values, isNot(contains('/u/p/')));
      expect(result.metadata![MovieMetadataField.poster], isNull);
      expect(result.metadata![MovieMetadataField.backdrop], isNull);
    },
  );

  for (final payload in [
    vodPayload(id: '99'),
    {},
    [],
    {'info': {}, 'movie_data': []},
    {
      'info': {},
      'movie_data': {'stream_id': '42', 'stream_type': 'live'},
    },
  ]) {
    test(
      'rejects malformed or wrong movie identity ${payload.runtimeType}',
      () async {
        expect(
          (await _fetch(_Transport(payload))).failure,
          MetadataFailure.malformed,
        );
      },
    );
  }

  test('missing/invalid fields are absent rather than fabricated', () {
    final result = normalizeXtreamVod(
      {
        'movie_data': {'stream_id': '42'},
        'info': {
          'plot': '',
          'rating': 20,
          'duration_secs': -1,
          'releasedate': 'not-a-date',
          'movie_image': '/relative.jpg',
        },
      },
      '42',
      credentials,
    );
    expect(result.failure, isNull);
    expect(result.metadata!.fields, isEmpty);
  });

  test('empty primary fields fall back and impossible dates are omitted', () {
    final result = normalizeXtreamVod(
      {
        'movie_data': {'stream_id': '42', 'name': 'Catalog title'},
        'info': {
          'name': '',
          'plot': 'N/A',
          'description': 'Useful synopsis',
          'cast': '',
          'actors': 'Useful cast',
          'releasedate': '2025-99-99',
          'movie_image': '',
          'cover_big': 'https://images.example/poster.jpg?raw=true',
        },
      },
      '42',
      credentials,
    );
    expect(result.metadata![MovieMetadataField.plot], 'Useful synopsis');
    expect(result.metadata![MovieMetadataField.cast], 'Useful cast');
    expect(result.metadata![MovieMetadataField.title], 'Catalog title');
    expect(result.metadata![MovieMetadataField.releaseDate], isNull);
    expect(result.metadata![MovieMetadataField.poster], endsWith('?raw=true'));
  });

  test(
    'HTTP 200 denied-account echo remains an authentication failure',
    () async {
      expect(
        (await _fetch(
          _Transport({
            'user_info': {'auth': '0'},
          }),
        )).failure,
        MetadataFailure.denied,
      );
    },
  );

  for (final (status, failure) in [
    (302, MetadataFailure.network),
    (401, MetadataFailure.denied),
    (404, MetadataFailure.unsupported),
    (429, MetadataFailure.rateLimited),
    (503, MetadataFailure.network),
  ]) {
    test('HTTP $status surfaces a safe failure and closes transport', () async {
      final transport = _Transport(vodPayload())..status = status;
      final result = await _fetch(transport);
      expect(result.failure, failure);
      if (status == 429) expect(result.retryAfter, const Duration(seconds: 30));
      expect(transport.closed, isTrue);
    });
  }

  test('enforces streamed byte limit, deadline and cancellation', () async {
    final oversized = _Transport(vodPayload());
    final result =
        await XtreamApiClient(
          resolveCredentials: (_, _) async => credentials,
          createTransport: () => oversized,
        ).getVodInfo(
          playlistId: 'p',
          connectionRevision: 1,
          movieId: '42',
          cancellation: XtreamCancellation(),
          byteLimit: 10,
        );
    expect(result.failure, MetadataFailure.tooLarge);
    expect(oversized.closed, isTrue);

    for (final cancel in [false, true]) {
      final waiting = _Transport(vodPayload())
        ..gate = Completer<XtreamAuthResponse>();
      final operation = XtreamCancellation();
      final request =
          XtreamApiClient(
            resolveCredentials: (_, _) async => credentials,
            createTransport: () => waiting,
            deadline: const Duration(milliseconds: 30),
          ).getVodInfo(
            playlistId: 'p',
            connectionRevision: 1,
            movieId: '42',
            cancellation: operation,
          );
      await waiting.started.future;
      if (cancel) operation.cancel();
      expect(
        (await request).failure,
        cancel ? MetadataFailure.cancelled : MetadataFailure.timeout,
      );
      expect(waiting.closed, isTrue);
      waiting.gate!.complete(waiting.response);
    }
  });
}

Future<MovieMetadataResult> _fetch(_Transport transport) =>
    XtreamApiClient(
      resolveCredentials: (_, _) async => credentials,
      createTransport: () => transport,
    ).getVodInfo(
      playlistId: 'p',
      connectionRevision: 1,
      movieId: '42',
      cancellation: XtreamCancellation(),
    );

class _Transport implements XtreamAuthTransport {
  _Transport(this.payload);
  final Object payload;
  int status = 200;
  Uri? uri;
  bool closed = false;
  Iterable<List<int>>? chunks;
  Completer<XtreamAuthResponse>? gate;
  final started = Completer<void>();
  XtreamAuthResponse get response => XtreamAuthResponse(
    statusCode: status,
    retryAfter: '30',
    body: chunks == null ? Stream.value(utf8.encode(jsonEncode(payload))) : Stream.fromIterable(chunks!),
  );
  @override
  Future<XtreamAuthResponse> get(Uri authenticatedUri) async {
    uri = authenticatedUri;
    started.complete();
    return gate == null ? response : gate!.future;
  }

  @override
  void close() {
    closed = true;
  }
}
