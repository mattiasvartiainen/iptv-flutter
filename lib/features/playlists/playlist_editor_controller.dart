import 'package:flutter/foundation.dart';

import '../../services/settings/settings_repository.dart'
    show ManagedPlaylist, PlaylistSourceConfig;
import '../../services/sources/source_contracts.dart';
import '../../services/sources/source_verification_candidate.dart';
import '../../services/sources/source_verification_record.dart';
import '../../services/sources/source_verifier.dart';
import '../../services/sources/xtream_source_detection.dart';
import 'playlist_form_validation.dart';

class PlaylistEditorController extends ChangeNotifier {
  PlaylistEditorController({
    required SourceVerifier verifier,
    ManagedPlaylist? initial,
    int connectionRevision = 0,
    DateTime Function()? now,
  }) : _verifier = verifier,
       _playlistId = initial?.playlistId,
       _enabled = initial?.enabled ?? true,
       _initial = initial,
       _connectionRevision = connectionRevision,
       _now = now ?? DateTime.now {
    if (connectionRevision < 0) {
      throw ArgumentError('Connection revision must not be negative.');
    }
    final config = initial?.sourceConfig;
    _name = initial?.name ?? '';
    _sourceKind = config?.kind ?? initial?.sourceKind ?? PlaylistSourceKind.url;
    _url = config?.url ?? initial?.resolvedUrl ?? '';
    _server = config?.server ?? '';
    _username = config?.username ?? '';
    _password = config?.password ?? '';
    _verificationRecord = initial?.verificationRecord;
    _urlOnly = initial?.verificationRecord?.apiEnabled == false;
    if (_verificationRecord case final record?) {
      _result = XtreamAuthResult(
        verification: record.verification,
        accountState: record.accountState,
      );
    }
  }

  final ManagedPlaylist? _initial;
  final SourceVerifier _verifier;
  final String? _playlistId;
  final bool _enabled;
  final DateTime Function() _now;
  late String _name;
  late String _url;
  late String _server;
  late String _username;
  late String _password;
  late PlaylistSourceKind _sourceKind;
  int _connectionRevision;
  bool _urlOnly = false;
  bool _connectionConfirmed = false;
  bool _disposed = false;
  XtreamCancellation? _cancellation;
  XtreamAuthResult? _result;
  SourceVerificationRecord? _verificationRecord;
  String? _errorMessage;

  String get name => _name;
  String get url => _url;
  String get server => _server;
  String get username => _username;
  String get password => _password;
  PlaylistSourceKind get sourceKind => _sourceKind;
  int get connectionRevision => _connectionRevision;
  bool get connectionConfirmed => _connectionConfirmed;
  bool get checking => _cancellation != null;
  XtreamAuthResult? get result => _result;
  SourceVerificationRecord? get verificationRecord => _verificationRecord;
  String? get errorMessage => _errorMessage;

  SourceVerificationCandidate? get _candidate =>
      sourceVerificationCandidate(_draftConfig(_playlistId));

  bool get apiEnabled =>
      _sourceKind == PlaylistSourceKind.xtream ||
      (!_urlOnly && _candidate != null);
  String? get candidatePreview => _candidate?.host;
  bool get insecure => _candidate?.insecure ?? false;
  bool get requiresConfirmation => _candidate?.requiresConfirmation ?? false;
  bool get canVerify =>
      !_disposed &&
      !checking &&
      apiEnabled &&
      _candidate != null &&
      (!requiresConfirmation || _connectionConfirmed);

  String get verificationText {
    if (checking) return 'Checking connection...';
    if (_errorMessage != null) return _errorMessage!;
    return switch (_result?.verification) {
      SourceVerificationState.verified => 'API verified.',
      _ => 'Not verified.',
    };
  }

  String get accountText => switch (_result?.accountState) {
    SourceAccountState.active => 'Active',
    SourceAccountState.expired => 'Expired',
    SourceAccountState.disabled => 'Disabled',
    SourceAccountState.banned => 'Banned',
    _ => 'Unknown',
  };

  void updateName(String value) {
    if (_disposed || value == _name) return;
    _name = value;
    notifyListeners();
  }

  void updateUrl(String value) {
    if (_disposed || value == _url) return;
    _url = value;
    _connectionChanged();
  }

  void updateServer(String value) {
    if (_disposed || value == _server) return;
    _server = value;
    _connectionChanged();
  }

  void updateUsername(String value) {
    if (_disposed || value == _username) return;
    _username = value;
    _connectionChanged();
  }

  void updatePassword(String value) {
    if (_disposed || value == _password) return;
    _password = value;
    _connectionChanged();
  }

  void updateSourceKind(PlaylistSourceKind value) {
    if (_disposed || value == _sourceKind) return;
    _sourceKind = value;
    _connectionChanged();
  }

  void updateApiEnabled(bool value) {
    if (_disposed || _sourceKind == PlaylistSourceKind.xtream) return;
    if (_urlOnly == !value) return;
    _urlOnly = !value;
    _connectionChanged();
  }

  void updateConnectionConfirmed(bool value) {
    if (_disposed || value == _connectionConfirmed) return;
    _clearVerification();
    _connectionConfirmed = value;
    notifyListeners();
  }

  PlaylistSourceConfig _draftConfig(String? playlistId) =>
      switch (_sourceKind) {
        PlaylistSourceKind.url => PlaylistSourceConfig.url(
          playlistId: playlistId,
          name: _name.trim(),
          url: _url,
          enabled: _enabled,
        ),
        PlaylistSourceKind.xtream => PlaylistSourceConfig.xtream(
          playlistId: playlistId,
          name: _name.trim(),
          server: _server,
          username: _username.trim(),
          password: _password,
          enabled: _enabled,
        ),
      };

  PlaylistSourceConfig buildConfig(String? playlistId) {
    if (_disposed) throw StateError('Editor is closed.');
    if (validatePlaylistName(_name) != null) {
      throw StateError('Enter a playlist name.');
    }
    if (_sourceKind == PlaylistSourceKind.url) {
      if (validatePlaylistUrl(_url) != null) {
        throw StateError('Enter a valid playlist URL.');
      }
      return _withVerification(_draftConfig(playlistId ?? _playlistId));
    }
    final address = parseXtreamServerAddress(_server);
    if (address == null || _username.trim().isEmpty || _password.isEmpty) {
      throw StateError('Enter a valid server, username and password.');
    }
    if (address.requiresSchemeConfirmation && !_connectionConfirmed) {
      throw StateError('Confirm the server scheme.');
    }
    return _withVerification(
      PlaylistSourceConfig.xtream(
        playlistId: playlistId ?? _playlistId,
        name: _name.trim(),
        server: address.baseUri.toString(),
        username: _username.trim(),
        password: _password,
        enabled: _enabled,
      ),
    );
  }

  PlaylistSourceConfig _withVerification(PlaylistSourceConfig config) {
    final original = _initial?.sourceConfig;
    String? normalizedServer(String? value) {
      final trimmed = value?.trim();
      return trimmed != null && trimmed.endsWith('/')
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
    }

    final changed =
        _initial != null &&
        (original == null ||
            original.kind != config.kind ||
            original.url?.trim() != config.url?.trim() ||
            normalizedServer(original.server) !=
                normalizedServer(config.server) ||
            original.username?.trim() != config.username?.trim() ||
            original.password != config.password);
    final revision = (_initial?.connectionRevision ?? 0) + (changed ? 1 : 0);
    final record =
        _verificationRecord ??
        (_result != null || _errorMessage != null
            ? SourceVerificationRecord(
                verification:
                    _result?.verification ??
                    SourceVerificationState.temporarilyUnavailable,
                accountState:
                    _result?.accountState ?? SourceAccountState.unknown,
                checkedAt: _now().toUtc(),
                connectionRevision: revision,
                apiEnabled: apiEnabled,
              )
            : null);
    final savedRecord = record == null
        ? (!apiEnabled
              ? SourceVerificationRecord(
                  verification: SourceVerificationState.unchecked,
                  accountState: SourceAccountState.unknown,
                  checkedAt: _now().toUtc(),
                  connectionRevision: revision,
                )
              : null)
        : SourceVerificationRecord(
            verification: record.verification,
            accountState: record.accountState,
            checkedAt: record.checkedAt,
            connectionRevision: revision,
            apiEnabled: apiEnabled,
          );
    return config.kind == PlaylistSourceKind.url
        ? PlaylistSourceConfig.url(
            playlistId: config.playlistId,
            name: config.name,
            url: config.url,
            enabled: config.enabled,
            verificationRecord: savedRecord,
            expectedConnectionRevision: _initial?.connectionRevision,
          )
        : PlaylistSourceConfig.xtream(
            playlistId: config.playlistId,
            name: config.name,
            server: config.server,
            username: config.username,
            password: config.password,
            enabled: config.enabled,
            verificationRecord: savedRecord,
            expectedConnectionRevision: _initial?.connectionRevision,
          );
  }

  Future<void> verify() async {
    if (!canVerify) return;
    _clearVerification();
    final cancellation = XtreamCancellation();
    _cancellation = cancellation;
    final config = _draftConfig(_playlistId);
    final confirmed = !requiresConfirmation || _connectionConfirmed;
    notifyListeners();
    if (!_isCurrent(cancellation)) return;
    try {
      final result = await _verifier.verify(
        config,
        confirmed: confirmed,
        cancellation: cancellation,
      );
      if (!_isCurrent(cancellation)) return;
      _result = result;
      if (result.verification == SourceVerificationState.verified) {
        _verificationRecord = SourceVerificationRecord(
          verification: result.verification,
          accountState: result.accountState,
          checkedAt: _now().toUtc(),
          connectionRevision: _connectionRevision,
          apiEnabled: apiEnabled,
        );
      } else {
        _errorMessage = _failureMessage(result.failure);
      }
    } catch (_) {
      if (!_isCurrent(cancellation)) return;
      _errorMessage = 'Could not verify the connection. Try again.';
    } finally {
      if (_isCurrent(cancellation)) {
        _cancellation = null;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(XtreamCancellation cancellation) =>
      !_disposed &&
      identical(_cancellation, cancellation) &&
      !cancellation.isCancelled;

  void cancelVerification() {
    if (_disposed) return;
    _clearVerification();
    notifyListeners();
  }

  void _connectionChanged() {
    _clearVerification();
    _connectionConfirmed = false;
    _connectionRevision++;
    notifyListeners();
  }

  void _clearVerification() {
    final cancellation = _cancellation;
    _cancellation = null;
    cancellation?.cancel();
    _result = null;
    _verificationRecord = null;
    _errorMessage = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearVerification();
    super.dispose();
  }
}

String _failureMessage(XtreamAuthFailure? failure) => switch (failure) {
  XtreamAuthFailure.denied => 'The account credentials were not accepted.',
  XtreamAuthFailure.unsupported => 'API verification is not supported.',
  XtreamAuthFailure.confirmationRequired => 'Confirm the connection first.',
  XtreamAuthFailure.invalidEndpoint ||
  XtreamAuthFailure.missingCredentials => 'Check the connection fields.',
  XtreamAuthFailure.timeout => 'Verification timed out. Try again.',
  XtreamAuthFailure.tls => 'A secure connection could not be established.',
  XtreamAuthFailure.rateLimited => 'Too many requests. Try again later.',
  XtreamAuthFailure.cancelled => 'Verification cancelled.',
  _ => 'Could not verify the connection. Try again.',
};
