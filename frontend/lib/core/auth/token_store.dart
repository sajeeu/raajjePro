import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:raajjepro/core/auth/auth_models.dart';

abstract class TokenStore {
  Future<TokenPair?> read();
  Future<void> write(TokenPair tokens);
  Future<void> clear();
}

/// Tokens live in the platform keystore, never in shared preferences.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _access = 'rp.access';
  static const _accessExp = 'rp.access_exp';
  static const _refresh = 'rp.refresh';
  static const _refreshExp = 'rp.refresh_exp';

  @override
  Future<TokenPair?> read() async {
    final values = await Future.wait<String?>([
      _s.read(key: _access),
      _s.read(key: _accessExp),
      _s.read(key: _refresh),
      _s.read(key: _refreshExp),
    ]);
    if (values.any((v) => v == null)) return null;
    return TokenPair(
      accessToken: values[0]!,
      accessTokenExpiresAt: DateTime.parse(values[1]!),
      refreshToken: values[2]!,
      refreshTokenExpiresAt: DateTime.parse(values[3]!),
    );
  }

  @override
  Future<void> write(TokenPair t) => Future.wait<void>([
    _s.write(key: _access, value: t.accessToken),
    _s.write(key: _accessExp, value: t.accessTokenExpiresAt.toIso8601String()),
    _s.write(key: _refresh, value: t.refreshToken),
    _s.write(
      key: _refreshExp,
      value: t.refreshTokenExpiresAt.toIso8601String(),
    ),
  ]);

  @override
  Future<void> clear() => Future.wait<void>([
    _s.delete(key: _access),
    _s.delete(key: _accessExp),
    _s.delete(key: _refresh),
    _s.delete(key: _refreshExp),
  ]);
}

class InMemoryTokenStore implements TokenStore {
  TokenPair? _tokens;
  @override
  Future<TokenPair?> read() async => _tokens;
  @override
  Future<void> write(TokenPair tokens) async => _tokens = tokens;
  @override
  Future<void> clear() async => _tokens = null;
}
