import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class StorageService {
  StorageService._();
  static final instance = StorageService._();

  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Image optimization settings
  static const int maxImageWidth = 1280;
  static const int quality = 70;

  /// Compress image to reduce storage and bandwidth costs
  Uint8List _compressImage(Uint8List bytes, {int maxWidth = maxImageWidth}) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return bytes;

      // Resize if too large
      if (image.width > maxWidth) {
        final resized = img.copyResize(
          image,
          width: maxWidth,
          height: (image.height * maxWidth ~/ image.width),
        );
        return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      }

      // Just compress if size is ok
      return Uint8List.fromList(img.encodeJpg(image, quality: quality));
    } catch (e) {
      debugPrint('Image compression failed: $e');
      return bytes; // Return original if compression fails
    }
  }

  /// ---------------------------
  /// PROFILE IMAGE UPLOAD
  /// ---------------------------
  Future<String> uploadProfileImage({
    required String uid,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw Exception("Empty image data");
    }

    final ref = _storage.ref().child('users/$uid/profile.jpg');

    try {
      final uploadTask = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      if (uploadTask.state != TaskState.success) {
        throw Exception("Profile upload failed");
      }

      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception("Profile image upload error: $e");
    }
  }

  /// ---------------------------
  /// ITEM IMAGES (MAX 4, COMPRESSED)
  /// ---------------------------
  Future<List<String>> uploadItemImages({
    required String itemId,
    required List<Uint8List> images,
  }) async {
    if (images.isEmpty) {
      throw Exception("At least 1 image required");
    }

    if (images.length > 4) {
      throw Exception("Maximum 4 images allowed");
    }

    final List<String> urls = [];

    for (int i = 0; i < images.length; i++) {
      final bytes = images[i];

      if (bytes.isEmpty) {
        throw Exception("Image $i is empty");
      }

      // Compress image before upload (saves storage + bandwidth)
      final compressed = _compressImage(bytes);
      final originalSize = bytes.length;
      final compressedSize = compressed.length;
      final savings = ((1 - compressedSize / originalSize) * 100)
          .toStringAsFixed(1);

      debugPrint(
        'Image $i: $originalSize -> $compressedSize bytes ($savings% smaller)',
      );

      final path = 'items/$itemId/img_$i.jpg';
      final ref = _storage.ref().child(path);

      try {
        debugPrint('Uploading image $i to path: $path');

        final uploadTask = ref.putData(
          compressed,
          SettableMetadata(contentType: 'image/jpeg'),
        );

        // Wait for the upload to complete and get the snapshot
        final TaskSnapshot snapshot = await uploadTask;

        debugPrint('Upload task completed with state: ${snapshot.state}');

        // Check if upload was successful
        if (snapshot.state == TaskState.error) {
          throw Exception("Upload failed with error at image index $i");
        }

        if (snapshot.state != TaskState.success) {
          throw Exception(
            "Upload did not complete successfully at image index $i (state: ${snapshot.state})",
          );
        }

        // Get the download URL from the reference
        debugPrint('Getting download URL for image $i');
        final url = await ref.getDownloadURL();

        debugPrint('Successfully got URL for image $i');

        if (url.isEmpty) {
          throw Exception("Failed to get URL for image $i");
        }

        urls.add(url);
      } catch (e, stackTrace) {
        debugPrint('Error uploading image $i: $e');
        debugPrint('Stack trace: $stackTrace');
        // IMPORTANT: fail fast instead of hiding issues
        throw Exception("Item image upload failed (index $i): $e");
      }
    }

    return urls;
  }

  /// ---------------------------
  /// DELETE ITEM IMAGES
  /// ---------------------------
  Future<void> deleteItemImages(String itemId) async {
    try {
      final folder = _storage.ref().child('items/$itemId');
      final list = await folder.listAll();

      for (final item in list.items) {
        await item.delete();
      }
    } catch (e) {
      throw Exception("Failed to delete item images: $e");
    }
  }
  /// ---------------------------
  /// CHAT RECEIPT IMAGES
  /// ---------------------------
  Future<String> uploadChatImage({
    required String roomId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) throw Exception("Empty image data");

    // Compress to save storage/bandwidth on receipts
    final compressed = _compressImage(bytes);
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('chats/$roomId/$fileName');

    try {
      final uploadTask = await ref.putData(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      if (uploadTask.state != TaskState.success) {
        throw Exception("Chat image upload failed");
      }
      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception("Chat image upload error: $e");
    }
  }
}
