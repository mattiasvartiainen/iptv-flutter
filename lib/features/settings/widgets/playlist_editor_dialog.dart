import 'package:flutter/material.dart';

import '../../../features/playlists/playlist_form_validation.dart';
import '../../../services/errors/exception_diagnostics.dart';
import '../../../services/settings/settings_repository.dart';
import '../../../state/playlists_controller.dart';
import '../../playlists/playlist_editor_controller.dart';
import 'playlist_error_details.dart';

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
  final _urlFocusNode = FocusNode();
  final _serverFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _saveFocusNode = FocusNode();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final PlaylistEditorController _editor;
  bool _saving = false;
  String? _saveError;
  String? _saveDiagnostics;

  @override
  void initState() {
    super.initState();
    _editor = PlaylistEditorController(
      verifier: widget.controller.sourceVerifier,
      initial: widget.playlist,
      connectionRevision: widget.playlist?.connectionRevision ?? 0,
    );
    _nameController = TextEditingController(text: _editor.name);
    _urlController = TextEditingController(text: _editor.url);
    _serverController = TextEditingController(text: _editor.server);
    _usernameController = TextEditingController(text: _editor.username);
    _passwordController = TextEditingController(text: _editor.password);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _editor.dispose();
    _nameController.dispose();
    _nameFocusNode.dispose();
    _urlFocusNode.dispose();
    _serverFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _saveFocusNode.dispose();
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
    return ListenableBuilder(
      listenable: _editor,
      builder: (context, _) => PopScope<bool>(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _editor.cancelVerification();
        },
        child: AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          title: Text(dialogTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    onEditingComplete: () {},
                    onFieldSubmitted: (_) =>
                        (_editor.sourceKind == PlaylistSourceKind.url
                                ? _urlFocusNode
                                : _serverFocusNode)
                            .requestFocus(),
                    enabled: !_saving,
                    onChanged: _editor.updateName,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: validatePlaylistName,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PlaylistSourceKind>(
                    initialValue: _editor.sourceKind,
                    isExpanded: true,
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
                            _editor.updateSourceKind(value);
                          },
                  ),
                  const SizedBox(height: 12),
                  if (_editor.sourceKind == PlaylistSourceKind.url) ...[
                    TextFormField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      textInputAction: TextInputAction.done,
                      onEditingComplete: () {},
                      onFieldSubmitted: (_) => _saveFocusNode.requestFocus(),
                      enabled: !_saving,
                      onChanged: _editor.updateUrl,
                      decoration: const InputDecoration(
                        labelText: 'Playlist URL',
                      ),
                      validator: validatePlaylistUrl,
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _serverController,
                      focusNode: _serverFocusNode,
                      textInputAction: TextInputAction.next,
                      onEditingComplete: () {},
                      onFieldSubmitted: (_) =>
                          _usernameFocusNode.requestFocus(),
                      enabled: !_saving,
                      onChanged: _editor.updateServer,
                      decoration: const InputDecoration(labelText: 'Server'),
                      validator: validateXtreamServer,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _usernameController,
                      focusNode: _usernameFocusNode,
                      textInputAction: TextInputAction.next,
                      onEditingComplete: () {},
                      onFieldSubmitted: (_) =>
                          _passwordFocusNode.requestFocus(),
                      enabled: !_saving,
                      onChanged: _editor.updateUsername,
                      decoration: const InputDecoration(labelText: 'Username'),
                      validator: validateXtreamUsername,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      textInputAction: TextInputAction.done,
                      onEditingComplete: () {},
                      onFieldSubmitted: (_) => _saveFocusNode.requestFocus(),
                      enabled: !_saving,
                      onChanged: _editor.updatePassword,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: validateXtreamPassword,
                    ),
                  ],
                  if (_editor.candidatePreview != null) ...[
                    const SizedBox(height: 12),
                    Text('API host: ${_editor.candidatePreview}'),
                    if (_editor.sourceKind == PlaylistSourceKind.url)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use Xtream API'),
                        value: _editor.apiEnabled,
                        onChanged: _saving ? null : _editor.updateApiEnabled,
                      ),
                    if (_editor.apiEnabled) ...[
                      if (_editor.insecure)
                        const Text(
                          'HTTP is not encrypted. Credentials may be exposed.',
                        ),
                      if (_editor.requiresConfirmation)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Confirm this server connection'),
                          value: _editor.connectionConfirmed,
                          onChanged: _saving || _editor.checking
                              ? null
                              : (value) => _editor.updateConnectionConfirmed(
                                  value ?? false,
                                ),
                        ),
                      const SizedBox(height: 8),
                      Text(_editor.verificationText),
                      Text('Account: ${_editor.accountText}'),
                      const SizedBox(height: 8),
                      if (_editor.checking)
                        OutlinedButton.icon(
                          onPressed: _editor.cancelVerification,
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel verification'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _saving || !_editor.canVerify
                              ? null
                              : _editor.verify,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: Text(
                            _editor.errorMessage == null
                                ? 'Verify connection'
                                : 'Retry verification',
                          ),
                        ),
                    ],
                  ],
                  if (_saveError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _saveError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (widget.controller.verboseErrorsEnabled &&
                        _saveDiagnostics != null) ...[
                      const SizedBox(height: 12),
                      PlaylistErrorDetails(diagnostics: _saveDiagnostics!),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving
                  ? null
                  : () {
                      _editor.cancelVerification();
                      Navigator.of(context).pop(false);
                    },
              child: const Text('Cancel'),
            ),
            FilledButton(
              focusNode: _saveFocusNode,
              onPressed: _saving || _editor.checking
                  ? null
                  : () async {
                      if (!(_formKey.currentState?.validate() ?? false)) return;
                      setState(() {
                        _saving = true;
                        _saveError = null;
                        _saveDiagnostics = null;
                      });
                      try {
                        final config = _editor.buildConfig(
                          widget.playlist?.playlistId,
                        );
                        final success = await widget.controller
                            .savePlaylistConfig(
                              config,
                              expectedRevision:
                                  widget.playlist?.connectionRevision,
                            );
                        if (!mounted || !context.mounted) return;
                        if (success) {
                          Navigator.of(context).pop(true);
                        } else {
                          setState(() {
                            _saveError =
                                widget.controller.errorMessage ??
                                'Could not save the playlist. Try again.';
                            _saveDiagnostics =
                                widget.controller.errorDiagnostics;
                          });
                        }
                      } catch (error, stackTrace) {
                        if (mounted) {
                          setState(() {
                            _saveError =
                                'Could not save the playlist. Check the connection fields and try again.';
                            _saveDiagnostics = formatExceptionDiagnostics(
                              error,
                              stackTrace,
                            );
                          });
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
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
        ),
      ),
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
