import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/catalog/catalog_import_progress.dart';
import '../../../ui/theme/app_tokens.dart';

class ImportProgressIndicator extends StatefulWidget {
  const ImportProgressIndicator({super.key, required this.progress});

  final CatalogImportProgress progress;

  @override
  State<ImportProgressIndicator> createState() =>
      _ImportProgressIndicatorState();
}

class _ImportProgressIndicatorState extends State<ImportProgressIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final label = switch (progress.phase) {
      CatalogImportPhase.starting => 'Preparing playlist…',
      CatalogImportPhase.downloading => 'Downloading playlist…',
      CatalogImportPhase.parsing => 'Parsing playlist…',
      CatalogImportPhase.importing => 'Importing items…',
      CatalogImportPhase.indexing => 'Updating search index…',
      CatalogImportPhase.completed => 'Import complete',
      CatalogImportPhase.cancelled => 'Import cancelled',
      CatalogImportPhase.failed => 'Import failed',
    };
    final detail = switch (progress.phase) {
      CatalogImportPhase.downloading when progress.total != null =>
        '${_formatBytes(progress.current ?? 0)} / ${_formatBytes(progress.total!)}',
      CatalogImportPhase.downloading => _formatBytes(progress.current ?? 0),
      CatalogImportPhase.parsing =>
        '${progress.current ?? 0} / ${progress.total ?? '?'} items',
      CatalogImportPhase.importing =>
        '${progress.current ?? 0} / ${progress.total ?? '?'} items',
      CatalogImportPhase.indexing => '${progress.indexedItems} indexed',
      _ => progress.message ?? '',
    };
    final elapsed = _formatElapsed(progress.elapsed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label $detail · $elapsed elapsed',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.progressRadius),
          child: LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatElapsed(Duration elapsed) {
    final totalSeconds = elapsed.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes == 0) return '${seconds}s';
    return '${minutes}m ${seconds}s';
  }
}
