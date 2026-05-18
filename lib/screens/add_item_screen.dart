import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';

import '../services/storage_service.dart';
import '../services/item_service.dart';
import '../constants/app_defaults.dart';
import '../widgets/feedback_helper.dart';

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();

  final List<Uint8List> _images = [];
  final picker = ImagePicker();

  bool _loading = false;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    if (_images.length >= 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Max 4 images allowed")));
      return;
    }

    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final bytes = await file.readAsBytes();

    setState(() {
      _images.add(bytes);
    });
  }

  Future<void> uploadItem() async {
    // Validate inputs
    if (_title.text.trim().isEmpty) {
      FeedbackHelper.showWarning(context, "Please enter a title for your item");
      return;
    }

    if (_price.text.trim().isEmpty) {
      FeedbackHelper.showWarning(context, "Please enter a price");
      return;
    }

    if (_images.isEmpty) {
      FeedbackHelper.showWarning(
        context,
        "Please add at least one photo of your item",
      );
      return;
    }

    // Validate price is a valid number
    final price = double.tryParse(_price.text.trim());
    if (price == null || price <= 0) {
      FeedbackHelper.showError(
        context,
        "Please enter a valid price (greater than 0)",
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;
        FeedbackHelper.showError(context, "Please login to upload items");
        return;
      }

      final uid = user.uid;
      debugPrint('Current user UID: $uid');

      // Show loading feedback
      if (!mounted) return;
      FeedbackHelper.showLoading(
        context,
        message: "Uploading your item...\nThis may take a moment",
      );

      // Fetch seller data ONCE and embed in item (avoids future joins)
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userDoc.exists) {
        if (!mounted) return;
        FeedbackHelper.hideLoading(context);
        FeedbackHelper.showError(context, "User profile not found");
        return;
      }

      final userData = userDoc.data()!;
      final sellerName = userData['name'] ?? 'Unknown';
      final sellerImage =
          userData['profileImage'] ?? AppDefaults.defaultProfileImage;
      final sellerStudentId = userData['studentId'] ?? '';

      final docRef = FirebaseFirestore.instance.collection('items').doc();
      final itemId = docRef.id;

      debugPrint('Uploading ${_images.length} images for item: $itemId');

      // UPLOAD IMAGES (COMPRESSED)
      final imageUrls = await StorageService.instance.uploadItemImages(
        itemId: itemId,
        images: _images,
      );

      debugPrint('Successfully uploaded ${imageUrls.length} images');

      // SAVE ITEM with embedded seller snapshot (eliminates N+1 reads)
      await ItemService.instance.createItem(
        itemId: itemId,
        sellerId: uid,
        sellerName: sellerName,
        sellerImage: sellerImage,
        sellerStudentId: sellerStudentId,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        price: price,
        category: 'Others', // TODO: Add category picker
        condition: 'Used', // TODO: Add condition picker
        meetupLocation: 'Library', // TODO: Add location picker
        images: imageUrls,
      );

      debugPrint('Item saved to Firestore with seller snapshot');

      // Hide loading
      if (!mounted) return;
      FeedbackHelper.hideLoading(context);

      // Show success
      FeedbackHelper.showSuccess(
        context,
        "Your item has been listed successfully!",
      );

      // Navigate back
      Navigator.pop(context);
    } catch (e, stackTrace) {
      debugPrint('Upload error: $e');
      debugPrint('Stack trace: $stackTrace');

      // Hide loading
      if (mounted) {
        FeedbackHelper.hideLoading(context);

        // Show specific error messages
        if (e.toString().contains('storage/unauthorized')) {
          FeedbackHelper.showError(
            context,
            "Storage permission denied. Please check Firebase Storage rules.",
          );
        } else if (e.toString().contains('permission-denied')) {
          FeedbackHelper.showError(
            context,
            "Permission denied. Please check Firestore security rules.",
          );
        } else if (e.toString().contains('network')) {
          FeedbackHelper.showError(
            context,
            "Network error. Please check your internet connection.",
          );
        } else {
          FeedbackHelper.showError(context, "Failed to upload item: $e");
        }
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Item")),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _title,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: "Title"),
                  ),

                  TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: "Price"),
                  ),

                  TextField(
                    controller: _desc,
                    minLines: 3,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(labelText: "Description"),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    "You can upload up to 4 images per item.",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),

                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _images.map((img) {
                      return Stack(
                        children: [
                          Image.memory(
                            img,
                            height: 70,
                            width: 70,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            right: 0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _images.remove(img);
                                });
                              },
                              child: const Icon(Icons.close, color: Colors.red),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 10),

                  ElevatedButton(
                    onPressed: _loading ? null : pickImage,
                    child: const Text("Add Image"),
                  ),

                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: _loading ? null : uploadItem,
                    child: Text(_loading ? "Uploading..." : "Upload Item"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
