import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:raajjepro/core/offline/pending_request.dart';

/// Where the queue survives the process.
///
/// An interface rather than a direct file write for the reason every other
/// platform boundary in `core/` is one: a widget test must not cross a
/// platform channel (`tempDirProvider` in `AccountController` set the
/// pattern).
abstract class OfflineQueueStore {
  Future<List<PendingRequest>> read();
  Future<void> write(List<PendingRequest> queue);
}

/// Where the queue file lives. `getApplicationDocumentsDirectory()`, never
/// `Directory.systemTemp` — a temp directory is exactly the one the OS is
/// entitled to empty, and on Android it is not app-private.
final queueDirectoryProvider = Provider<Future<Directory> Function()>(
  (_) => getApplicationDocumentsDirectory,
);

/// The default store: one small JSON file.
///
/// **Every failure degrades to no persistence rather than to an error.** The
/// in-memory queue in [OfflineQueue] is authoritative and this is a safety
/// net under it; a device with a full disk should still let a provider fill
/// in their listing.
class FileOfflineQueueStore implements OfflineQueueStore {
  const FileOfflineQueueStore(this._directory);

  final Future<Directory> Function() _directory;

  static const _fileName = 'offline-queue.json';

  Future<File?> _file() async {
    try {
      final dir = await _directory();
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    } on Object {
      return null;
    }
  }

  @override
  Future<List<PendingRequest>> read() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return const [];
      return PendingRequest.decode(await file.readAsString());
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> write(List<PendingRequest> queue) async {
    try {
      final file = await _file();
      if (file == null) return;
      if (queue.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }
      await file.writeAsString(PendingRequest.encode(queue), flush: true);
    } on Object {
      // Deliberately swallowed — see the class note.
    }
  }
}

final offlineQueueStoreProvider = Provider<OfflineQueueStore>(
  (ref) => FileOfflineQueueStore(ref.watch(queueDirectoryProvider)),
);
