enum CatalogImportPhase {
  starting,
  downloading,
  parsing,
  importing,
  indexing,
  completed,
  cancelled,
  failed,
}

class CatalogImportProgress {
  const CatalogImportProgress({
    required this.phase,
    required this.startedAt,
    this.current,
    this.total,
    this.message,
    this.jobId,
    this.playlistId,
    this.updatedAt,
    this.parsedItems = 0,
    this.stagedItems = 0,
    this.acceptedItems = 0,
    this.rejectedItems = 0,
    this.indexedItems = 0,
    this.currentOperation,
    this.error,
  });

  final CatalogImportPhase phase;
  final DateTime startedAt;
  final int? current;
  final int? total;
  final String? message;
  final String? jobId;
  final String? playlistId;
  final DateTime? updatedAt;
  final int parsedItems;
  final int stagedItems;
  final int acceptedItems;
  final int rejectedItems;
  final int indexedItems;
  final String? currentOperation;
  final Object? error;

  bool get isTerminal => switch (phase) {
    CatalogImportPhase.completed ||
    CatalogImportPhase.cancelled ||
    CatalogImportPhase.failed => true,
    _ => false,
  };

  double? get fraction {
    final current = this.current;
    final total = this.total;
    if (current == null || total == null || total <= 0) return null;
    return (current / total).clamp(0.0, 1.0);
  }

  Duration get elapsed => DateTime.now().difference(startedAt);

  CatalogImportProgress copyWith({
    CatalogImportPhase? phase,
    DateTime? startedAt,
    int? current,
    int? total,
    String? message,
    String? jobId,
    String? playlistId,
    DateTime? updatedAt,
    int? parsedItems,
    int? stagedItems,
    int? acceptedItems,
    int? rejectedItems,
    int? indexedItems,
    String? currentOperation,
    Object? error,
  }) {
    return CatalogImportProgress(
      phase: phase ?? this.phase,
      startedAt: startedAt ?? this.startedAt,
      current: current ?? this.current,
      total: total ?? this.total,
      message: message ?? this.message,
      jobId: jobId ?? this.jobId,
      playlistId: playlistId ?? this.playlistId,
      updatedAt: updatedAt ?? this.updatedAt,
      parsedItems: parsedItems ?? this.parsedItems,
      stagedItems: stagedItems ?? this.stagedItems,
      acceptedItems: acceptedItems ?? this.acceptedItems,
      rejectedItems: rejectedItems ?? this.rejectedItems,
      indexedItems: indexedItems ?? this.indexedItems,
      currentOperation: currentOperation ?? this.currentOperation,
      error: error ?? this.error,
    );
  }
}

typedef CatalogImportProgressCallback =
    void Function(CatalogImportProgress progress);
