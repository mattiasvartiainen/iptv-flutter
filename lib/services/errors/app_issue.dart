enum AppIssueKind {
  invalidUrl,
  networkUnavailable,
  timeout,
  authorizationFailure,
  playlistFormatInvalid,
  playlistEmpty,
  storageUnavailable,
  mediaUnsupported,
  unknown,
}

enum AppIssueSource {
  setup,
  playlistImport,
  settings,
  playback,
  storage,
  unknown,
}

class AppIssue {
  const AppIssue({
    required this.kind,
    required this.source,
    required this.title,
    required this.message,
    this.details,
    this.retryable = true,
  });

  final AppIssueKind kind;
  final AppIssueSource source;
  final String title;
  final String message;
  final String? details;
  final bool retryable;
}

class AppIssueException implements Exception {
  const AppIssueException(this.issue, {this.cause, this.stackTrace});

  final AppIssue issue;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'AppIssueException(${issue.kind.name}, ${issue.source.name}, ${issue.message})';
}
