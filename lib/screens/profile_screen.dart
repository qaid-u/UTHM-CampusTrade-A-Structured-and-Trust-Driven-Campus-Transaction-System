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
import '../models/review_model.dart';
import '../widgets/feedback_helper.dart';
import '../widgets/premium_badge.dart';
import '../widgets/review_card.dart';
import '../services/subscription_service.dart';
import '../services/review_service.dart';
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _myItemsSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshProfile();
    });
    _setupUserDocListener();
    _setupMyItemsListener();
  }

  /// Real-time listener for user document — auto-updates trust score, rating, etc.
  void _setupUserDocListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userDocSubscription = usersRef
        .doc(user.uid)
        .snapshots()
        .listen(
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

  void _setupMyItemsListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _myItemsSubscription?.cancel();
    _myItemsSubscription = FirebaseFirestore.instance
        .collection('items')
        .where('sellerId', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen(
          (items) {
            final filtered =
                items.docs.map((doc) => ItemModel.fromFirestore(doc)).toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            if (!mounted) return;
            setState(() {
              _myItems = filtered;
              _loadingItems = false;
            });
          },
          onError: (e) {
            debugPrint('My listings stream error: $e');
            if (mounted) setState(() => _loadingItems = false);
          },
        );
  }

  Future<void> _loadMyItems() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final items = await FirebaseFirestore.instance
          .collection('items')
          .where('sellerId', isEqualTo: user.uid)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 5));

      final filtered =
          items.docs.map((doc) => ItemModel.fromFirestore(doc)).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
    _myItemsSubscription?.cancel();
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
    final isPremium = SubscriptionService.isPremiumActive(data);
    final activeListingCount = _myItems
        .where((item) => item.status == 'available')
        .length;

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
                  leading: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                  ),
                  title: Text(
                    "Completed Transactions: ${data['completedTransactions'] ?? 0}",
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                            _getTrustScoreColor(
                              (data['trustScore'] ?? 0).toDouble(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              _buildReviewsReceivedSection(user.uid),

              _buildPlanCard(
                data: data,
                isPremium: isPremium,
                activeListingCount: activeListingCount,
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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("RM ${item.price.toStringAsFixed(2)}"),
                            const SizedBox(height: 4),
                            _buildListingStatusChip(item.status),
                          ],
                        ),
                        isThreeLine: true,
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

  Widget _buildListingStatusChip(String status) {
    final normalized = status.trim().toLowerCase();
    final style = _listingStatusStyle(normalized);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.foreground.withValues(alpha: 0.35)),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: style.foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  _ListingStatusStyle _listingStatusStyle(String status) {
    switch (status) {
      case 'available':
        return _ListingStatusStyle(
          label: 'Available',
          foreground: Colors.green.shade800,
          background: Colors.green.shade50,
        );
      case 'reserved':
        return _ListingStatusStyle(
          label: 'Reserved',
          foreground: Colors.orange.shade900,
          background: Colors.orange.shade50,
        );
      case 'sold':
        return _ListingStatusStyle(
          label: 'Sold',
          foreground: Colors.blueGrey.shade800,
          background: Colors.blueGrey.shade50,
        );
      case 'hidden':
      case 'inactive':
        return _ListingStatusStyle(
          label: 'Inactive',
          foreground: Colors.grey.shade800,
          background: Colors.grey.shade100,
        );
      default:
        return _ListingStatusStyle(
          label: status.isEmpty
              ? 'Unknown'
              : status[0].toUpperCase() + status.substring(1),
          foreground: Colors.grey.shade800,
          background: Colors.grey.shade100,
        );
    }
  }

  Widget _buildReviewsReceivedSection(String userId) {
    return StreamBuilder<List<ReviewModel>>(
      stream: ReviewService.getReviewsForUser(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 3),
          );
        }

        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('Failed to load reviews'),
          );
        }

        final reviews = snapshot.data ?? const <ReviewModel>[];
        final averageRating = reviews.isEmpty
            ? 0.0
            : reviews.fold<int>(0, (sum, review) => sum + review.rating) /
                  reviews.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Reviews Received',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (reviews.isNotEmpty)
                    Text(
                      '${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildReviewStars(averageRating),
                  const SizedBox(width: 8),
                  Text(
                    reviews.isEmpty
                        ? 'No stars yet'
                        : averageRating.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Stars from completed transaction reviews will appear here.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              )
            else
              ...reviews
                  .take(3)
                  .map((review) => _ReviewCardWithReviewerName(review: review)),
          ],
        );
      },
    );
  }

  Widget _buildReviewStars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starNumber = index + 1;
        final icon = rating >= starNumber
            ? Icons.star_rounded
            : rating >= starNumber - 0.5
            ? Icons.star_half_rounded
            : Icons.star_border_rounded;

        return Icon(icon, size: 22, color: Colors.amber.shade700);
      }),
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

  Widget _buildPlanCard({
    required Map<String, dynamic> data,
    required bool isPremium,
    required int activeListingCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isPremium
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        PremiumBadge(),
                        Spacer(),
                        Icon(Icons.workspace_premium, color: Colors.amber),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Unlimited listings enabled',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text('Boosted visibility active'),
                    if (_formatDate(data['premiumExpiryDate']).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Expires: ${_formatDate(data['premiumExpiryDate'])}',
                      ),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Free Plan',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('$activeListingCount / 5 active listings used'),
                    const SizedBox(height: 4),
                    const Text(
                      'Upgrade for unlimited listings and boosted visibility.',
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PremiumScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.workspace_premium),
                        label: const Text('Upgrade to Premium'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ReviewCardWithReviewerName extends StatelessWidget {
  const _ReviewCardWithReviewerName({required this.review});

  final ReviewModel review;

  @override
  Widget build(BuildContext context) {
    if (review.reviewerName.isNotEmpty) {
      return ReviewCard(review: review, showReviewerName: true);
    }

    return FutureBuilder<String>(
      future: ReviewService.getReviewerName(review.reviewerId),
      builder: (context, snapshot) {
        final name = snapshot.data ?? '';
        return ReviewCard(
          review: ReviewModel(
            id: review.id,
            transactionId: review.transactionId,
            reviewerId: review.reviewerId,
            revieweeId: review.revieweeId,
            reviewerName: name,
            rating: review.rating,
            comment: review.comment,
            createdAt: review.createdAt,
          ),
          showReviewerName: true,
        );
      },
    );
  }
}

class _ListingStatusStyle {
  const _ListingStatusStyle({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;
}
