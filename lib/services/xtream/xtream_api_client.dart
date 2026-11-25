import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import '../metadata/movie_metadata.dart';
import '../sources/source_contracts.dart';
import 'bounded_xtream_json.dart';
import 'xtream_authentication.dart';
import 'xtream_series_metadata.dart';
import 'xtream_vod_metadata.dart';

class XtreamApiClient {
  XtreamApiClient({
    required XtreamCredentialResolver resolveCredentials,
    XtreamAuthTransport Function()? createTransport,
    AppLogger logger = const DebugAppLogger(),
    this.deadline = const Duration(seconds: 30),
    this.maxResponseBytes = 2 * 1024 * 1024,
  }) : _resolveCredentials = resolveCredentials,
       _createTransport = createTransport ?? IoXtreamAuthTransport.new,
       _logger = logger {
    if (deadline <= Duration.zero || maxResponseBytes < 1) {
      throw ArgumentError('Authentication limits must be positive.');
    }
  }

  final XtreamCredentialResolver _resolveCredentials;
  final XtreamAuthTransport Function() _createTransport;
  final AppLogger _logger;
  final Duration deadline;
  final int maxResponseBytes;

  Future<XtreamAuthResult> authenticate({
    required String playlistId,
    required int connectionRevision,
    XtreamCancellation? cancellation,
  }) async {
    final response = await _request(
      playlistId: playlistId,
      connectionRevision: connectionRevision,
      cancellation: cancellation,
      byteLimit: maxResponseBytes,
      decode: (bytes, _) => compute(_decodeTransferredAuthentication, bytes),
    );
    final result =
        response.value ??
        _failure(
          response.failure!,
          status: response.status,
          retryAfter: response.retryAfter,
        );
    _logger.info(
      'xtream_authentication_completed',
      context: {
        'verification': result.verification.name,
        if (result.failure != null) 'failure': result.failure!.name,
        if (result.statusCode != null) 'statusCode': result.statusCode,
      },
    );
    return result;
  }

  Future<MovieMetadataResult> getVodInfo({
    required String playlistId,
    required int connectionRevision,
    required String movieId,
    required XtreamCancellation cancellation,
    int byteLimit = 10 * 1024 * 1024,
  }) async {
    if (positiveProviderId(movieId) == null || byteLimit < 1) {
      throw ArgumentError('Invalid movie detail request.');
    }
    final response = await _request(
      playlistId: playlistId,
      connectionRevision: connectionRevision,
      cancellation: cancellation,
      byteLimit: byteLimit,
      parameters: {'action': 'get_vod_info', 'vod_id': movieId},
      decode: (bytes, credentials) =>
          compute(decodeTransferredXtreamVod, (bytes, movieId, credentials)),
    );
    final result =
        response.value ??
        MovieMetadataResult(
          failure: _metadataFailure(response.failure!),
          retryAfter: response.retryAfter,
        );
    _logger.info(
      'xtream_movie_metadata_completed',
      context: {if (result.failure != null) 'failure': result.failure!.name},
    );
    return result;
  }

  Future<_RequestResult<T>> _request<T>({
    required String playlistId,
    required int connectionRevision,
    required int byteLimit,
    required FutureOr<T> Function(TransferableTypedData, XtreamCredentials) decode,
    Map<String, String> parameters = const {},
    XtreamCancellation? cancellation,
  }) async {
    if (connectionRevision < 0) throw ArgumentError('Invalid revision.');
    final operation = cancellation ?? XtreamCancellation();
    XtreamAuthTransport? transport;
    var finished = false;
    Future<_RequestResult<T>> perform() async {
      if (operation.isCancelled) throw XtreamAuthFailure.cancelled;
      final credentials = await _resolveCredentials(
        playlistId,
        connectionRevision,
      );
      if (finished || operation.isCancelled) throw XtreamAuthFailure.cancelled;
      if (credentials == null) throw XtreamAuthFailure.missingCredentials;
      if (!credentials.confirmed) throw XtreamAuthFailure.confirmationRequired;
      final endpoint = credentials.endpoint;
      if ((endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
          endpoint.host.isEmpty ||
          endpoint.userInfo.isNotEmpty ||
          endpoint.hasQuery ||
          endpoint.hasFragment ||
          endpoint.port < 1 ||
          endpoint.port > 65535 ||
          endpoint.pathSegments.isEmpty ||
          endpoint.pathSegments.last != 'player_api.php' ||
          credentials.username.trim().isEmpty ||
          credentials.password.isEmpty) {
        throw XtreamAuthFailure.invalidEndpoint;
      }
      transport = _createTransport();
      final response = await transport!.get(
        endpoint.replace(
          queryParameters: {
            'username': credentials.username,
            'password': credentials.password,
            ...parameters,
          },
        ),
      );
      if (finished || operation.isCancelled) throw XtreamAuthFailure.cancelled;
      final status = response.statusCode;
      if (status != 200) {
        final failure = switch (status) {
          >= 300 && < 400 => XtreamAuthFailure.redirectRejected,
          401 || 403 => XtreamAuthFailure.denied,
          404 => XtreamAuthFailure.unsupported,
          407 => XtreamAuthFailure.proxyAuthentication,
          429 => XtreamAuthFailure.rateLimited,
          >= 500 => XtreamAuthFailure.serverUnavailable,
          _ => XtreamAuthFailure.network,
        };
        return _RequestResult(
          failure: failure,
          status: status,
          retryAfter: _retryAfter(response.retryAfter),
        );
      }
      if ((response.contentLength ?? 0) > byteLimit) {
        throw XtreamAuthFailure.responseTooLarge;
      }
      final bytes = Uint8List(byteLimit);
      var length = 0;
      await for (final chunk in response.body) {
        if (finished || operation.isCancelled) {
          throw XtreamAuthFailure.cancelled;
        }
        if (length + chunk.length > byteLimit) {
          throw XtreamAuthFailure.responseTooLarge;
        }
        bytes.setRange(length, length + chunk.length, chunk);
        length += chunk.length;
      }
      final transferred = TransferableTypedData.fromList([
        Uint8List.sublistView(bytes, 0, length),
      ]);
      return _RequestResult(value: await decode(transferred, credentials));
    }

    try {
      return await Future.any<_RequestResult<T>>([
        perform(),
        operation.whenCancelled.then((_) => throw XtreamAuthFailure.cancelled),
      ]).timeout(deadline);
    } on XtreamAuthFailure catch (failure) {
      return _RequestResult(failure: failure);
    } on XtreamJsonLimitException {
      return const _RequestResult(failure: XtreamAuthFailure.responseTooLarge);
    } on TimeoutException {
      return const _RequestResult(failure: XtreamAuthFailure.timeout);
    } on HandshakeException {
      return const _RequestResult(failure: XtreamAuthFailure.tls);
    } on FormatException {
      return const _RequestResult(failure: XtreamAuthFailure.malformedResponse);
    } on IOException {
      return const _RequestResult(failure: XtreamAuthFailure.network);
    } finally {
      finished = true;
      transport?.close();
    }
  }

  Future<XtreamSeriesResponse> seriesRequest({
    required String playlistId,
    required int connectionRevision,
    required String action,
    required XtreamCancellation cancellation,
    required String title,
    required String group,
    String? categoryId,
    String? seriesId,
    Set<String> episodeIds = const {},
  }) async {
    if (!const [
          'get_series_categories',
          'get_series',
          'get_series_info',
        ].contains(action) ||
        (action == 'get_series' && positiveProviderId(categoryId) == null) ||
        (action == 'get_series_info' && positiveProviderId(seriesId) == null)) {
      throw ArgumentError('Invalid series request.');
    }
    final response = await _request(
      playlistId: playlistId,
      connectionRevision: connectionRevision,
      cancellation: cancellation,
      byteLimit: 10 * 1024 * 1024,
      parameters: {
        'action': action,
        'category_id': ?categoryId,
        'series_id': ?seriesId,
      },
      decode: (bytes, credentials) => compute(
        decodeXtreamSeries,
        XtreamSeriesRequest.transferred(
          transferableBytes: bytes,
          action: action,
          credentials: credentials,
          title: title,
          group: group,
          seriesId: seriesId,
          episodeIds: episodeIds,
        ),
      ),
    );
    final result =
        response.value ??
        XtreamSeriesResponse(
          failure: _metadataFailure(response.failure!),
          retryAfter: response.retryAfter,
        );
    _logger.info(
      'xtream_series_metadata_completed',
      context: {
        'action': action,
        if (result.failure != null) 'failure': result.failure!.name,
      },
    );
    return result;
  }
}

class _RequestResult<T> {
  const _RequestResult({
    this.value,
    this.failure,
    this.status,
    this.retryAfter,
  });
  final T? value;
  final XtreamAuthFailure? failure;
  final int? status;
  final Duration? retryAfter;
}

MetadataFailure _metadataFailure(XtreamAuthFailure failure) =>
    switch (failure) {
      XtreamAuthFailure.denied => MetadataFailure.denied,
      XtreamAuthFailure.unsupported => MetadataFailure.unsupported,
      XtreamAuthFailure.malformedResponse => MetadataFailure.malformed,
      XtreamAuthFailure.rateLimited => MetadataFailure.rateLimited,
      XtreamAuthFailure.timeout => MetadataFailure.timeout,
      XtreamAuthFailure.cancelled => MetadataFailure.cancelled,
      XtreamAuthFailure.responseTooLarge => MetadataFailure.tooLarge,
      XtreamAuthFailure.missingCredentials ||
      XtreamAuthFailure.confirmationRequired => MetadataFailure.unverified,
      _ => MetadataFailure.network,
    };

XtreamAuthResult _decodeTransferredAuthentication(TransferableTypedData bytes) {
  try {
    return _decodeAuthentication(bytes.materialize().asUint8List());
  } on XtreamAuthFailure catch (failure) {
    return _failure(failure);
  }
}

XtreamAuthResult _decodeAuthentication(List<int> bytes) {
  final decoded = decodeBoundedXtreamJson(bytes);
  if (decoded is! Map<String, dynamic> ||
      decoded['user_info'] is! Map<String, dynamic>) {
    throw XtreamAuthFailure.malformedResponse;
  }
  final user = decoded['user_info'] as Map<String, dynamic>;
  final auth = user['auth'];
  if ((auth is int && auth == 0) || auth == '0') {
    return _failure(XtreamAuthFailure.denied);
  }
  if (!(auth is int && auth == 1) && auth != '1') {
    throw XtreamAuthFailure.malformedResponse;
  }
  final expires = _nonNegativeInt(user['exp_date']);
  final formats = user['allowed_output_formats'];
  return XtreamAuthResult(
    verification: SourceVerificationState.verified,
    accountState: switch (user['status']) {
      final String status => switch (status.toLowerCase()) {
        'active' => SourceAccountState.active,
        'expired' => SourceAccountState.expired,
        'disabled' => SourceAccountState.disabled,
        'banned' => SourceAccountState.banned,
        _ => SourceAccountState.unknown,
      },
      _ => SourceAccountState.unknown,
    },
    expiresAt: expires != null && expires > 0 && expires <= 8640000000000
        ? DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true)
        : null,
    activeConnections: _nonNegativeInt(user['active_cons']),
    maxConnections: _nonNegativeInt(user['max_connections']),
    allowedOutputFormats: List.unmodifiable(
      formats is List
          ? formats
                .whereType<String>()
                .where(const {'ts', 'm3u8', 'rtmp'}.contains)
                .toSet()
          : <String>[],
    ),
  );
}

int? _nonNegativeInt(Object? value) {
  final number = value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  return number != null && number >= 0 ? number : null;
}

Duration? _retryAfter(String? value) {
  if (value == null) return null;
  final seconds = int.tryParse(value);
  if (seconds != null && seconds >= 0) {
    return Duration(seconds: seconds.clamp(0, 86400));
  }
  try {
    final difference = HttpDate.parse(value).difference(DateTime.now().toUtc());
    return Duration(seconds: difference.inSeconds.clamp(0, 86400));
  } on FormatException {
    return null;
  }
}

XtreamAuthResult _failure(
  XtreamAuthFailure failure, {
  int? status,
  Duration? retryAfter,
}) => XtreamAuthResult(
  verification: switch (failure) {
    XtreamAuthFailure.denied => SourceVerificationState.invalidCredentials,
    XtreamAuthFailure.unsupported => SourceVerificationState.unsupported,
    _ => SourceVerificationState.temporarilyUnavailable,
  },
  failure: failure,
  statusCode: status,
  retryAfter: retryAfter,
);

class IoXtreamAuthTransport implements XtreamAuthTransport {
  IoXtreamAuthTransport() : _client = HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 10);
  }

  final HttpClient _client;

  @override
  Future<XtreamAuthResponse> get(Uri authenticatedUri) async {
    final request = await _client.getUrl(authenticatedUri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    return XtreamAuthResponse(
      statusCode: response.statusCode,
      body: response,
      contentLength: response.contentLength < 0 ? null : response.contentLength,
      retryAfter: response.headers.value(HttpHeaders.retryAfterHeader),
    );
  }

  @override
  void close() => _client.close(force: true);
}
