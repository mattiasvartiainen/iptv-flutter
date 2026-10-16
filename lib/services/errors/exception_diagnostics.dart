import '../catalog/catalog_import_worker.dart';
import '../security/url_redaction.dart';
import 'app_issue.dart';

String formatExceptionDiagnostics(Object error, StackTrace stackTrace) {
  final cause = error is AppIssueException ? error.cause ?? error : error;
  final originalStack = error is AppIssueException
      ? error.stackTrace ?? stackTrace
      : stackTrace;
  final diagnosticStack =
      cause is CatalogImportWorkerException && cause.workerStackTrace.isNotEmpty
      ? cause.workerStackTrace
      : originalStack.toString();
  return redactSensitiveText(
    'Exception: $cause\n'
    '${error is AppIssueException && error.issue.details != null ? '${error.issue.details}\n' : ''}'
    '\nStack trace:\n$diagnosticStack',
  );
}
