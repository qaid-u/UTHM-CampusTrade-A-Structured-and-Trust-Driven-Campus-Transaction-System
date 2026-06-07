import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/review_model.dart';
import 'trust_score_service.dart';

class ReviewService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> submitReview({
    required String transactionId,
    required String reviewerId,
    required String revieweeId,
    required int rating,
    required String comment,
  }) async {
    final docId = '${transactionId}_$reviewerId';
    String reviewerName = '';
    try {
      final reviewerDoc = await _db.collection('users').doc(reviewerId).get();
      reviewerName = reviewerDoc.data()?['name']?.toString().trim() ?? '';
    } catch (_) {}

    await _db.collection('reviews').doc(docId).set({
      'transactionId': transactionId,
      'reviewerId': reviewerId,
      'revieweeId': revieweeId,
      if (reviewerName.isNotEmpty) 'reviewerName': reviewerName,
      'rating': rating,
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Trigger trust score recalculation for the reviewee
    unawaited(TrustScoreService.instance.recalculateForUser(revieweeId));
  }

  /// Checks the write-once anonymous review document for this reviewer.
  static Future<bool> hasUserReviewed({
    required String transactionId,
    required String reviewerId,
  }) async {
    try {
      final docId = '${transactionId}_$reviewerId';
      final doc = await _db
          .collection('reviews')
          .doc(docId)
          .get()
          .timeout(const Duration(seconds: 5));
      return doc.exists;
    } catch (e) {
      debugPrint('ReviewService.hasUserReviewed error: $e');
      return false;
    }
  }

  static Future<String> getReviewerName(String reviewerId) async {
    if (reviewerId.isEmpty) return '';
    try {
      final doc = await _db
          .collection('users')
          .doc(reviewerId)
          .get()
          .timeout(const Duration(seconds: 5));
      return doc.data()?['name']?.toString().trim() ?? '';
    } catch (e) {
      debugPrint('ReviewService.getReviewerName error: $e');
      return '';
    }
  }

  /// Stream reviews for a specific user (reviewee), newest first.
  /// Used in SellerProfileScreen for real-time updates.
  static Stream<List<ReviewModel>> getReviewsForUser(String userId) {
    return _db
        .collection('reviews')
        .where('revieweeId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final reviews = snapshot.docs
              .map((doc) => ReviewModel.fromFirestore(doc))
              .toList();
          reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return reviews;
        });
  }

  /// One-time fetch of reviews for a specific user.
  /// Use when a stream is not needed.
  static Future<List<ReviewModel>> getReviewsForUserOnce(String userId) async {
    try {
      final snapshot = await _db
          .collection('reviews')
          .where('revieweeId', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 5));

      final reviews = snapshot.docs
          .map((doc) => ReviewModel.fromFirestore(doc))
          .toList();
      reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reviews;
    } catch (e) {
      debugPrint('ReviewService.getReviewsForUserOnce error: $e');
      return [];
    }
  }
}
