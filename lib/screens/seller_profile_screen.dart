import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/item_model.dart';
import '../models/review_model.dart';
import '../services/item_service.dart';
import '../services/review_service.dart';
import '../widgets/item_card.dart';
import '../widgets/review_card.dart';
import 'item_detail_screen.dart';

class SellerProfileScreen extends StatefulWidget {
  final String sellerId;

  const SellerProfileScreen({super.key, required this.sellerId});

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  Map<String, dynamic>? _userData;
  bool _loadingProfile = true;

  @override
  void initState() {
    super.initState();
    _setupUserListener();
  }

  void _setupUserListener() {
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.sellerId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() {
        _userData = doc.data();
        _loadingProfile = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loadingProfile = false);
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  String _maskStudentId(String? studentId) {
    if (studentId == null || studentId.length < 4) return studentId ?? '';
    if (studentId.length <= 6) {
      return '${studentId.substring(0, 2)}****${studentId.substring(studentId.length - 2)}';
    }
    return '${studentId.substring(0, 4)}****${studentId.substring(studentId.length - 2)}';
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
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Color _getTrustScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return Scaffold(
        appBar: AppBar(title: const Text('Seller Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final data = _userData ?? {};
    final name = data['name'] ?? 'Unknown Seller';
    final studentId = data['studentId'] ?? '';
    final profileImage = data['profileImage'] ?? '';
    final rating = (data['rating'] ?? 0).toDouble();
    final trustScore = (data['trustScore'] ?? 0).toDouble();
    final totalReviews = data['totalReviews'] ?? 0;
    final completedTransactions = data['completedTransactions'] ?? 0;
    final activeListingCount = data['activeListingCount'] ?? 0;
    final createdAt = data['createdAt'];

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Profile Header ----
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundImage: profileImage.isNotEmpty
                        ? NetworkImage(profileImage)
                        : null,
                    child: profileImage.isEmpty
                        ? const Icon(Icons.person_rounded, size: 48)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _maskStudentId(studentId),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Member since ${_formatDate(createdAt)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ---- Stats Row ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildStatCard(
                    Icons.star_rounded,
                    rating.toStringAsFixed(1),
                    'Rating',
                    Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  _buildStatCard(
                    Icons.shield_rounded,
                    '${trustScore.toStringAsFixed(0)}',
                    'Trust Score',
                    _getTrustScoreColor(trustScore),
                  ),
                  const SizedBox(width: 8),
                  _buildStatCard(
                    Icons.reviews_rounded,
                    '$totalReviews',
                    'Reviews',
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildStatCard(
                    Icons.check_circle_rounded,
                    '$completedTransactions',
                    'Completed',
                    Colors.green,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ---- Active Listings ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'Active Listings',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$activeListingCount',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildListingsSection(),

            const SizedBox(height: 24),

            // ---- Reviews ----
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Reviews',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildReviewsSection(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListingsSection() {
    return StreamBuilder<List<ItemModel>>(
      stream: ItemService.instance.watchSellerListings(widget.sellerId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('Failed to load listings')),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final listings = snapshot.data!;
        if (listings.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No active listings',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: listings.length,
            itemBuilder: (context, index) {
              final item = listings[index];
              return SizedBox(
                width: 180,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ItemCard(
                    item: item,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ItemDetailScreen(itemId: item.id),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildReviewsSection() {
    return StreamBuilder<List<ReviewModel>>(
      stream: ReviewService.getReviewsForUser(widget.sellerId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('Failed to load reviews')),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final reviews = snapshot.data!;
        if (reviews.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.rate_review_outlined,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No reviews yet',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reviews.length,
          padding: const EdgeInsets.symmetric(horizontal: 0),
          itemBuilder: (context, index) {
            return ReviewCard(review: reviews[index]);
          },
        );
      },
    );
  }
}
