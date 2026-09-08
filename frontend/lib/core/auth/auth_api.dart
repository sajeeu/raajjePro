import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_models.dart';

/// Typed calls to /v1/auth and /v1/users/me. Bodies and paths are the backend
/// plan's route blocks, verbatim. No rule lives here — the server decides.
class AuthApi {
  const AuthApi(this._api);
  final ApiClient _api;

  Future<
    ({UserAccount user, TokenPair tokens, VerificationOutcome verification})
  >
  register(RegisterRequest request, {required String idempotencyKey}) async {
    final d = await _api.post(
      '/v1/auth/register',
      body: request.toJson(),
      headers: {'idempotency-key': idempotencyKey},
    );
    return (
      user: UserAccount.fromJson(d['user'] as Map<String, dynamic>),
      tokens: TokenPair.fromJson(d['tokens'] as Map<String, dynamic>),
      verification: VerificationOutcome.fromJson(
        d['verification'] as Map<String, dynamic>,
      ),
    );
  }

  Future<({UserAccount user, TokenPair tokens})> login(
    String email,
    String password,
    String deviceName,
  ) async {
    final d = await _api.post(
      '/v1/auth/login',
      body: {'email': email, 'password': password, 'deviceName': deviceName},
    );
    return (
      user: UserAccount.fromJson(d['user'] as Map<String, dynamic>),
      tokens: TokenPair.fromJson(d['tokens'] as Map<String, dynamic>),
    );
  }

  Future<TokenPair> refresh(String refreshToken) async => TokenPair.fromJson(
    (await _api.post(
          '/v1/auth/refresh',
          body: {'refreshToken': refreshToken},
        ))['tokens']
        as Map<String, dynamic>,
  );

  Future<void> logout() => _api.post('/v1/auth/logout');
  Future<UserAccount> me() async =>
      UserAccount.fromJson(await _api.get('/v1/auth/me'));

  Future<List<SessionInfo>> sessions() async =>
      ((await _api.get('/v1/auth/sessions'))['_list'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(SessionInfo.fromJson)
          .toList();
  Future<void> revokeSession(String id) => _api.delete('/v1/auth/sessions/$id');

  Future<VerificationOutcome> sendVerification() async =>
      VerificationOutcome.fromJson(
        await _api.post('/v1/auth/verify-email/send'),
      );
  Future<void> confirmVerification(String code) =>
      _api.post('/v1/auth/verify-email/confirm', body: {'code': code});
  Future<void> social(String provider, String idToken, String deviceName) =>
      _api.post(
        '/v1/auth/social/$provider',
        body: {'idToken': idToken, 'deviceName': deviceName},
      );

  /// Forgot password (plan §Phase 3b). All three are unauthenticated, so the
  /// address travels in the body — there is no session to identify by.
  Future<PasswordResetRequestOutcome> requestPasswordReset(
    String email,
  ) async => PasswordResetRequestOutcome.fromJson(
    await _api.post('/v1/auth/password-reset/request', body: {'email': email}),
  );
  Future<void> verifyPasswordResetCode(String email, String code) => _api.post(
    '/v1/auth/password-reset/verify',
    body: {'email': email, 'code': code},
  );
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) => _api.post(
    '/v1/auth/password-reset/confirm',
    body: {'email': email, 'code': code, 'newPassword': newPassword},
  );

  Future<void> changePassword(String currentPassword, String newPassword) =>
      _api.post(
        '/v1/users/me/change-password',
        body: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );
  Future<VerificationOutcome> requestEmailChange(
    String newEmail,
    String currentPassword,
  ) async => VerificationOutcome.fromJson(
    await _api.post(
      '/v1/users/me/change-email/request',
      body: {'newEmail': newEmail, 'currentPassword': currentPassword},
    ),
  );
  Future<UserAccount> confirmEmailChange(String code) async =>
      UserAccount.fromJson(
        await _api.post(
          '/v1/users/me/change-email/confirm',
          body: {'code': code},
        ),
      );
  Future<UserAccount> changePhone(String dialCode, String number) async =>
      UserAccount.fromJson(
        await _api.patch(
          '/v1/users/me/phone',
          body: {'dialCode': dialCode, 'number': number},
        ),
      );
  Future<Map<String, dynamic>> dataExport() =>
      _api.get('/v1/users/me/data-export');
  Future<DeletionResult> requestDeletion() async =>
      DeletionResult.fromJson(await _api.post('/v1/users/me/deletion-request'));
}
