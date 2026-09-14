import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// One image the provider chose, already read into memory.
///
/// Bytes rather than a path: the upload is a PUT of the whole object to an
/// expiring URL (§Phase 8's presigned three-step), and a path would have to be
/// re-read at PUT time anyway — by which point the picker's temporary copy
/// may be gone.
class PickedImage {
  const PickedImage({
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });

  final String fileName;

  /// One of the three the API accepts. [MediaPicker] refuses anything else
  /// before an upload target is ever requested, so a provider hears "that
  /// file type isn't supported" from the picker rather than from a failed
  /// upload two round trips later.
  final String contentType;

  final Uint8List bytes;

  int get byteSize => bytes.length;
}

/// Why nothing came back.
enum PickFailure {
  /// The provider closed the picker. Not an error and nothing is shown.
  cancelled,

  /// A file the API would refuse (`ACCEPTED_IMAGE_TYPES`).
  unsupportedType,

  /// Larger than `MAX_IMAGE_BYTES`. Caught here so a 40 MB photo is not
  /// uploaded over an atoll connection only to be rejected at the far end.
  tooLarge,
}

class PickedImageResult {
  const PickedImageResult.picked(PickedImage this.image) : failure = null;
  const PickedImageResult.failed(PickFailure this.failure) : image = null;

  final PickedImage? image;
  final PickFailure? failure;
}

/// The seam over the platform photo library, in the same shape as
/// [PushMessaging]'s seam over FCM: no widget test crosses a platform
/// channel, and the wizard's media step is testable without one.
///
/// Unlike push and crash reporting there is nothing deferred behind it —
/// `image_picker` needs no vendor account and no per-project config file — so
/// the real implementation ships now.
abstract class MediaPicker {
  Future<PickedImageResult> pickImage();
}

/// What the API accepts, mirrored from `backend/src/modules/media/exif.ts`.
/// Checked here for the provider's benefit; the bytes are checked again at
/// `finalise`, which is the check that counts (invariant 4).
const acceptedImageTypes = <String>{'image/jpeg', 'image/png', 'image/webp'};

/// `MAX_IMAGE_BYTES` — 10 MB, and the number the media step's copy quotes.
const maxImageBytes = 10 * 1024 * 1024;

class ImagePickerMediaPicker implements MediaPicker {
  ImagePickerMediaPicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedImageResult> pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      return const PickedImageResult.failed(PickFailure.cancelled);
    }
    final contentType = contentTypeOf(file.mimeType, file.name);
    if (contentType == null) {
      return const PickedImageResult.failed(PickFailure.unsupportedType);
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxImageBytes) {
      return const PickedImageResult.failed(PickFailure.tooLarge);
    }
    return PickedImageResult.picked(
      PickedImage(fileName: file.name, contentType: contentType, bytes: bytes),
    );
  }
}

/// The declared type, or the extension where the platform gave none — Android
/// routinely returns a null `mimeType`. Null for anything the API would
/// refuse.
String? contentTypeOf(String? mimeType, String fileName) {
  final declared = mimeType?.split(';').first.trim().toLowerCase();
  if (declared != null && acceptedImageTypes.contains(declared)) {
    return declared;
  }
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => null,
  };
}

final mediaPickerProvider = Provider<MediaPicker>(
  (_) => ImagePickerMediaPicker(),
);
