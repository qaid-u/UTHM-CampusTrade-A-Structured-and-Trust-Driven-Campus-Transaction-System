import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_defaults.dart';
import '../screens/item_detail_screen.dart';
import '../services/auth_service.dart';
import '../services/item_service.dart';
import '../services/storage_service.dart';
import '../models/item_model.dart';
import '../widgets/feedback_helper.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final usersRef = FirebaseFirestore.instance.collection('users');
  final ImagePicker _picker = ImagePicker();

  // Cache user data to avoid repeated reads
  Map<String, dynamic>? _userData;
  List<ItemModel> _myItems = [];
  bool _loadingProfile = true;
  bool _loadingItems = true;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshProfile();
    });
    _loadProfileData();
    _loadMyItems();
  }

  Future<void> _loadProfileData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await usersRef.doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userData = doc.data();
          _loadingProfile = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingProfile = false);
      }
    }
  }

  Future<void> _loadMyItems() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final items = await ItemService.instance.getItems(limit: 50);

      // Filter only my items
      final myItems = items['items'] as List<ItemModel>;
      final filtered = myItems
          .where((item) => item.sellerId == user.uid)
          .toList();

      if (mounted) {
        setState(() {
          _myItems = filtered;
          _loadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingItems = false);
      }
    }
  }

  Future<void> _refreshProfile() async {
    setState(() {
      _loadingProfile = true;
      _loadingItems = true;
    });
    await Future.wait([_loadProfileData(), _loadMyItems()]);
  }

  // -------------------------
  // PROFILE IMAGE UPLOAD
  // -------------------------
  Future<void> _changeProfileImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Show image source selection
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take a Photo'),
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

    try {
      // Pick image
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );

      if (image == null) {
        if (mounted) {
          FeedbackHelper.showWarning(context, "No image selected");
        }
        return;
      }

      // Show loading
      if (!mounted) return;
      setState(() => _uploadingImage = true);
      FeedbackHelper.showLoading(
        context,
        message: "Uploading new profile photo...",
      );

      // Read image bytes
      final Uint8List imageBytes = await image.readAsBytes();

      debugPrint('Uploading profile image: ${imageBytes.length} bytes');

      // Upload to Firebase Storage (with compression)
      final downloadUrl = await StorageService.instance.uploadProfileImage(
        uid: user.uid,
        bytes: imageBytes,
      );

      debugPrint('Profile image uploaded: $downloadUrl');

      // Update Firestore with new image URL
      await usersRef.doc(user.uid).update({
        'profileImage': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      FeedbackHelper.hideLoading(context);
      FeedbackHelper.showSuccess(
        context,
        "Profile photo updated successfully!",
      );

      // Reload profile to show new image
      await _loadProfileData();
    } catch (e) {
      debugPrint('Profile image upload error: $e');

      if (!mounted) return;
      FeedbackHelper.hideLoading(context);

      // Show specific error messages
      if (e.toString().contains('permission-denied') ||
          e.toString().contains('unauthorized')) {
        FeedbackHelper.showError(
          context,
          "Storage permission denied. Please check Firebase Storage rules.",
        );
      } else if (e.toString().contains('network')) {
        FeedbackHelper.showError(
          context,
          "Network error. Please check your internet connection.",
        );
      } else {
        FeedbackHelper.showError(context, "Failed to update profile photo: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  Future<void> editField(String field, String currentValue) async {
    String newValue = currentValue;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit $field"),
        content: TextField(
          controller: TextEditingController(text: currentValue),
          onChanged: (v) => newValue = v,
          decoration: InputDecoration(
            hintText: "Enter new $field",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, newValue),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;

    // Show loading
    if (!mounted) return;
    FeedbackHelper.showLoading(context, message: "Saving changes...");

    try {
      await usersRef.doc(user.uid).update({field: result.trim()});

      if (!mounted) return;
      FeedbackHelper.hideLoading(context);
      FeedbackHelper.showSuccess(context, "$field updated successfully!");

      // Reload profile to reflect changes
      await _loadProfileData();
    } catch (e) {
      if (!mounted) return;
      FeedbackHelper.hideLoading(context);
      FeedbackHelper.showError(context, "Failed to update $field: $e");
    }
  }

  // -------------------------
  // LOGOUT CONFIRMATION
  // -------------------------
  Future<void> _confirmLogout() async {
    final confirm = await FeedbackHelper.showConfirmation(
      context,
      title: "Logout",
      message:
          "You are about to log out of your account.\n\nMake sure your data is synced before continuing.",
      confirmText: "Logout",
      cancelText: "Cancel",
      confirmColor: Colors.red,
    );

    if (!confirm) return;

    // Show loading
    if (!mounted) return;
    FeedbackHelper.showLoading(context, message: "Logging out...");

    try {
      await AuthService.instance.logout();

      if (!mounted) return;
      FeedbackHelper.hideLoading(context);
      FeedbackHelper.showSuccess(context, "Logged out successfully");
    } catch (e) {
      if (!mounted) return;
      FeedbackHelper.hideLoading(context);
      FeedbackHelper.showError(context, "Failed to logout: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Please log in to view profile")),
      );
    }

    // Show loading while fetching profile data
    if (_loadingProfile) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final data = _userData ?? {};
    final name = data['name'] ?? 'No name';
    final email = user.email ?? '';
    final rawImage = data['profileImage'];
    final profileImage = (rawImage == null || rawImage.toString().isEmpty)
        ? AppDefaults.defaultProfileImage
        : rawImage;
    final bio = data['bio'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshProfile,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _confirmLogout,
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Profile image with edit button
              Stack(
                children: [
                  CircleAvatar(
                    radius: 45,
                    backgroundImage: NetworkImage(profileImage),
                    onBackgroundImageError: (_, __) {
                      // Fallback to default image if network image fails
                    },
                  ),
                  // Upload overlay indicator
                  if (_uploadingImage)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                    ),
                  // Edit button
                  if (!_uploadingImage)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Material(
                        color: Theme.of(context).primaryColor,
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: InkWell(
                          onTap: _changeProfileImage,
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              Text(email, style: const TextStyle(color: Colors.grey)),

              // Change photo button
              TextButton.icon(
                onPressed: _uploadingImage ? null : _changeProfileImage,
                icon: _uploadingImage
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue,
                          ),
                        ),
                      )
                    : const Icon(Icons.photo_camera_rounded, size: 18),
                label: Text(
                  _uploadingImage ? "Uploading..." : "Change Profile Photo",
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Divider(),

              ListTile(
                title: const Text("Username"),
                subtitle: Text(name),
                trailing: const Icon(Icons.edit),
                onTap: () => editField("name", name),
              ),

              ListTile(
                title: const Text("Bio"),
                subtitle: Text(bio),
                trailing: const Icon(Icons.edit),
                onTap: () => editField("bio", bio),
              ),

              const Divider(),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      "My Listings",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              if (_loadingItems)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_myItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text("No items posted yet")),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _myItems.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    final item = _myItems[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: (item.thumbnail.isEmpty)
                            ? const Icon(Icons.image)
                            : Image.network(
                                item.thumbnail,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.image),
                              ),
                        title: Text(item.title),
                        subtitle: Text("RM ${item.price.toStringAsFixed(2)}"),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItemDetailScreen(itemId: item.id),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
