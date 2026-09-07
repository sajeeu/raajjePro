import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "iPhone 14", "Pixel 7" — what the sessions list shows. Falls back to the
/// platform name; never fails a sign-in over it.
final deviceNameProvider = FutureProvider<String>((ref) async {
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return '${a.manufacturer} ${a.model}'.trim();
    }
    if (Platform.isIOS) {
      final i = await info.iosInfo;
      return i.name;
    }
  } on Object {
    // fall through
  }
  return Platform.operatingSystem;
});
