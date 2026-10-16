import '../settings/settings_repository.dart' show PlaylistSourceConfig;
import '../xtream/xtream_authentication.dart';

export '../xtream/xtream_authentication.dart'
    show XtreamAuthResult, XtreamAuthFailure, XtreamCancellation;

abstract interface class SourceVerifier {
  Future<XtreamAuthResult> verify(
    PlaylistSourceConfig config, {
    required bool confirmed,
    required XtreamCancellation cancellation,
  });
}
