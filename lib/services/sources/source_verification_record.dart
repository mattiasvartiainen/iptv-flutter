import 'source_contracts.dart';

class SourceVerificationRecord {
  const SourceVerificationRecord({
    required this.verification,
    required this.accountState,
    required this.checkedAt,
    this.connectionRevision = 0,
    this.apiEnabled = false,
  });

  final SourceVerificationState verification;
  final SourceAccountState accountState;
  final DateTime checkedAt;
  final int connectionRevision;
  final bool apiEnabled;
}
