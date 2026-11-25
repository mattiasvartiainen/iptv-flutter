import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_worker.dart';
import 'package:iptv_flutter/services/errors/app_issue.dart';
import 'package:iptv_flutter/services/errors/playlist_issue_mapper.dart';

void main() {
  for (final (status, kind) in [
    (401, AppIssueKind.authorizationFailure),
    (403, AppIssueKind.authorizationFailure),
    (511, AppIssueKind.networkAuthenticationRequired),
    (500, AppIssueKind.unknown),
  ]) {
    test('maps structured HTTP $status without inspecting exception text', () {
      final issue = playlistIssueFor(
        CatalogImportWorkerException(
          errorType: 'HttpException',
          message: 'untrusted 401 403 511 https://secret.test/private-password',
          workerStackTrace: '',
          diagnostics: {'http.response.status_code': status},
        ),
      );

      expect(issue.kind, kind);
      expect(issue.source, AppIssueSource.playlistImport);
      expect(issue.retryable, isTrue);
      expect(issue.message, isNot(contains('private-password')));
      if (status == 511) {
        expect(issue.title, 'Network sign-in may be required');
        expect(issue.message, contains('HTTP 511'));
        expect(issue.message, contains('If other services work'));
        expect(issue.message, isNot(contains('password')));
      }
    });
  }

  test('does not classify a status mentioned only in exception text', () {
    final issue = playlistIssueFor(
      const CatalogImportWorkerException(
        errorType: 'HttpException',
        message: 'HTTP 511 and 401',
        workerStackTrace: '',
      ),
    );
    expect(issue.kind, AppIssueKind.unknown);
  });

  test('preserves typed failures and their retry policy', () {
    const issue = AppIssue(
      kind: AppIssueKind.storageUnavailable,
      source: AppIssueSource.storage,
      title: 'Storage unavailable',
      message: 'Could not save your settings.',
      retryable: false,
    );
    expect(playlistIssueFor(const AppIssueException(issue)), same(issue));
  });
}
