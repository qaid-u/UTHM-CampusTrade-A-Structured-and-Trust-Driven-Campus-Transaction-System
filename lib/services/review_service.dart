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

    await _db.collection('reviews').doc(docId).set({
      'transactionId': transactionId,
      'reviewerId': reviewerId,
      'revieweeId': revieweeId,
      'rating': rating,
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Trigger trust score recalculation for the reviewee
    unawaited(TrustScoreService.instance.recalculateForUser(revieweeId));
  }

  /// Stream reviews for a specific user (reviewee), newest first.
  /// Used in SellerProfileScreen for real-time updates.
  static Stream<List<ReviewModel>> getReviewsForUser(String userId) {
    return _db
        .collection('reviews')
        .where('revieweeId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ReviewModel.fromFirestore(doc))
          .toList();
    });
  }

  /// One-time fetch of reviews for a specific user.
  /// Use when a stream is not needed.
  static Future<List<ReviewModel>> getReviewsForUserOnce(
    String userId,
  ) async {
    try {
      final snapshot = await _db
          .collection('reviews')
          .where('revieweeId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 5));

      return snapshot.docs
          .map((doc) => ReviewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('ReviewService.getReviewsForUserOnce error: $e');
      return [];
    }
  }
}
