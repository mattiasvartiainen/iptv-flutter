import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/sources/source_verification_record.dart';

void main() {
  test('safe verification defaults do not enable API or catalog switching', () {
    final record = SourceVerificationRecord(
      verification: SourceVerificationState.verified,
      accountState: SourceAccountState.active,
      checkedAt: DateTime.utc(2026, 10, 15),
    );
    expect(record.apiEnabled, isFalse);
    expect(record.connectionRevision, 0);
    expect(record.verification, SourceVerificationState.verified);
  });
}
