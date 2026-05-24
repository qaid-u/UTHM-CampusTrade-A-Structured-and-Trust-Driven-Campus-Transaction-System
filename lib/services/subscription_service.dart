import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Manages user subscription tiers, listing limits, and auto-expiry.
///
/// Caches subscription data from the user's Firestore document and
/// reacts to changes in realtime via a StreamSubscription.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  final _db = FirebaseFirestore.instance;

  // Cached subscription data from the user document.
  Map<String, dynamic>? _cachedData;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  /// Whether the current user has an active premium subscription.
  bool get isPremium => _cachedData?['subscriptionTier'] == 'premium' &&
      _cachedData?['premiumActive'] == true;

  /// The cached user data map (contains all user fields).
  Map<String, dynamic>? get cachedData => _cachedData;

  /// Initialize: check auto-expiry and start listening to user doc changes.
  Future<void> init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = _db.collection('users').doc(user.uid);

    // Fetch once to check for expired premium.
    final doc = await ref.get();
    if (doc.exists) {
      _cachedData = doc.data();
      await _checkAndExpire();
    }

    // Listen for realtime updates.
    _userSub?.cancel();
    _userSub = ref.snapshots().listen((snapshot) {
      if (snapshot.exists) {
        _cachedData = snapshot.data();
        debugPrint(
          '[SubscriptionService] Cache updated: tier=${_cachedData?['subscriptionTier']}',
        );
      }
    }, onError: (e) {
      debugPrint('[SubscriptionService] Stream error: $e');
    });
  }

  /// Dispose the listener when no longer needed.
  void dispose() {
    _userSub?.cancel();
    _userSub = null;
    _cachedData = null;
  }

  /// Check if premium has expired and revert to free if so.
  Future<void> _checkAndExpire() async {
    if (_cachedData == null) return;

    final tier = _cachedData!['subscriptionTier'];
    final active = _cachedData!['premiumActive'] == true;
    final expiryRaw = _cachedData!['premiumExpiryDate'];

    if (tier == 'premium' && active && expiryRaw != null) {
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
            'premiumActive': false,
            'premiumExpiryDate': FieldValue.delete(),
            'premiumStartDate': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          // Cache will update via the stream listener.
        }
      }
    }
  }

  /// Count active (available) listings for the current user.
  Future<int> activeListingCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    try {
      final snapshot = await _db
          .collection('items')
          .where('sellerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'available')
          .count()
          .get()
          .timeout(const Duration(seconds: 5));

      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('[SubscriptionService] Error counting listings: $e');
      return 0;
    }
  }

  /// Check if the user can create a new listing.
  ///
  /// Returns true if premium or if active listing count < 5.
  Future<bool> canCreateListing() async {
    // Premium users have unlimited listings.
    if (isPremium) return true;

    final count = await activeListingCount();
    return count < 5;
  }

  /// Activate premium subscription (mocked payment flow).
  ///
  /// Sets subscriptionTier=premium, premiumActive=true,
  /// premiumStartDate=now, premiumExpiryDate=now+30days.
  Future<void> activatePremium({bool yearly = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final now = DateTime.now();
    final expiry = yearly ? now.add(const Duration(days: 365)) : now.add(const Duration(days: 30));

    await _db.collection('users').doc(user.uid).update({
      'subscriptionTier': 'premium',
      'premiumActive': true,
      'premiumStartDate': Timestamp.fromDate(now),
      'premiumExpiryDate': Timestamp.fromDate(expiry),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint(
      '[SubscriptionService] Premium activated until $expiry',
    );
  }

  /// Manually check and revert expired premium (called at startup/login).
  Future<void> checkExpiry() async {
    await _checkAndExpire();
  }

  /// Get the premium expiry date from cache.
  DateTime? get premiumExpiryDate {
    final raw = _cachedData?['premiumExpiryDate'];
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  /// Get the subscription tier from cache.
  String get subscriptionTier =>
      _cachedData?['subscriptionTier'] ?? 'free';
}
