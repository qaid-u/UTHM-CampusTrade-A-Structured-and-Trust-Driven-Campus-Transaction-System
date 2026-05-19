import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../firebase_options.dart';

class StorageService {
  StorageService._();
  static final instance = StorageService._();

  FirebaseStorage get _storage => FirebaseStorage.instanceFor(
    bucket: DefaultFirebaseOptions.currentPlatform.storageBucket,
  );

  String get bucketName => _storage.bucket;

  List<String> itemImagePaths(String itemId, int imageCount) {
    return List.generate(imageCount, (index) => 'items/$itemId/img_$index.jpg');
  }

  Future<String> downloadUrlFor(String source, {String? bucket}) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw Exception('Empty image source');
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    final storage = bucket == null || bucket.isEmpty
        ? _storage
        : FirebaseStorage.instanceFor(bucket: bucket);

    if (trimmed.startsWith('gs://')) {
      return storage.refFromURL(trimmed).getDownloadURL();
    }

    final path = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    return storage.ref().child(path).getDownloadURL();
  }

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
      ).timeout(const Duration(seconds: 30));

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
    debugPrint('Firebase Storage bucket: ${_storage.bucket}');

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

        final metadata = SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'itemId': itemId, 'imageIndex': '$i'},
        );

        // Wait for the upload to complete and get the snapshot
        final TaskSnapshot snapshot = await ref
            .putData(compressed, metadata)
            .timeout(const Duration(seconds: 45));

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
        final url = await ref.getDownloadURL().timeout(
          const Duration(seconds: 20),
        );

        debugPrint('Successfully got URL for image $i');

        if (url.isEmpty) {
          throw Exception("Failed to get URL for image $i");
        }

        urls.add(url);
      } catch (e, stackTrace) {
        debugPrint('Error uploading image $i: $e');
        debugPrint('Stack trace: $stackTrace');
        // IMPORTANT: fail fast instead of hiding issues
        throw Exception(_friendlyUploadError(e, i));
      }
    }

    return urls;
  }

  Future<String> uploadChatImage({
    required String roomId,
    required String senderId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Empty chat image');
    }

    final compressed = _compressImage(bytes, maxWidth: 1280);
    final fileName = DateTime.now().millisecondsSinceEpoch;
    final path = 'chats/$roomId/$senderId-$fileName.jpg';
    final ref = _storage.ref().child(path);

    final snapshot = await ref
        .putData(
          compressed,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {'roomId': roomId, 'senderId': senderId},
          ),
        )
        .timeout(const Duration(seconds: 45));

    if (snapshot.state != TaskState.success) {
      throw Exception('Chat image upload failed');
    }

    return ref.getDownloadURL();
  }

  Future<String> uploadTransactionProof({
    required String transactionId,
    required String userId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Empty payment proof image');
    }

    final compressed = _compressImage(bytes, maxWidth: 1280);
    final fileName = DateTime.now().millisecondsSinceEpoch;
    final path = 'transactions/$transactionId/payment_proof_$userId-$fileName.jpg';
    final ref = _storage.ref().child(path);

    final snapshot = await ref
        .putData(
          compressed,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {'transactionId': transactionId, 'userId': userId},
          ),
        )
        .timeout(const Duration(seconds: 45));

    if (snapshot.state != TaskState.success) {
      throw Exception('Payment proof upload failed');
    }

    return ref.getDownloadURL();
  }

  String _friendlyUploadError(Object error, int index) {
    final message = error.toString();

    if (message.contains('storage/unauthorized') ||
        message.contains('unauthorized') ||
        message.contains('permission-denied')) {
      return 'Item image upload failed (image ${index + 1}): Storage permission denied. Deploy storage.rules to the Firebase project used by the app.';
    }

    if (message.contains('storage/object-not-found') ||
        message.contains('bucket-not-found') ||
        message.contains('NoSuchBucket')) {
      return 'Item image upload failed (image ${index + 1}): Firebase Storage bucket was not found. Make sure Storage is enabled for ${DefaultFirebaseOptions.currentPlatform.projectId}.';
    }

    if (message.contains('timed out') || message.contains('TimeoutException')) {
      return 'Item image upload failed (image ${index + 1}): Upload timed out. Check internet connection and Firebase Storage availability.';
    }

    return 'Item image upload failed (image ${index + 1}): $message';
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
}
