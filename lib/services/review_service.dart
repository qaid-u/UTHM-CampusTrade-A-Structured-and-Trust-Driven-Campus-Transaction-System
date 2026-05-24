import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

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
      // The backend/Cloud Function will scan this collection to update aggregate trustScores securely
    });

    // Trigger trust score recalculation for the reviewee
    unawaited(TrustScoreService.instance.recalculateForUser(revieweeId));
  }
}
