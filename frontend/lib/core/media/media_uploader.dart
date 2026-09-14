import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';

/// The store refused the bytes. Distinct from [ApiNetworkException], which
/// means they never arrived at all.
class MediaUploadException implements Exception {
  const MediaUploadException(this.status);
  final int status;
  @override
  String toString() => 'MediaUploadException($status)';
}

/// Step 2 of §Phase 8's three-step upload: the bytes go **straight to the
/// object store**, at the expiring URL the server issued.
///
/// It deliberately does not go through [ApiClient]. That client attaches a
/// bearer token, decodes an envelope and refreshes an expired session — none
/// of which belongs on a presigned PUT, and the first of which a real S3
/// endpoint would reject outright. The signed URL *is* the authorization.
abstract class MediaUploader {
  Future<void> put({
    required String url,
    required Map<String, String> headers,
    required Uint8List bytes,
  });
}

class HttpMediaUploader implements MediaUploader {
  const HttpMediaUploader(this._http);
  final http.Client _http;

  @override
  Future<void> put({
    required String url,
    required Map<String, String> headers,
    required Uint8List bytes,
  }) async {
    http.StreamedResponse response;
    try {
      final request = http.Request('PUT', Uri.parse(url))
        ..headers.addAll(headers)
        ..bodyBytes = bytes;
      // Generous: 10 MB over an atoll connection is not a fast request, and
      // the upload target itself is good for thirty minutes.
      response = await _http.send(request).timeout(const Duration(minutes: 3));
    } on http.ClientException {
      throw const ApiNetworkException();
    } on SocketException {
      throw const ApiNetworkException();
    } on TimeoutException {
      throw const ApiNetworkException();
    }
    // Drain, so the connection is returned to the pool.
    await response.stream.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MediaUploadException(response.statusCode);
    }
  }
}

final mediaUploaderProvider = Provider<MediaUploader>(
  (ref) => HttpMediaUploader(ref.watch(httpClientProvider)),
);
