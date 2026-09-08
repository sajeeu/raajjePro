import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:share_plus/share_plus.dart';

// `retry: null` (via the callback below) turns off riverpod 3's built-in
// exponential-backoff auto-retry on a failed `build()`. Left at its default,
// a failed `me`/`sessions` fetch keeps silently re-fetching in the
// background for up to ~30s (10 attempts, 200ms→6400ms) before the screen's
// own `error` branch is ever reached — fighting the explicit, user-triggered
// "Try again" this screen already provides, and — the version this shipped
// with first — leaving a pending `Timer` past test teardown. Both
// account-settings providers disable it explicitly for the same reason.
Duration? _noRetry(int retryCount, Object error) => null;

final accountControllerProvider =
    AsyncNotifierProvider<AccountController, UserAccount>(
      AccountController.new,
      retry: _noRetry,
    );

/// `me`, fresh, for the settings screens. Applies the result to AuthState so
/// the rest of the app sees a verification or a freeze done here.
class AccountController extends AsyncNotifier<UserAccount> {
  @override
  Future<UserAccount> build() async {
    final user = await ref.read(authApiProvider).me();
    ref.read(authControllerProvider.notifier).applyUser(user);
    return user;
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final sessionsControllerProvider =
    AsyncNotifierProvider<SessionsController, List<SessionInfo>>(
      SessionsController.new,
      retry: _noRetry,
    );

class SessionsController extends AsyncNotifier<List<SessionInfo>> {
  @override
  Future<List<SessionInfo>> build() => ref.read(authApiProvider).sessions();

  /// Revokes one device — only that device (plan §Phase 3). Returns its name for the toast.
  Future<String> revoke(String id) async {
    final current = state.value ?? const [];
    final target = current.firstWhere((s) => s.id == id);
    await ref.read(authApiProvider).revokeSession(id);
    state = AsyncData(current.where((s) => s.id != id).toList());
    return target.deviceName;
  }

  Future<void> signOutThisDevice() =>
      ref.read(authControllerProvider.notifier).signOut();
}

/// Which per-row session action is in flight, so `Sign out` and `Revoke`
/// show their own loading state (frontend/CLAUDE.md) rather than a
/// page-level spinner or a frozen screen.
class SessionActionState {
  const SessionActionState({this.signingOut = false, this.revokingId});
  final bool signingOut;
  final String? revokingId;
}

final sessionActionControllerProvider =
    NotifierProvider<SessionActionController, SessionActionState>(
      SessionActionController.new,
    );

class SessionActionController extends Notifier<SessionActionState> {
  @override
  SessionActionState build() => const SessionActionState();

  Future<void> signOutThisDevice() async {
    state = const SessionActionState(signingOut: true);
    try {
      await ref.read(sessionsControllerProvider.notifier).signOutThisDevice();
    } finally {
      state = const SessionActionState();
    }
  }

  Future<String> revoke(String id) async {
    state = SessionActionState(revokingId: id);
    try {
      return await ref.read(sessionsControllerProvider.notifier).revoke(id);
    } finally {
      state = const SessionActionState();
    }
  }
}

/// Injectable so tests never open a real share sheet.
final shareProvider = Provider<Future<void> Function(XFile file)>(
  (_) => (file) async {
    await SharePlus.instance.share(
      ShareParams(files: [file], subject: 'Your RaajjePro data export'),
    );
  },
);

class DownloadState {
  const DownloadState({
    this.fetching = false,
    this.shared = false,
    this.offline = false,
    this.failed = false,
  });
  final bool fetching;
  final bool shared;
  final bool offline;
  final bool failed;
}

final downloadControllerProvider =
    NotifierProvider<DownloadController, DownloadState>(DownloadController.new);

class DownloadController extends Notifier<DownloadState> {
  @override
  DownloadState build() => const DownloadState();

  /// Synchronous JSON from the API (plan §Phase 3), handed to the OS share
  /// sheet — the prototype's "emailed within a day" is the flagged divergence.
  ///
  /// Brief-vs-package-behaviour: the brief called `XFile.fromData(bytes,
  /// name: …)` directly, but on every non-web target `cross_file`'s `XFile`
  /// derives `.name` from `.path`'s last segment and silently ignores the
  /// `name:` argument — and `share_plus`'s method channel reads that same
  /// `.name` when handing the file to the OS share sheet. Left as the brief
  /// wrote it, the share sheet would see an unnamed file on a real device,
  /// not just in this test. Writing the bytes to a real temp file first
  /// gives `.name` (and the share sheet) the intended filename.
  Future<void> request() async {
    state = const DownloadState(fetching: true);
    try {
      final data = await ref.read(authApiProvider).dataExport();
      final date = ref.read(clockProvider)().toIso8601String().substring(0, 10);
      final name = 'raajjepro-export-$date.json';
      final bytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(data),
      );
      final dir = Directory.systemTemp;
      // Clear out any earlier export before writing this one — never right
      // after sharing, since the share target (another app) may still be
      // reading that file asynchronously at that point.
      await _deleteStaleExports(dir);
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes);
      await ref.read(shareProvider)(
        XFile(file.path, mimeType: 'application/json'),
      );
      state = const DownloadState(shared: true);
    } on ApiNetworkException {
      state = const DownloadState(offline: true);
    } on ApiException {
      state = const DownloadState(failed: true);
    }
  }
}

/// Removes any earlier `raajjepro-export-*.json` left in [dir] by a
/// previous [DownloadController.request]. Best-effort: a listing or delete
/// failure (a locked file still being read by an old share target, a
/// sandboxed platform) must never block the export in progress.
Future<void> _deleteStaleExports(Directory dir) async {
  try {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final base = entity.path.split(Platform.pathSeparator).last;
      if (!base.startsWith('raajjepro-export-') || !base.endsWith('.json')) {
        continue;
      }
      try {
        await entity.delete();
      } on FileSystemException {
        // Left for next time.
      }
    }
  } on FileSystemException {
    // Left for next time.
  }
}

class DeleteState {
  const DeleteState({this.busy = false, this.result, this.offline = false});
  final bool busy;
  final DeletionResult? result;
  final bool offline;
}

final deleteControllerProvider =
    NotifierProvider<DeleteController, DeleteState>(DeleteController.new);

class DeleteController extends Notifier<DeleteState> {
  @override
  DeleteState build() {
    // Already frozen (a second visit): straight to the frozen card.
    final auth = ref.read(authControllerProvider);
    if (auth is AuthSignedIn &&
        auth.user.status == AccountStatus.frozen &&
        auth.user.deletionDeadlineAt != null) {
      return DeleteState(
        result: DeletionResult(
          deletionRequestedAt: auth.user.deletionDeadlineAt!.subtract(
            const Duration(days: 30),
          ),
          deletionDeadlineAt: auth.user.deletionDeadlineAt!,
        ),
      );
    }
    return const DeleteState();
  }

  /// Queued, never refused (plan §Phase 3). There is no rejected state to render.
  Future<void> confirm() async {
    state = const DeleteState(busy: true);
    try {
      final result = await ref.read(authApiProvider).requestDeletion();
      final auth = ref.read(authControllerProvider);
      if (auth is AuthSignedIn) {
        ref
            .read(authControllerProvider.notifier)
            .applyUser(
              auth.user.copyWith(
                status: AccountStatus.frozen,
                deletionDeadlineAt: result.deletionDeadlineAt,
              ),
            );
      }
      state = DeleteState(result: result);
    } on ApiNetworkException {
      state = const DeleteState(offline: true);
    }
  }
}
