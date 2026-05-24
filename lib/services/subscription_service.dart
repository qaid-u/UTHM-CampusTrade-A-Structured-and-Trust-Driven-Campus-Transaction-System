import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// SINGLE source of truth for all premium/subscription logic.
///
/// Provides static methods that work with any user data map
/// (from Firestore doc), eliminating cached-state dependencies.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  final _db = FirebaseFirestore.instance;

  // ─────────────────────────────────────────────────────────
  // STATIC — Single source of truth functions
  // ─────────────────────────────────────────────────────────

  /// Check if a user has an active premium subscription.
  ///
  /// [userData] is the Firestore document data (map) for the user.
  /// Returns false if null or if subscription is free/expired.
  static bool isPremiumActive(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    final tier = userData['subscriptionTier'] ?? 'free';
    if (tier != 'premium') return false;

    // Check expiry date
    final expiryRaw = userData['premiumExpiryDate'];
    if (expiryRaw == null) return true; // No expiry = lifetime (demo)

    DateTime expiryDate;
    if (expiryRaw is Timestamp) {
      expiryDate = expiryRaw.toDate();
    } else if (expiryRaw is DateTime) {
      expiryDate = expiryRaw;
    } else {
      return true;
    }

    return expiryDate.isAfter(DateTime.now());
  }

  /// Check if a user can create a new listing.
  ///
  /// [userData] is the Firestore document data for the user.
  /// Free users are limited to 5 active listings.
  static Future<bool> canCreateListing(Map<String, dynamic>? userData) async {
    if (isPremiumActive(userData)) return true;

    final uid = userData?['uid'] ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      final count = await FirebaseFirestore.instance
          .collection('items')
          .where('sellerId', isEqualTo: uid)
          .where('status', isEqualTo: 'available')
          .count()
          .get()
          .timeout(const Duration(seconds: 5));

      return (count.count ?? 0) < 5;
    } catch (e) {
      debugPrint('[SubscriptionService] Error counting listings: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────
  // INSTANCE — Backward-compatible convenience methods
  // ─────────────────────────────────────────────────────────

  /// Initialize: fetch user doc and check auto-expiry.
  /// No longer starts a stream subscription — reduces complexity.
  Future<void> init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists) {
        await _checkAndExpire(doc.data()!);
      }
    } catch (e) {
      debugPrint('[SubscriptionService] Init error: $e');
    }
  }

  /// Check if premium has expired and revert to free if so.
  Future<void> _checkAndExpire(Map<String, dynamic> userData) async {
    final tier = userData['subscriptionTier'] ?? 'free';
    if (tier != 'premium') return;

    final expiryRaw = userData['premiumExpiryDate'];
    if (expiryRaw == null) return;

    DateTime expiryDate;
    if (expiryRaw is Timestamp) {
      expiryDate = expiryRaw.toDate();
    } else if (expiryRaw is DateTime) {
      expiryDate = expiryRaw;
    } else {
      return;
    }

    if (expiryDate.isBefore(DateTime.now())) {
      debugPrint('[SubscriptionService] Premium expired, reverting to free');
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _db.collection('users').doc(user.uid).update({
          'subscriptionTier': 'free',
          'premiumExpiryDate': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('[SubscriptionService] User downgraded to free');
      }
    }
  }

  /// Activate premium subscription (mocked payment flow).
  ///
  /// Sets subscriptionTier=premium, premiumExpiryDate=now+30d/+365d.
  Future<void> activatePremium({bool yearly = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final now = DateTime.now();
    final expiry =
        yearly ? now.add(const Duration(days: 365)) : now.add(const Duration(days: 30));

    await _db.collection('users').doc(user.uid).update({
      'subscriptionTier': 'premium',
      'premiumExpiryDate': Timestamp.fromDate(expiry),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('[SubscriptionService] Premium activated until $expiry');
  }

  /// Manually check and revert expired premium (called at startup/login).
  Future<void> checkExpiry() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists) await _checkAndExpire(doc.data()!);
    } catch (e) {
      debugPrint('[SubscriptionService] checkExpiry error: $e');
    }
  }

  /// Get the current user's subscription tier from Firestore.
  Future<String> getSubscriptionTier() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'free';
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      return doc.data()?['subscriptionTier'] ?? 'free';
    } catch (_) {
      return 'free';
    }
  }
}
