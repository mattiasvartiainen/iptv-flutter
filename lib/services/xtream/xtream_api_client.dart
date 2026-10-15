import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';
import '../sources/source_contracts.dart';
import 'xtream_authentication.dart';

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
    if (connectionRevision < 0) throw ArgumentError('Invalid revision.');
    final operation = cancellation ?? XtreamCancellation();
    XtreamAuthTransport? transport;
    var finished = false;
    Future<XtreamAuthResult> perform() async {
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
        return _failure(
          failure,
          status: status,
          retryAfter: _retryAfter(response.retryAfter),
        );
      }
      if ((response.contentLength ?? 0) > maxResponseBytes) {
        throw XtreamAuthFailure.responseTooLarge;
      }
      final bytes = <int>[];
      await for (final chunk in response.body) {
        if (finished || operation.isCancelled) {
          throw XtreamAuthFailure.cancelled;
        }
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw XtreamAuthFailure.responseTooLarge;
        }
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
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

    XtreamAuthResult result;
    try {
      result = await Future.any<XtreamAuthResult>([
        perform(),
        operation.whenCancelled.then((_) => throw XtreamAuthFailure.cancelled),
      ]).timeout(deadline);
    } on XtreamAuthFailure catch (failure) {
      result = _failure(failure);
    } on TimeoutException {
      result = _failure(XtreamAuthFailure.timeout);
    } on HandshakeException {
      result = _failure(XtreamAuthFailure.tls);
    } on FormatException {
      result = _failure(XtreamAuthFailure.malformedResponse);
    } on Exception {
      result = _failure(XtreamAuthFailure.network);
    } finally {
      finished = true;
      transport?.close();
    }
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
