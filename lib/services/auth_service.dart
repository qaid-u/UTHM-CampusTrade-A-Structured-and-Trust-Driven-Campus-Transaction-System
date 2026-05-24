import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_defaults.dart';
import 'fcm_service.dart';
import 'subscription_service.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String _emailFromStudentId(String studentId) {
    return '$studentId@student.uthm.edu.my';
  }

  Future<String?> register({
    required String name,
    required String studentId,
    required String phone,
    required String password,
  }) async {
    try {
      final email = _emailFromStudentId(studentId);

      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user!.uid;

      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'studentId': studentId,
        'phone': phone,
        'email': email,
        'bio': '',
        'profileImage': AppDefaults.defaultProfileImage,
        'fcmToken': await FCMService.instance.getToken() ?? '',
        'trustScore': 0.0,
        'completedTransactions': 0,
        'rating': 0.0,
        'subscriptionTier': 'free',
        'activeListingCount': 0,
        'totalTransactions': 0,
        'cancelledTransactions': 0,
        'totalReviews': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> login({
    required String studentId,
    required String password,
  }) async {
    try {
      final email = _emailFromStudentId(studentId);

      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _ensureUserDoc(cred.user!);

      // Check subscription expiry after login.
      try {
        await SubscriptionService.instance.checkExpiry();
      } catch (_) {}

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> _ensureUserDoc(User user) async {
    final ref = _db.collection('users').doc(user.uid);
    final doc = await ref.get();

    if (!doc.exists) {
      await ref.set({
        'uid': user.uid,
        'name': 'New User',
        'studentId': '',
        'phone': '',
        'email': user.email ?? '',
        'bio': '',
        'profileImage': AppDefaults.defaultProfileImage,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.set({
        'profileImage': doc['profileImage'] ?? AppDefaults.defaultProfileImage,
        'bio': doc['bio'] ?? '',
        'fcmToken': await FCMService.instance.getToken() ?? '',
      }, SetOptions(merge: true));
    }
  }

  Future<void> logout() async {
    final user = _auth.currentUser;
    if (user != null) {
      await FCMService.instance.removeToken(user.uid);
    }
    await _auth.signOut();
  }
}
