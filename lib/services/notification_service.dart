import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/notification_model.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection('notifications');

  Stream<List<NotificationModel>> getUserNotifications(String userId) {
    return _notifications
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc))
              .toList(),
        );
  }

  Future<void> createNotification(NotificationModel notification) async {
    await _notifications.doc(notification.id).set(notification.toFirestore());
  }

  Future<void> notifyUser({
    required String userId,
    required String title,
    required String body,
    String? type, // 'message', 'offer', 'sale', etc.
    String? itemId,
    String? chatRoomId,
  }) async {
    final doc = _notifications.doc();

    await doc.set({
      'id': doc.id,
      'userId': userId,
      'title': title,
      'body': body,
      'type': type ?? 'message',
      'itemId': itemId,
      'chatRoomId': chatRoomId,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });

    debugPrint('Notification created for user $userId: $title - $body');

    // TODO: Add Firebase Cloud Messaging (FCM) push notification here
    // await _sendPushNotification(userId, title, body);
  }

  Future<void> markAsRead(String notificationId) async {
    await _notifications.doc(notificationId).update({'isRead': true});
  }

  /// Mark all notifications as read for a user
  Future<void> markAllAsRead(String userId) async {
    final snapshot = await _notifications
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
    debugPrint(
      'Marked ${snapshot.docs.length} notifications as read for user $userId',
    );
  }

  /// Mark message notifications as read when opening chat
  Future<void> markChatNotificationsAsRead({
    required String userId,
    required String chatRoomId,
  }) async {
    try {
      // Simplified query to avoid index issues
      final snapshot = await _notifications
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('Mark chat notifications timed out');
              throw Exception('Timeout marking notifications as read');
            },
          );

      if (snapshot.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      int markedCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Filter by chatRoomId in code instead of query
        if (data['chatRoomId'] == chatRoomId) {
          batch.update(doc.reference, {'isRead': true});
          markedCount++;
        }
      }

      if (markedCount > 0) {
        await batch.commit();
      }

      debugPrint('Marked $markedCount chat notifications as read');
    } catch (e) {
      debugPrint('Error in markChatNotificationsAsRead: $e');
      // Don't throw - this shouldn't break the app
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    await _notifications.doc(notificationId).delete();
  }

  /// Delete all notifications for a user
  Future<void> deleteAllNotifications(String userId) async {
    final snapshot = await _notifications
        .where('userId', isEqualTo: userId)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
    debugPrint(
      'Deleted ${snapshot.docs.length} notifications for user $userId',
    );
  }

  // TODO: Implement Firebase Cloud Messaging (FCM) for push notifications
  /*
  Future<void> _sendPushNotification(
    String userId, 
    String title, 
    String body
  ) async {
    // 1. Get user's FCM token from Firestore
    // 2. Send push notification using FCM HTTP API
    // 3. Handle delivery receipts
    
    // Example implementation:
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    
    final fcmToken = userDoc.data()?['fcmToken'];
    if (fcmToken == null) return;
    
    // Use Firebase Admin SDK or Cloud Functions to send push
    // This should be done server-side for security
  }
  */
}
