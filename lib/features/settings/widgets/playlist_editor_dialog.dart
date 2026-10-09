import 'package:flutter/material.dart';

import '../../../features/playlists/playlist_form_validation.dart';
import '../../../services/settings/settings_repository.dart';
import '../../../state/playlists_controller.dart';

class _PlaylistEditorDialog extends StatefulWidget {
  const _PlaylistEditorDialog({required this.controller, this.playlist});

  final PlaylistsController controller;
  final ManagedPlaylist? playlist;

  @override
  State<_PlaylistEditorDialog> createState() => _PlaylistEditorDialogState();
}

class _PlaylistEditorDialogState extends State<_PlaylistEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameFocusNode = FocusNode();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    _urlController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogTitle = widget.playlist == null
        ? 'Add playlist'
        : 'Edit playlist';
    return AlertDialog(
      title: Text(dialogTitle),
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
                  focusNode: _nameFocusNode,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: validatePlaylistName,
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
                    validator: validatePlaylistUrl,
                  ),
                ] else ...[
                  TextFormField(
                    controller: _serverController,
                    decoration: const InputDecoration(labelText: 'Server'),
                    validator: validateXtreamServer,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: validateXtreamUsername,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: validateXtreamPassword,
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
          autofocus: true,
          onPressed: _saving
              ? null
              : () async {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
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
                  if (success && context.mounted) {
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

Future<void> showPlaylistEditor(
  BuildContext context, {
  required PlaylistsController controller,
  ManagedPlaylist? playlist,
}) async {
  await showDialog<bool>(
    context: context,
    builder: (_) =>
        _PlaylistEditorDialog(controller: controller, playlist: playlist),
  );
}

Future<void> confirmPlaylistDelete(
  BuildContext context,
  PlaylistsController controller,
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
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.deletePlaylist(playlist.playlistId);
}
