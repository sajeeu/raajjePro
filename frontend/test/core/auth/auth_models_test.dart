import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_models.dart';

void main() {
  test('UserAccount parses the /v1/auth/me DTO and a null phone', () {
    final u = UserAccount.fromJson({
      'id': 'u1',
      'fullName': 'Aishath',
      'email': 'a@example.mv',
      'emailVerified': false,
      'phone': {'dialCode': '+960', 'number': '7771234'},
      'status': 'frozen',
      'deletionDeadlineAt': '2026-10-06T10:00:00.000Z',
      'isProvider': true,
      'createdAt': '2026-09-06T10:00:00.000Z',
    });
    expect(u.phone?.display, '+960 7771234');
    expect(u.status, AccountStatus.frozen);
    expect(u.deletionDeadlineAt, DateTime.utc(2026, 10, 6, 10));
    expect(u.isProvider, isTrue);
    final noPhone = UserAccount.fromJson({
      ...u.toJson(),
      'phone': null,
      'status': 'active',
      'deletionDeadlineAt': null,
    });
    expect(noPhone.phone, isNull);
    expect(noPhone.status, AccountStatus.active);
  });

  test('an unknown status parses as active rather than crashing (additive-only API)', () {
    final u = UserAccount.fromJson({
      'id': 'u',
      'fullName': 'x',
      'email': 'e',
      'emailVerified': true,
      'phone': null,
      'status': 'something_new',
      'deletionDeadlineAt': null,
      'isProvider': false,
      'createdAt': '2026-09-06T10:00:00.000Z',
    });
    expect(u.status, AccountStatus.active);
  });

  test('TokenPair and VerificationOutcome parse timestamps', () {
    final t = TokenPair.fromJson({
      'accessToken': 'a',
      'accessTokenExpiresAt': '2026-09-06T10:15:00.000Z',
      'refreshToken': 'r',
      'refreshTokenExpiresAt': '2026-10-06T10:00:00.000Z',
    });
    expect(t.accessTokenExpiresAt.minute, 15);
    final v = VerificationOutcome.fromJson({
      'status': 'suppressed',
      'expiresAt': '2026-09-06T10:10:00.000Z',
      'resendAvailableAt': '2026-09-06T10:01:00.000Z',
    });
    expect(v.status, VerificationStatus.suppressed);
  });
}
