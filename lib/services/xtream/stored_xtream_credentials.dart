import '../settings/settings_repository.dart';
import '../sources/source_contracts.dart';
import '../sources/source_verification_candidate.dart';
import 'xtream_authentication.dart';

class StoredXtreamCredentials {
  const StoredXtreamCredentials(this.settings);
  final SettingsRepository settings;

  Future<XtreamCredentials?> resolve(String playlistId, int revision) async {
    final playlist = await settings.getPlaylist(playlistId);
    final record = playlist?.verificationRecord;
    if (playlist == null ||
        !playlist.enabled ||
        playlist.connectionRevision != revision ||
        record == null ||
        record.connectionRevision != revision ||
        !record.apiEnabled ||
        record.verification != SourceVerificationState.verified ||
        playlist.sourceConfig == null) {
      return null;
    }
    final candidate = sourceVerificationCandidate(playlist.sourceConfig!);
    if (candidate == null) return null;
    return XtreamCredentials(
      endpoint: candidate.endpoint,
      username: candidate.username,
      password: candidate.password,
      confirmed: true,
    );
  }
}
