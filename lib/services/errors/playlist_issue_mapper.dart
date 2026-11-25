import '../catalog/catalog_import_worker.dart';
import '../security/url_redaction.dart';
import 'app_issue.dart';

AppIssue playlistIssueFor(
  Object error, {
  AppIssueSource source = AppIssueSource.playlistImport,
}) {
  if (error is AppIssueException) return error.issue;
  final isImport = source == AppIssueSource.playlistImport;
  if (isImport && error is CatalogImportWorkerException) {
    final status = error.diagnostics['http.response.status_code'];
    final kind = switch (error.errorType) {
      'TimeoutException' => AppIssueKind.timeout,
      'SocketException' => AppIssueKind.networkUnavailable,
      'HttpException' when status == 511 =>
        AppIssueKind.networkAuthenticationRequired,
      'HttpException' when status == 401 || status == 403 =>
        AppIssueKind.authorizationFailure,
      _ => AppIssueKind.unknown,
    };
    return AppIssue(
      kind: kind,
      source: source,
      title: switch (kind) {
        AppIssueKind.timeout => 'Playlist request timed out',
        AppIssueKind.networkUnavailable => 'Network unavailable',
        AppIssueKind.networkAuthenticationRequired =>
          'Network sign-in may be required',
        AppIssueKind.authorizationFailure => 'Access denied',
        _ => 'Import failed',
      },
      message: switch (kind) {
        AppIssueKind.timeout => 'The playlist server took too long to respond.',
        AppIssueKind.networkUnavailable =>
          'Could not connect to the playlist server.',
        AppIssueKind.networkAuthenticationRequired =>
          'The playlist request was blocked (HTTP 511). Check whether your '
              'device\'s internet connection requires sign-in. If other services '
              'work, contact your playlist provider.',
        AppIssueKind.authorizationFailure =>
          'The playlist server rejected the request.',
        _ => 'Could not load that playlist. Try again.',
      },
    );
  }
  final invalidFormat = isImport && error is FormatException;
  return AppIssue(
    kind: invalidFormat
        ? AppIssueKind.playlistFormatInvalid
        : AppIssueKind.unknown,
    source: source,
    title: invalidFormat ? 'Playlist format invalid' : 'Import failed',
    message: invalidFormat
        ? 'The playlist could not be parsed.'
        : 'Could not load that playlist. Try again.',
    details: isImport ? redactSensitiveText(error.toString()) : null,
  );
}
