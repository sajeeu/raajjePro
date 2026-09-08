enum AccountStatus { active, frozen, anonymised }

enum AccountRole { customer, provider }

enum VerificationStatus { sent, suppressed, failed }

DateTime? _date(Object? v) => v is String ? DateTime.parse(v).toUtc() : null;

class PhoneNumber {
  const PhoneNumber({required this.dialCode, required this.number});
  final String dialCode;
  final String number;

  /// User-supplied text, shown as typed. Never with a check mark (plan §Phase 3).
  String get display => '$dialCode $number';

  factory PhoneNumber.fromJson(Map<String, dynamic> j) => PhoneNumber(
    dialCode: j['dialCode'] as String,
    number: j['number'] as String,
  );
}

class UserAccount {
  const UserAccount({
    required this.id,
    required this.fullName,
    required this.email,
    required this.emailVerified,
    required this.phone,
    required this.status,
    required this.deletionDeadlineAt,
    required this.isProvider,
    required this.createdAt,
  });

  final String id;
  final String fullName;
  final String email;
  final bool emailVerified;
  final PhoneNumber? phone;
  final AccountStatus status;
  final DateTime? deletionDeadlineAt;
  final bool isProvider;
  final DateTime createdAt;

  /// An unrecognised status reads as `active`: the API is additive-only and a
  /// new enum value must not crash an installed app (docs/api/versioning.md).
  factory UserAccount.fromJson(Map<String, dynamic> j) => UserAccount(
    id: j['id'] as String,
    fullName: j['fullName'] as String,
    email: j['email'] as String,
    emailVerified: j['emailVerified'] as bool,
    phone: j['phone'] is Map<String, dynamic>
        ? PhoneNumber.fromJson(j['phone'] as Map<String, dynamic>)
        : null,
    status:
        AccountStatus.values.asNameMap()[j['status'] as String?] ??
        AccountStatus.active,
    deletionDeadlineAt: _date(j['deletionDeadlineAt']),
    isProvider: j['isProvider'] as bool? ?? false,
    createdAt: _date(j['createdAt']) ?? DateTime.now().toUtc(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fullName': fullName,
    'email': email,
    'emailVerified': emailVerified,
    'phone': phone == null
        ? null
        : {'dialCode': phone!.dialCode, 'number': phone!.number},
    'status': status.name,
    'deletionDeadlineAt': deletionDeadlineAt?.toIso8601String(),
    'isProvider': isProvider,
    'createdAt': createdAt.toIso8601String(),
  };

  UserAccount copyWith({
    bool? emailVerified,
    String? email,
    PhoneNumber? phone,
    AccountStatus? status,
    DateTime? deletionDeadlineAt,
  }) => UserAccount(
    id: id,
    fullName: fullName,
    email: email ?? this.email,
    emailVerified: emailVerified ?? this.emailVerified,
    phone: phone ?? this.phone,
    status: status ?? this.status,
    deletionDeadlineAt: deletionDeadlineAt ?? this.deletionDeadlineAt,
    isProvider: isProvider,
    createdAt: createdAt,
  );
}

class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
  });
  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;

  factory TokenPair.fromJson(Map<String, dynamic> j) => TokenPair(
    accessToken: j['accessToken'] as String,
    accessTokenExpiresAt: _date(j['accessTokenExpiresAt'])!,
    refreshToken: j['refreshToken'] as String,
    refreshTokenExpiresAt: _date(j['refreshTokenExpiresAt'])!,
  );
}

class VerificationOutcome {
  const VerificationOutcome({
    required this.status,
    required this.expiresAt,
    required this.resendAvailableAt,
  });
  final VerificationStatus status;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;

  factory VerificationOutcome.fromJson(Map<String, dynamic> j) =>
      VerificationOutcome(
        status:
            VerificationStatus.values.asNameMap()[j['status'] as String?] ??
            VerificationStatus.failed,
        expiresAt: _date(j['expiresAt'])!,
        resendAvailableAt: _date(j['resendAvailableAt'])!,
      );
}

class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.deviceName,
    required this.createdAt,
    required this.lastSeenAt,
    required this.current,
  });
  final String id;
  final String deviceName;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final bool current;

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
    id: j['id'] as String,
    deviceName: j['deviceName'] as String,
    createdAt: _date(j['createdAt'])!,
    lastSeenAt: _date(j['lastSeenAt'])!,
    current: j['current'] as bool,
  );
}

class DeletionResult {
  const DeletionResult({
    required this.deletionRequestedAt,
    required this.deletionDeadlineAt,
  });
  final DateTime deletionRequestedAt;
  final DateTime deletionDeadlineAt;
  factory DeletionResult.fromJson(Map<String, dynamic> j) => DeletionResult(
    deletionRequestedAt: _date(j['deletionRequestedAt'])!,
    deletionDeadlineAt: _date(j['deletionDeadlineAt'])!,
  );
}

class RegisterRequest {
  const RegisterRequest({
    required this.role,
    required this.fullName,
    required this.email,
    required this.dialCode,
    required this.number,
    required this.password,
    this.businessName,
    required this.deviceName,
  });
  final AccountRole role;
  final String fullName;
  final String email;
  final String dialCode;
  final String number;
  final String password;
  final String? businessName;
  final String deviceName;

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'fullName': fullName,
    'email': email,
    'phone': {'dialCode': dialCode, 'number': number},
    'password': password,
    if (role == AccountRole.provider && businessName != null)
      'businessName': businessName,
    'acceptTerms': true,
    'deviceName': deviceName,
  };
}

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthGuest extends AuthState {
  const AuthGuest();
}

class AuthSessionExpired extends AuthState {
  const AuthSessionExpired();
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);
  final UserAccount user;
}
