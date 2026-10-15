enum PlaylistSourceKind { url, xtream }

enum CatalogSourceMode { m3u, xtreamApi }

enum SourceVerificationState {
  unchecked,
  checking,
  verified,
  invalidCredentials,
  unsupported,
  temporarilyUnavailable,
}

enum SourceAccountState { active, expired, disabled, banned, unknown }

enum SourceCapability {
  liveCatalog,
  vodCatalog,
  seriesCatalog,
  vodInfo,
  seriesInfo,
}

enum SourceCapabilityState { unknown, supported, unsupported }

class SourceConnectionSummary {
  SourceConnectionSummary({
    required this.playlistId,
    required this.inputKind,
    this.catalogMode = CatalogSourceMode.m3u,
    this.verification = SourceVerificationState.unchecked,
    this.accountState = SourceAccountState.unknown,
    this.connectionRevision = 0,
    Map<SourceCapability, SourceCapabilityState> capabilities = const {},
  }) : capabilities = Map.unmodifiable(capabilities) {
    if (connectionRevision < 0) {
      throw ArgumentError('Connection revision must not be negative.');
    }
  }

  final String playlistId;
  final PlaylistSourceKind inputKind;
  final CatalogSourceMode catalogMode;
  final SourceVerificationState verification;
  final SourceAccountState accountState;
  final int connectionRevision;
  final Map<SourceCapability, SourceCapabilityState> capabilities;

  SourceCapabilityState capability(SourceCapability capability) =>
      capabilities[capability] ?? SourceCapabilityState.unknown;
}
