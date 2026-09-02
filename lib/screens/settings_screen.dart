import 'dart:async';

import 'package:flutter/material.dart';

import '../services/catalog/catalog_import_progress.dart';

import '../services/settings/settings_repository.dart';
import '../state/app_controller.dart';
import '../widgets/app_scope.dart';
import '../widgets/app_shell_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return AppShellScaffold(
      showBack: true,
      title: 'Settings',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(40, 8, 40, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Manage saved playlists, refresh them manually, and keep home section visibility in one place.',
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: () =>
                        _showPlaylistEditor(context, controller: c),
                    icon: const Icon(Icons.add),
                    label: const Text('Add playlist'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PlaylistSection(controller: c),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              title: const Text('Show Live TV on Home'),
              subtitle: const Text(
                'Displays the Live TV row on the Home screen.',
              ),
              value: c.showHomeLiveTv,
              onChanged: (value) => c.setHomeSectionVisibility(
                settingKey: 'show_home_live_tv',
                enabled: value,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Show Movies on Home'),
              subtitle: const Text(
                'Displays the Movies row on the Home screen.',
              ),
              value: c.showHomeMovies,
              onChanged: (value) => c.setHomeSectionVisibility(
                settingKey: 'show_home_movies',
                enabled: value,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Show Series on Home'),
              subtitle: const Text(
                'Displays the Series row on the Home screen.',
              ),
              value: c.showHomeSeries,
              onChanged: (value) => c.setHomeSectionVisibility(
                settingKey: 'show_home_series',
                enabled: value,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Display verbose information'),
              subtitle: const Text(
                'Shows download and import progress while a playlist refreshes.',
              ),
              value: c.verboseRefreshInfo,
              onChanged: (value) => c.setVerboseRefreshInfo(value),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: c.goBack, child: const Text('Back')),
        ],
      ),
    );
  }
}

class _PlaylistSection extends StatelessWidget {
  const _PlaylistSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final playlists = controller.playlists;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Playlists',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text('${playlists.length} saved'),
              ],
            ),
            if (controller.errorMessage case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            if (playlists.isEmpty)
              const _EmptyPlaylistState()
            else
              ...playlists.map(
                (playlist) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PlaylistCard(
                    playlist: playlist,
                    isActive:
                        playlist.playlistId == controller.activePlaylistId,
                    isRefreshing:
                        playlist.playlistId == controller.refreshingPlaylistId,
                    progress:
                        playlist.playlistId ==
                                controller.refreshingPlaylistId &&
                            controller.verboseRefreshInfo
                        ? controller.importProgress
                        : null,
                    onSelect: () =>
                        controller.selectPlaylist(playlist.playlistId),
                    onRefresh: () =>
                        controller.refreshPlaylist(playlist.playlistId),
                    onEdit: () => _showPlaylistEditor(
                      context,
                      controller: controller,
                      playlist: playlist,
                    ),
                    onDelete: () =>
                        _confirmDelete(context, controller, playlist),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlaylistState extends StatelessWidget {
  const _EmptyPlaylistState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'No playlists saved yet. Add a URL playlist or enter Xtream Codes details to store it here.',
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                              Chip(
                                label: const Text('Active'),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            if (!playlist.enabled)
                              Chip(
                                label: const Text('Disabled'),
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
                          'Import: ${playlist.lastImportStatus ?? 'never'}${lastImport != null ? ' · ${_formatDate(lastImport)}' : ''}',
                        ),
                        if (playlist.lastImportWarning case final warning?) ...[
                          const SizedBox(height: 4),
                          Text(
                            warning,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'Refresh: ${refresh?.refreshMode.name ?? 'weekly'}${refresh?.nextRefreshAt != null ? ' · next ${_formatDate(refresh!.nextRefreshAt!)}' : ''}',
                        ),
                        if (progress != null) ...[
                          const SizedBox(height: 8),
                          _ImportProgressIndicator(progress: progress!),
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

class _ImportProgressIndicator extends StatefulWidget {
  const _ImportProgressIndicator({required this.progress});

  final CatalogImportProgress progress;

  @override
  State<_ImportProgressIndicator> createState() =>
      _ImportProgressIndicatorState();
}

class _ImportProgressIndicatorState extends State<_ImportProgressIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Ticks the elapsed-time label between progress callbacks.
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
      CatalogImportPhase.downloading => 'Downloading playlist…',
      CatalogImportPhase.importing => 'Importing items…',
    };
    final fraction = progress.fraction;
    final detail = switch (progress.phase) {
      CatalogImportPhase.downloading when progress.total != null =>
        '${_formatBytes(progress.current ?? 0)} / ${_formatBytes(progress.total!)}',
      CatalogImportPhase.downloading => _formatBytes(progress.current ?? 0),
      CatalogImportPhase.importing =>
        '${progress.current ?? 0} / ${progress.total ?? '?'} items',
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
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: fraction, minHeight: 4),
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

class _PlaylistEditorDialog extends StatefulWidget {
  const _PlaylistEditorDialog({required this.controller, this.playlist});

  final AppController controller;

  final ManagedPlaylist? playlist;

  @override
  State<_PlaylistEditorDialog> createState() => _PlaylistEditorDialogState();
}

class _PlaylistEditorDialogState extends State<_PlaylistEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late PlaylistSourceKind _kind;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final source = widget.playlist?.sourceConfig;
    _kind = source?.kind ?? PlaylistSourceKind.url;
    _nameController = TextEditingController(
      text: widget.playlist?.name ?? source?.name ?? '',
    );
    _urlController = TextEditingController(
      text: source?.url ?? widget.playlist?.resolvedUrl ?? '',
    );
    _serverController = TextEditingController(text: source?.server ?? '');
    _usernameController = TextEditingController(text: source?.username ?? '');
    _passwordController = TextEditingController(text: source?.password ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.playlist == null ? 'Add playlist' : 'Edit playlist';
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a playlist name.'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PlaylistSourceKind>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Source type'),
                  items: const [
                    DropdownMenuItem(
                      value: PlaylistSourceKind.url,
                      child: Text('Name / URL'),
                    ),
                    DropdownMenuItem(
                      value: PlaylistSourceKind.xtream,
                      child: Text('Xtream Codes'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _kind = value);
                        },
                ),
                const SizedBox(height: 12),
                if (_kind == PlaylistSourceKind.url) ...[
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Playlist URL',
                    ),
                    validator: (value) =>
                        value == null ||
                            Uri.tryParse(value.trim()) == null ||
                            !Uri.tryParse(value.trim())!.hasScheme
                        ? 'Enter a valid playlist URL.'
                        : null,
                  ),
                ] else ...[
                  TextFormField(
                    controller: _serverController,
                    decoration: const InputDecoration(labelText: 'Server'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter the server URL.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter the username.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter the password.'
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  if (!(_formKey.currentState?.validate() ?? false)) {
                    return;
                  }
                  setState(() => _saving = true);
                  final success = switch (_kind) {
                    PlaylistSourceKind.url =>
                      await widget.controller.savePlaylistUrl(
                        playlistId: widget.playlist?.playlistId,
                        name: _nameController.text,
                        url: _urlController.text,
                      ),
                    PlaylistSourceKind.xtream =>
                      await widget.controller.saveXtreamPlaylist(
                        playlistId: widget.playlist?.playlistId,
                        name: _nameController.text,
                        server: _serverController.text,
                        username: _usernameController.text,
                        password: _passwordController.text,
                      ),
                  };
                  if (!mounted) return;
                  setState(() => _saving = false);
                  if (success) {
                    Navigator.of(context).pop(true);
                  }
                },
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

Future<void> _showPlaylistEditor(
  BuildContext context, {
  required AppController controller,
  ManagedPlaylist? playlist,
}) async {
  await showDialog<bool>(
    context: context,
    builder: (_) =>
        _PlaylistEditorDialog(controller: controller, playlist: playlist),
  );
}

Future<void> _confirmDelete(
  BuildContext context,
  AppController controller,
  ManagedPlaylist playlist,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete playlist?'),
      content: Text(
        'This removes ${playlist.name} and all of its imported data from the local database.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.deletePlaylist(playlist.playlistId);
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
