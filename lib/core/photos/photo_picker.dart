import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoFrom { camera, gallery }

/// Takes or chooses a photo of a person, already shrunk to a small JPEG
/// that fits on their Firestore record (no paid Storage plan needed).
abstract class PhotoPicker {
  const PhotoPicker();

  /// Longest side, in pixels. Plenty for a face on a phone screen.
  static const size = 240.0;

  /// The security rules refuse anything bigger.
  static const maxBytes = 100 * 1024;

  /// Swapped for a fake in tests.
  static PhotoPicker instance = const DevicePhotoPicker();

  /// The photo, or null if the person cancelled.
  Future<Uint8List?> pick(PhotoFrom from);
}

class DevicePhotoPicker extends PhotoPicker {
  const DevicePhotoPicker();

  @override
  Future<Uint8List?> pick(PhotoFrom from) async {
    final file = await ImagePicker().pickImage(
      source: from == PhotoFrom.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: PhotoPicker.size,
      maxHeight: PhotoPicker.size,
      imageQuality: 70,
      // Faces are photographed with the front camera more often, but a
      // supervisor photographs a worker: the back camera.
      preferredCameraDevice: CameraDevice.rear,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }
}
