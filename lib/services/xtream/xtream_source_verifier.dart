import '../settings/settings_repository.dart' show PlaylistSourceConfig;
import '../sources/source_contracts.dart';
import '../sources/source_verification_candidate.dart';
import '../sources/source_verifier.dart';
import 'xtream_api_client.dart';
import 'xtream_authentication.dart';

typedef XtreamDraftClientFactory =
    XtreamApiClient Function(XtreamCredentialResolver resolveCredentials);

class XtreamSourceVerifier implements SourceVerifier {
  XtreamSourceVerifier({XtreamDraftClientFactory? createClient})
    : _createClient = createClient ?? _defaultClient;

  final XtreamDraftClientFactory _createClient;

  static XtreamApiClient _defaultClient(XtreamCredentialResolver resolver) =>
      XtreamApiClient(resolveCredentials: resolver);

  @override
  Future<XtreamAuthResult> verify(
    PlaylistSourceConfig config, {
    required bool confirmed,
    required XtreamCancellation cancellation,
  }) async {
    if (cancellation.isCancelled) return _failure(XtreamAuthFailure.cancelled);
    final candidate = sourceVerificationCandidate(config);
    if (candidate == null) return _failure(XtreamAuthFailure.invalidEndpoint);
    if (candidate.requiresConfirmation && !confirmed) {
      return _failure(XtreamAuthFailure.confirmationRequired);
    }
    try {
      final client = _createClient(
        (_, _) async => XtreamCredentials(
          endpoint: candidate.endpoint,
          username: candidate.username,
          password: candidate.password,
          confirmed: true,
        ),
      );
      return await client.authenticate(
        playlistId: config.playlistId ?? 'editor-draft',
        connectionRevision: 0,
        cancellation: cancellation,
      );
    } catch (_) {
      return _failure(XtreamAuthFailure.network);
    }
  }
}

XtreamAuthResult _failure(XtreamAuthFailure failure) => XtreamAuthResult(
  verification: SourceVerificationState.temporarilyUnavailable,
  failure: failure,
);
