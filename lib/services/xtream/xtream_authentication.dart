import 'dart:async';

import '../sources/source_contracts.dart';

class XtreamCredentials {
  const XtreamCredentials({
    required this.endpoint,
    required this.username,
    required this.password,
    required this.confirmed,
  });

  final Uri endpoint;
  final String username;
  final String password;
  final bool confirmed;
}

typedef XtreamCredentialResolver =
    Future<XtreamCredentials?> Function(
      String playlistId,
      int connectionRevision,
    );

enum XtreamAuthFailure {
  missingCredentials,
  invalidEndpoint,
  confirmationRequired,
  denied,
  unsupported,
  malformedResponse,
  proxyAuthentication,
  rateLimited,
  serverUnavailable,
  redirectRejected,
  tls,
  network,
  timeout,
  cancelled,
  responseTooLarge,
}

class XtreamAuthResult {
  const XtreamAuthResult({
    required this.verification,
    this.accountState = SourceAccountState.unknown,
    this.failure,
    this.statusCode,
    this.retryAfter,
    this.expiresAt,
    this.activeConnections,
    this.maxConnections,
    this.allowedOutputFormats = const [],
  });

  final SourceVerificationState verification;
  final SourceAccountState accountState;
  final XtreamAuthFailure? failure;
  final int? statusCode;
  final Duration? retryAfter;
  final DateTime? expiresAt;
  final int? activeConnections;
  final int? maxConnections;
  final List<String> allowedOutputFormats;
}

class XtreamCancellation {
  final _completion = Completer<void>();
  bool get isCancelled => _completion.isCompleted;
  Future<void> get whenCancelled => _completion.future;
  void cancel() {
    if (!isCancelled) _completion.complete();
  }
}

abstract interface class XtreamAuthTransport {
  Future<XtreamAuthResponse> get(Uri authenticatedUri);
  void close();
}

class XtreamAuthResponse {
  const XtreamAuthResponse({
    required this.statusCode,
    required this.body,
    this.contentLength,
    this.retryAfter,
  });

  final int statusCode;
  final Stream<List<int>> body;
  final int? contentLength;
  final String? retryAfter;
}
