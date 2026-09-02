/// Coarse-grained phase of a playlist refresh, surfaced to the UI when the
/// user opts in via the "Display verbose information" setting.
enum CatalogImportPhase { downloading, importing }

class CatalogImportProgress {
  const CatalogImportProgress({
    required this.phase,
    required this.startedAt,
    this.current,
    this.total,
    this.message,
  });

  final CatalogImportPhase phase;

  /// When the overall refresh (download + import) began, so the UI can
  /// keep ticking an elapsed-time display between progress callbacks.
  final DateTime startedAt;

  /// Bytes received (downloading) or items processed (importing).
  final int? current;

  /// Total bytes (if known from Content-Length) or total items to import.
  final int? total;

  final String? message;

  /// 0.0-1.0, or null when the total is unknown (e.g. chunked download).
  double? get fraction {
    final current = this.current;
    final total = this.total;
    if (current == null || total == null || total <= 0) return null;
    return (current / total).clamp(0.0, 1.0);
  }

  Duration get elapsed => DateTime.now().difference(startedAt);
}

typedef CatalogImportProgressCallback =
    void Function(CatalogImportProgress progress);
