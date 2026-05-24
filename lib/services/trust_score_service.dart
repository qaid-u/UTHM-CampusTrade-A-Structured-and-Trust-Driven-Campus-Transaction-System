import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class TrustScoreService {
  TrustScoreService._();
  static final TrustScoreService instance = TrustScoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Recalculates and updates trust metrics for a specific user.
  ///
  /// New formula (60/20/20):
  /// - 60% Average rating score (rating / 5 * 60)
  /// - 20% Completed transaction score (min(completedTx, 50) / 50 * 20)
  /// - 20% Cancellation performance score ((totalTx - cancelledByUser) / totalTx * 20)
  ///
  /// If no transactions exist, cancellation score is 0 (no track record).
  Future<void> recalculateForUser(String userId) async {
    try {
      // Run all aggregation queries in parallel
      final results = await Future.wait([
        _aggregateRating(userId),
        _countCompletedTransactions(userId),
        _countTotalTransactions(userId),
        _countCancelledByUser(userId),
        _countTotalReviews(userId),
      ]);

      final double avgRating = results[0] as double;
      final int completedTx = results[1] as int;
      final int totalTx = results[2] as int;
      final int cancelledByUser = results[3] as int;
      final int totalReviews = results[4] as int;

      // New formula: 60/20/20 split
      final double ratingScore = (avgRating / 5.0) * 60.0;
      final double txScore =
          (completedTx.clamp(0, 50) / 50.0) * 20.0;
      final double cancellationScore = totalTx > 0
          ? ((totalTx - cancelledByUser) / totalTx) * 20.0
          : 0.0; // No transactions = no track record

      final double trustScore =
          (ratingScore + txScore + cancellationScore).clamp(0.0, 100.0);

      // Round to one decimal
      final double roundedScore =
          (trustScore * 10).roundToDouble() / 10;
      final double roundedAvgRating =
          (avgRating * 10).roundToDouble() / 10;

      // Batch update user document with all aggregated metrics
      final userRef = _firestore.collection('users').doc(userId);
      await userRef.update({
        'rating': roundedAvgRating,
        'completedTransactions': completedTx,
        'totalTransactions': totalTx,
        'cancelledTransactions': cancelledByUser,
        'totalReviews': totalReviews,
        'trustScore': roundedScore,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
        'TrustScore updated for user $userId: '
        'rating=$avgRating, completed=$completedTx, '
        'totalTx=$totalTx, cancelled=$cancelledByUser, '
        'reviews=$totalReviews, trustScore=$roundedScore',
      );
    } catch (e) {
      debugPrint('TrustScoreService.recalculateForUser error: $e');
    }
  }

  /// Aggregates average rating from all reviews received by this user.
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

  /// Counts total transactions where the user participated.
  Future<int> _countTotalTransactions(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('transactions')
          .where('participants', arrayContains: userId)
          .count()
          .get()
          .timeout(const Duration(seconds: 5));

      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('TrustScoreService._countTotalTransactions error: $e');
      return 0;
    }
  }

  /// Counts transactions cancelled BY this user (cancelledBy field matches userId).
  Future<int> _countCancelledByUser(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('transactions')
          .where('participants', arrayContains: userId)
          .where('status', isEqualTo: 'cancelled')
          .where('cancelledBy', isEqualTo: userId)
          .count()
          .get()
          .timeout(const Duration(seconds: 5));

      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('TrustScoreService._countCancelledByUser error: $e');
      return 0;
    }
  }

  /// Counts total reviews received by this user.
  Future<int> _countTotalReviews(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('revieweeId', isEqualTo: userId)
          .count()
          .get()
          .timeout(const Duration(seconds: 5));

      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('TrustScoreService._countTotalReviews error: $e');
      return 0;
    }
  }
}
