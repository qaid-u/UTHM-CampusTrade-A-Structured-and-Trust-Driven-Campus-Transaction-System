import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class TrustScoreService {
  TrustScoreService._();
  static final TrustScoreService instance = TrustScoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Recalculates and updates trust metrics for a specific user.
  /// Called when:
  /// - A transaction is completed
  /// - A review is submitted
  ///
  /// This avoids expensive full-database scans by only touching the affected user.
  Future<void> recalculateForUser(String userId) async {
    try {
      // Run rating and completed-transaction queries in parallel
      final results = await Future.wait([
        _aggregateRating(userId),
        _countCompletedTransactions(userId),
      ]);

      final double avgRating = results[0] as double;
      final int completedTx = results[1] as int;

      // Calculate trust score
      // Formula: (rating / 5 * 70) + (min(completed,50) / 50 * 30)
      final double ratingComponent = (avgRating / 5.0) * 70.0;
      final double txComponent =
          (completedTx.clamp(0, 50) / 50.0) * 30.0;
      final double trustScore =
          (ratingComponent + txComponent).clamp(0.0, 100.0);

      // Round to one decimal
      final double roundedScore =
          (trustScore * 10).roundToDouble() / 10;

      // Batch update user document with all three metrics atomically
      final userRef = _firestore.collection('users').doc(userId);
      await userRef.update({
        'rating': (avgRating * 10).roundToDouble() / 10,
        'completedTransactions': completedTx,
        'trustScore': roundedScore,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
        'TrustScore updated for user $userId: '
        'rating=$avgRating, transactions=$completedTx, trustScore=$roundedScore',
      );
    } catch (e) {
      debugPrint('TrustScoreService.recalculateForUser error: $e');
    }
  }

  /// Aggregates average rating from all reviews received by this user.
  /// Returns 0.0 if no reviews exist.
  Future<double> _aggregateRating(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('revieweeId', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 5));

      if (snapshot.docs.isEmpty) return 0.0;

      double sum = 0;
      for (final doc in snapshot.docs) {
        final rating = (doc.data()['rating'] ?? 0).toDouble();
        sum += rating;
      }

      return sum / snapshot.docs.length;
    } catch (e) {
      debugPrint('TrustScoreService._aggregateRating error: $e');
      return 0.0;
    }
  }

  /// Counts completed transactions where the user participated.
  Future<int> _countCompletedTransactions(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('transactions')
          .where('participants', arrayContains: userId)
          .where('status', isEqualTo: 'completed')
          .count()
          .get()
          .timeout(const Duration(seconds: 5));

      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('TrustScoreService._countCompletedTransactions error: $e');
      return 0;
    }
  }
}
