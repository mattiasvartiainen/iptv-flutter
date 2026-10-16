import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/features/playlists/playlist_editor_controller.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/sources/source_verifier.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';

import '../../support/database_adapter.dart';

void main() {
  test(
    'failed revalidation replaces a previously verified saved status',
    () async {
      final database = createTestDatabaseAdapter(
        fileName: 'reverify_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(database.close);
      final settings = SqliteSettingsRepository(
        databaseAdapter: database,
        secretStore: InMemoryPlaylistSecretStore(),
      );
      final verifier = _Verifier();
      final editor = PlaylistEditorController(verifier: verifier);
      addTearDown(editor.dispose);
      editor.updateName('Provider');
      editor.updateUrl(
        'https://provider.example/get.php?username=u&password=p&output=ts',
      );
      await editor.verify();
      final saved = await settings.upsertPlaylist(editor.buildConfig(null));
      final editing = PlaylistEditorController(
        verifier: verifier,
        initial: saved,
        connectionRevision: saved.connectionRevision,
      );
      addTearDown(editing.dispose);
      verifier.result = const XtreamAuthResult(
        verification: SourceVerificationState.invalidCredentials,
        failure: XtreamAuthFailure.denied,
      );
      await editing.verify();
      final updated = await settings.upsertPlaylist(
        editing.buildConfig(saved.playlistId),
      );
      expect(
        updated.verificationRecord?.verification,
        SourceVerificationState.invalidCredentials,
      );
      expect(updated.verificationRecord?.apiEnabled, isTrue);
      expect(updated.connectionRevision, saved.connectionRevision);
      expect(updated.resolvedUrl, saved.resolvedUrl);
    },
  );

  test(
    'editor verification survives saving new, editing and reopening a real source',
    () async {
      final database = createTestDatabaseAdapter(
        fileName: 'editor_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(database.close);
      final settings = SqliteSettingsRepository(
        databaseAdapter: database,
        secretStore: InMemoryPlaylistSecretStore(),
      );
      final verifier = _Verifier();
      final editor = PlaylistEditorController(verifier: verifier);
      addTearDown(editor.dispose);
      editor.updateName('Provider');
      editor.updateUrl(
        'https://provider.example/get.php?username=u&password=p&output=ts',
      );
      await editor.verify();
      final saved = await settings.upsertPlaylist(editor.buildConfig(null));
      expect(saved.connectionRevision, 0);
      expect(
        saved.verificationRecord?.verification,
        SourceVerificationState.verified,
      );
      final editing = PlaylistEditorController(
        verifier: verifier,
        initial: saved,
        connectionRevision: saved.connectionRevision,
      );
      addTearDown(editing.dispose);
      expect(editing.verificationText, 'API verified.');
      editing.updateUrl(
        'https://provider.example/get.php?username=u&password=other&output=ts',
      );
      editing.updateUrl(
        'https://provider.example/get.php?username=u&password=final&output=ts',
      );
      await editing.verify();
      final updated = await settings.upsertPlaylist(
        editing.buildConfig(saved.playlistId),
      );
      expect(updated.connectionRevision, 1);
      expect(updated.verificationRecord?.connectionRevision, 1);
      expect(
        updated.verificationRecord?.verification,
        SourceVerificationState.verified,
      );
      editing.updateApiEnabled(false);
      await expectLater(
        settings.upsertPlaylist(editing.buildConfig(saved.playlistId)),
        throwsStateError,
      );
      final freshEditor = PlaylistEditorController(
        verifier: verifier,
        initial: updated,
        connectionRevision: updated.connectionRevision,
      );
      addTearDown(freshEditor.dispose);
      freshEditor.updateApiEnabled(false);
      final urlOnly = await settings.upsertPlaylist(
        freshEditor.buildConfig(saved.playlistId),
      );
      final reopened = PlaylistEditorController(
        verifier: verifier,
        initial: urlOnly,
        connectionRevision: urlOnly.connectionRevision,
      );
      addTearDown(reopened.dispose);
      expect(reopened.apiEnabled, isFalse);
      expect(urlOnly.resolvedUrl, contains('output=ts'));
    },
  );
}

class _Verifier implements SourceVerifier {
  XtreamAuthResult result = const XtreamAuthResult(
    verification: SourceVerificationState.verified,
    accountState: SourceAccountState.active,
  );

  @override
  Future<XtreamAuthResult> verify(
    PlaylistSourceConfig config, {
    required bool confirmed,
    required XtreamCancellation cancellation,
  }) async => result;
}
