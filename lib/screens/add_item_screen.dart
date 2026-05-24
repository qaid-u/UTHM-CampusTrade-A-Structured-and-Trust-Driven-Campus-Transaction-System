import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';

import '../services/storage_service.dart';
import '../services/item_service.dart';
import '../services/app_config_service.dart';
import '../services/subscription_service.dart';
import '../constants/app_defaults.dart';
import '../widgets/feedback_helper.dart';
import 'meetup_location_screen.dart';
import 'premium_screen.dart';

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
  
  // Location picker state
  String? _selectedMeetupLocation;
  double? _meetupLatitude;
  double? _meetupLongitude;
  
  String? _selectedCategory;
  String? _selectedCondition;

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

  Future<void> _pickMeetupLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MeetupLocationScreen(),
      ),
    );

    if (result != null && result is Map) {
      setState(() {
        _selectedMeetupLocation = result['location'] as String;
        _meetupLatitude = result['latitude'] as double;
        _meetupLongitude = result['longitude'] as double;
      });
    }
  }

  Future<void> _pickCategory() async {
    final categories = AppConfigService.instance.categories;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView(
        children: categories.map((cat) => ListTile(
          title: Text(cat),
          onTap: () => Navigator.pop(context, cat),
        )).toList(),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedCategory = selected);
    }
  }

  Future<void> _pickCondition() async {
    final conditions = AppConfigService.instance.conditions;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView(
        children: conditions.map((cond) => ListTile(
          title: Text(cond),
          onTap: () => Navigator.pop(context, cond),
        )).toList(),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedCondition = selected);
    }
  }

  /// Shows a dialog when the free user listing limit is reached.
  Future<void> _showListingLimitDialog() {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Listing Limit Reached',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: const Text(
          'Free accounts may only have 5 active listings at a time. '
          'Upgrade to Premium to unlock unlimited listings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                this.context,
                MaterialPageRoute(
                  builder: (_) => const PremiumScreen(),
                ),
              );
            },
            icon: const Icon(Icons.workspace_premium, size: 18),
            label: const Text('Upgrade Now'),
          ),
        ],
      ),
    );
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

    if (_selectedCategory == null) {
      FeedbackHelper.showWarning(context, "Please select a category");
      return;
    }

    if (_selectedCondition == null) {
      FeedbackHelper.showWarning(context, "Please select a condition");
      return;
    }

    // Check listing limit for free users.
    final canCreate = await SubscriptionService.instance.canCreateListing();
    if (!canCreate) {
      _showListingLimitDialog();
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
        category: _selectedCategory!,
        condition: _selectedCondition!,
        meetupLocation: _selectedMeetupLocation ?? 'Campus Meetup',
        meetupLatitude: _meetupLatitude ?? 1.8538, // Default: UTHM center
        meetupLongitude: _meetupLongitude ?? 103.0863,
        images: imageUrls,
        isBoosted: SubscriptionService.instance.isPremium,
      );

      debugPrint('Item saved to Firestore with seller snapshot');

      // Hide loading
      if (!mounted) return;
      FeedbackHelper.hideLoading(context);

      // Show success
      FeedbackHelper.showSuccess(
        context,
        "🎉 Your item has been listed successfully!",
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

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: "Title"),
            ),

            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Price"),
            ),

            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: "Description"),
            ),

            const SizedBox(height: 10),

            // Category Picker
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.category_rounded,
                  color: _selectedCategory != null ? Colors.green : Colors.blue,
                ),
                title: Text(
                  _selectedCategory ?? 'Select category',
                  style: TextStyle(
                    fontSize: 14,
                    color: _selectedCategory != null ? Colors.black87 : Colors.grey[600],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickCategory,
              ),
            ),

            const SizedBox(height: 10),

            // Condition Picker
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.build_rounded,
                  color: _selectedCondition != null ? Colors.green : Colors.blue,
                ),
                title: Text(
                  _selectedCondition ?? 'Select condition',
                  style: TextStyle(
                    fontSize: 14,
                    color: _selectedCondition != null ? Colors.black87 : Colors.grey[600],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickCondition,
              ),
            ),

            const SizedBox(height: 10),

            // Meetup Location Picker
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.location_on,
                  color: _selectedMeetupLocation != null
                      ? Colors.green
                      : Colors.blue,
                ),
                title: Text(
                  _selectedMeetupLocation ?? 'Select pickup location',
                  style: TextStyle(
                    fontSize: 14,
                    color: _selectedMeetupLocation != null
                        ? Colors.black87
                        : Colors.grey[600],
                  ),
                ),
                subtitle: _selectedMeetupLocation != null
                    ? const Text('Tap to change location')
                    : const Text('Recommended for faster transactions'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickMeetupLocation,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              "You can upload up to 4 images per item.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              children: _images.map((img) {
                return Stack(
                  children: [
                    Image.memory(img, height: 70, width: 70, fit: BoxFit.cover),
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
              onPressed: pickImage,
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
    );
  }
}
