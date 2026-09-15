import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// The two platform seams a screen crosses to hand the user a file — a
/// writable app-private directory and the OS share sheet.
///
/// 🔧 **Moved out of `features/account/` by §Phase 10a**, on their second
/// consumer: the invoice PDF download. `lib/README.md`'s convention — a thing
/// a second feature needs moves to `core/`; it is not copied — and the
/// alternative was the billing feature importing the account feature for two
/// providers, which `lib/README.md` forbids outright.

/// Injectable so tests never open a real share sheet. The subject is the
/// data export's, because that was its only caller when it was written;
/// [shareDocumentProvider] is the general form.
final shareProvider = Provider<Future<void> Function(XFile file)>(
  (ref) =>
      (file) =>
          ref.read(shareDocumentProvider)(file, 'Your RaajjePro data export'),
);

/// Hands a file to the OS share sheet under a caller-chosen subject.
final shareDocumentProvider =
    Provider<Future<void> Function(XFile file, String subject)>(
      (_) => (file, subject) async {
        await SharePlus.instance.share(
          ShareParams(files: [file], subject: subject),
        );
      },
    );

/// Where a file is written before being handed to the share sheet.
/// `getTemporaryDirectory()` (path_provider), never `Directory.systemTemp` —
/// on Android that is a directory other apps can read, not app-private
/// (final review #5). Injectable so tests never cross a real platform
/// channel; overridden with a plain `Directory.systemTemp` getter in tests,
/// which is a perfectly good stand-in for "some writable temp dir" there.
final tempDirProvider = Provider<Future<Directory> Function()>(
  (_) => getTemporaryDirectory,
);
