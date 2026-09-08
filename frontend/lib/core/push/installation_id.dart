import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A stable id for this app installation, generated once and kept.
///
/// Deliberately separate from the device token: the token rotates and this
/// does not, which is what lets a refresh update the existing registration
/// instead of leaving a dead one behind on every rotation.
///
/// Stored in the platform keystore beside the auth tokens. If it is ever lost
/// — a reinstall, cleared data — a new one is minted; the old registration is
/// revoked server-side when the vendor reports its token dead.
abstract class InstallationIdStore {
  Future<String> read();
}

class SecureInstallationIdStore implements InstallationIdStore {
  SecureInstallationIdStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _key = 'rp.installation_id';

  @override
  Future<String> read() async {
    final existing = await _s.read(key: _key);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = uuidV4();
    await _s.write(key: _key, value: fresh);
    return fresh;
  }
}

class InMemoryInstallationIdStore implements InstallationIdStore {
  InMemoryInstallationIdStore([String? id]) : _id = id ?? uuidV4();
  final String _id;
  @override
  Future<String> read() async => _id;
}

String uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => b
      .sublist(from, to)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

final installationIdProvider = Provider<InstallationIdStore>(
  (_) => SecureInstallationIdStore(),
);
