import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/storage_service.dart';
import '../services/item_service.dart';
import '../services/app_config_service.dart';
import '../services/media_feedback_service.dart';
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
  bool _loadingPlan = true;
  bool _isPremiumUser = false;
  int _activeListingCount = 0;

  // Location picker state
  String? _selectedMeetupLocation;
  double? _meetupLatitude;
  double? _meetupLongitude;

  String? _selectedCategory;
  String? _selectedCondition;

  @override
  void initState() {
    super.initState();
    _loadPlanStatus();
  }

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

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final file = await picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    setState(() {
      _images.add(bytes);
    });
  }

  Future<void> _pickMeetupLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MeetupLocationScreen()),
    );

    if (result != null && result is Map) {
      setState(() {
        _selectedMeetupLocation = result['location'] as String;
        _meetupLatitude = result['latitude'] as double;
        _meetupLongitude = result['longitude'] as double;
      });
    }
  }

  Future<void> _loadPlanStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 5));
      final data = userDoc.data();
      final isPremium = SubscriptionService.isPremiumActive(data);
      final count = isPremium
          ? 0
          : await SubscriptionService.activeListingCount(user.uid);

      if (!mounted) return;
      setState(() {
        _isPremiumUser = isPremium;
        _activeListingCount = count;
        _loadingPlan = false;
      });
    } catch (e) {
      debugPrint('Failed to load listing plan status: $e');
      if (mounted) setState(() => _loadingPlan = false);
    }
  }

  Future<void> _pickCategory() async {
    final categories = AppConfigService.instance.categories;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView(
        children: categories
            .map(
              (cat) => ListTile(
                title: Text(cat),
                onTap: () => Navigator.pop(context, cat),
              ),
            )
            .toList(),
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
        children: conditions
            .map(
              (cond) => ListTile(
                title: Text(cond),
                onTap: () => Navigator.pop(context, cond),
              ),
            )
            .toList(),
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
                MaterialPageRoute(builder: (_) => const PremiumScreen()),
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
    final validationMessage = _validateItemInputs();
    if (validationMessage != null) {
      _showValidationMessage(validationMessage);
      return;
    }

    final price = double.parse(_price.text.trim());

    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;
        MediaFeedbackService.instance.playError();
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
        MediaFeedbackService.instance.playError();
        FeedbackHelper.showError(context, "User profile not found");
        return;
      }

      final userData = userDoc.data()!;
      final isPremiumUser = SubscriptionService.isPremiumActive(userData);

      // Check listing limit for free users.
      final activeCount = isPremiumUser
          ? 0
          : await SubscriptionService.activeListingCount(uid);
      final canCreate = isPremiumUser || activeCount < 5;
      if (!canCreate) {
        if (!mounted) return;
        FeedbackHelper.hideLoading(context);
        MediaFeedbackService.instance.playError();
        setState(() {
          _isPremiumUser = false;
          _activeListingCount = activeCount;
          _loadingPlan = false;
        });
        _showListingLimitDialog();
        return;
      }

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
        sellerIsPremium: isPremiumUser,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        price: price,
        category: _selectedCategory!,
        condition: _selectedCondition!,
        meetupLocation: _selectedMeetupLocation ?? 'Campus Meetup',
        meetupLatitude: _meetupLatitude ?? 1.8538, // Default: UTHM center
        meetupLongitude: _meetupLongitude ?? 103.0863,
        images: imageUrls,
        isBoosted: isPremiumUser,
      );

      debugPrint('Item saved to Firestore with seller snapshot');

      // Hide loading
      if (!mounted) return;
      FeedbackHelper.hideLoading(context);

      // Show success
      MediaFeedbackService.instance.playSuccess();
      FeedbackHelper.showSuccess(
        context,
        "🎉 Your item has been listed successfully!",
      );

      _loadPlanStatus();

      // Navigate back
      Navigator.pop(context);
    } catch (e, stackTrace) {
      debugPrint('Upload error: $e');
      debugPrint('Stack trace: $stackTrace');

      // Hide loading
      if (mounted) {
        FeedbackHelper.hideLoading(context);
        MediaFeedbackService.instance.playError();

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

  /// Input validation keeps incomplete item posts from reaching Firebase upload.
  String? _validateItemInputs() {
    final title = _title.text.trim();
    final description = _desc.text.trim();
    final priceText = _price.text.trim();
    final price = double.tryParse(priceText);

    if (title.isEmpty) {
      return "Please enter a title for your item";
    }

    if (title.length < 3) {
      return "Title must be at least 3 characters";
    }

    if (title.length > 80) {
      return "Title must be 80 characters or less";
    }

    if (priceText.isEmpty) {
      return "Please enter a price";
    }

    if (price == null || price <= 0) {
      return "Please enter a valid price greater than 0";
    }

    if (price > 99999) {
      return "Please enter a realistic item price";
    }

    if (description.length > 500) {
      return "Description must be 500 characters or less";
    }

    if (_selectedCategory == null) {
      return "Please select a category";
    }

    if (_selectedCondition == null) {
      return "Please select a condition";
    }

    if (_images.isEmpty) {
      return "Please add at least one photo of your item";
    }

    return null;
  }

  void _showValidationMessage(String message) {
    MediaFeedbackService.instance.playError();
    FeedbackHelper.showWarning(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Item")),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPlanStatusCard(),
              const SizedBox(height: 14),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: "Title",
                  hintText: "e.g. UTHM hoodie size M",
                  helperText: "At least 3 characters",
                ),
              ),

              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  labelText: "Price",
                  prefixText: "RM ",
                  helperText: "Numbers only, up to 2 decimal places",
                ),
              ),

              TextField(
                controller: _desc,
                minLines: 1,
                maxLines: 3,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: "Description",
                  hintText:
                      "Add useful details like size, defects, or bundle info",
                ),
              ),

              const SizedBox(height: 14),

              Text(
                'Category',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppConfigService.instance.categories.map((category) {
                  return ChoiceChip(
                    label: Text(category),
                    selected: _selectedCategory == category,
                    onSelected: (_) {
                      setState(() => _selectedCategory = category);
                    },
                    showCheckmark: false,
                  );
                }).toList(),
              ),

              const SizedBox(height: 10),

              // Category Picker fallback for long or remotely configured lists.
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.category_rounded,
                    color: _selectedCategory != null
                        ? Colors.green
                        : Colors.blue,
                  ),
                  title: Text(
                    _selectedCategory ?? 'Select category',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedCategory != null
                          ? Colors.black87
                          : Colors.grey[600],
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
                    color: _selectedCondition != null
                        ? Colors.green
                        : Colors.blue,
                  ),
                  title: Text(
                    _selectedCondition ?? 'Select condition',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedCondition != null
                          ? Colors.black87
                          : Colors.grey[600],
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

              ElevatedButton.icon(
                onPressed: pickImage,
                icon: const Icon(Icons.add_a_photo_rounded),
                label: const Text("Add Image"),
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
    );
  }

  Widget _buildPlanStatusCard() {
    if (_loadingPlan) {
      return const LinearProgressIndicator(minHeight: 3);
    }

    if (_isPremiumUser) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.workspace_premium, color: Colors.amber.shade800),
          title: const Text('Premium Active: Unlimited listings'),
          subtitle: const Text('New listings can receive boosted visibility.'),
        ),
      );
    }

    final reachedLimit = _activeListingCount >= 5;
    return Card(
      child: ListTile(
        leading: Icon(
          reachedLimit ? Icons.lock_outline : Icons.inventory_2_outlined,
          color: reachedLimit ? Colors.orange.shade800 : Colors.blue.shade700,
        ),
        title: Text('$_activeListingCount / 5 active listings used'),
        subtitle: const Text(
          'Free Plan. Upgrade for unlimited listings and boosted visibility.',
        ),
        trailing: reachedLimit
            ? TextButton(
                onPressed: _showListingLimitDialog,
                child: const Text('Upgrade'),
              )
            : null,
      ),
    );
  }
}
