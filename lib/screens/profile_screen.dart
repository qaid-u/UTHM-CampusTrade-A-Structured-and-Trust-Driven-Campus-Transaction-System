import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_defaults.dart';
import '../screens/item_detail_screen.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../models/item_model.dart';
import '../widgets/feedback_helper.dart';
import '../widgets/premium_badge.dart';
import '../services/subscription_service.dart';
import 'premium_screen.dart';

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

  // Realtime user document subscription for trust score updates
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userDocSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshProfile();
    });
    _setupUserDocListener();
    _loadMyItems();
  }

  /// Real-time listener for user document — auto-updates trust score, rating, etc.
  void _setupUserDocListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userDocSubscription = usersRef.doc(user.uid).snapshots().listen(
      (doc) {
        if (!mounted) return;
        if (doc.exists) {
          setState(() {
            _userData = doc.data();
            _loadingProfile = false;
          });
        }
      },
      onError: (e) {
        debugPrint('User doc stream error: $e');
        if (mounted) {
          setState(() => _loadingProfile = false);
        }
      },
    );
  }

  Future<void> _loadMyItems() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // OPTIMIZED: Use sellerId query instead of fetching all items
      final items = await FirebaseFirestore.instance
          .collection('items')
          .where('sellerId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 5));

      final filtered = items.docs
          .map((doc) => ItemModel.fromFirestore(doc))
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
      _loadingItems = true;
    });
    await _loadMyItems();
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    super.dispose();
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
      // Realtime stream listener will auto-update
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
      // Realtime stream listener will auto-update
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

  /// Builds a star rating string from a numeric rating value
  String _buildStarRating(double rating) {
    final fullStars = rating.floor();
    final hasHalfStar = (rating - fullStars) >= 0.5;
    final emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0);
    return '${'★' * fullStars}${hasHalfStar ? '½' : ''}${'☆' * emptyStars}';
  }

  /// Returns a color based on trust score value
  Color _getTrustScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
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
                          color: Colors.black.withValues(alpha: 0.5),
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

              // Trust Score Section
              if (data['trustScore'] != null) ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    "Trust Profile",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.star_rounded, color: Colors.amber),
                  title: Text(
                    "${_buildStarRating((data['rating'] ?? 0).toDouble())}  Rating: ${(data['rating'] ?? 0).toStringAsFixed(1)}",
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle_rounded, color: Colors.green),
                  title: Text("Completed Transactions: ${data['completedTransactions'] ?? 0}"),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Trust Score: ${(data['trustScore'] ?? 0).toStringAsFixed(1)}/100",
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: ((data['trustScore'] ?? 0).toDouble()) / 100,
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getTrustScoreColor((data['trustScore'] ?? 0).toDouble()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Subscription Section
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Subscription',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (data['subscriptionTier'] == 'premium' &&
                  SubscriptionService.isPremiumActive(data)) ...[
                ListTile(
                  leading: Icon(
                    Icons.verified_rounded,
                    color: Colors.amber.shade700,
                  ),
                  title: const Text('Premium Active'),
                  subtitle: Text(
                    'Expires: ${_formatDate(data['premiumExpiryDate'])}',
                  ),
                  trailing: const PremiumBadge(),
                ),
              ] else ...[                
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      Navigator.push(
                        this.context,
                        MaterialPageRoute(
                          builder: (_) => const PremiumScreen(),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.amber.shade50,
                            child: Icon(
                              Icons.workspace_premium,
                              color: Colors.amber.shade700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Go Premium',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'Unlock unlimited listings and boosted visibility',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

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

  String _formatDate(dynamic date) {
    if (date == null) return '';
    DateTime dt;
    if (date is Timestamp) {
      dt = date.toDate();
    } else if (date is DateTime) {
      dt = date;
    } else {
      return '';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}