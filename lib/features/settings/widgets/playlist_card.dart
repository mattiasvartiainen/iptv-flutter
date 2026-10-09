import 'package:flutter/material.dart';

import '../../../services/catalog/catalog_import_progress.dart';
import '../../../services/settings/settings_repository.dart';
import '../../../ui/theme/app_tokens.dart';
import 'import_progress_indicator.dart';

class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.isActive,
    required this.isRefreshing,
    this.progress,
    required this.onSelect,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
  });

  final ManagedPlaylist playlist;
  final bool isActive;
  final bool isRefreshing;
  final CatalogImportProgress? progress;
  final VoidCallback onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final refresh = playlist.refreshSettings;
    final lastImport = playlist.lastImportCompletedAt;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: isActive ? colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              playlist.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 8),
                            if (isActive)
                              const Chip(
                                label: Text('Active'),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            if (!playlist.enabled)
                              const Chip(
                                label: Text('Disabled'),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          playlist.sourceSummary,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Import: ${playlist.lastImportStatus ?? 'never'}${lastImport == null ? '' : ' · ${formatPlaylistDate(lastImport)}'}',
                        ),
                        if (playlist.lastImportWarning case final warning?) ...[
                          const SizedBox(height: 4),
                          Text(
                            warning,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'Refresh: ${refresh?.refreshMode.name ?? 'weekly'}${refresh?.nextRefreshAt == null ? '' : ' · next ${formatPlaylistDate(refresh!.nextRefreshAt!)}'}',
                        ),
                        if (progress != null) ...[
                          const SizedBox(height: 8),
                          ImportProgressIndicator(progress: progress!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: isRefreshing ? null : onRefresh,
                        icon: isRefreshing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(isRefreshing ? 'Refreshing' : 'Refresh'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatPlaylistDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
