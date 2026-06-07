import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/notification_model.dart';
import 'fcm_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const allowedTypes = <String>{
    'message',
    'offer',
    'offer_accepted',
    'offer_rejected',
    'transaction_update',
    'receipt_uploaded',
    'payment_verified',
    'transaction_completed',
    'review_prompt',
    'premium',
    'system',
  };

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection('notifications');

  Stream<List<NotificationModel>> getUserNotifications(
    String userId, {
    int limit = 50,
  }) {
    return _notifications
        .where('userId', isEqualTo: userId)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Stream<int> unreadCountStream(String userId) {
    return _notifications
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  Future<void> createNotification(NotificationModel notification) async {
    final type = _normalizeType(notification.type);
    await _notifications
        .doc(notification.id)
        .set(
          NotificationModel(
            id: notification.id,
            userId: notification.userId,
            title: _cleanText(notification.title, fallback: 'Notification'),
            body: _cleanText(notification.body),
            type: type,
            relatedId: notification.relatedId,
            relatedType: notification.relatedType,
            route: notification.route,
            createdAt: notification.createdAt,
            isRead: notification.isRead,
          ).toFirestore(),
        );
  }

  Future<void> notifyUser({
    required String userId,
    required String title,
    required String body,
    String type = 'system',
    String relatedId = '',
    String relatedType = '',
    String route = '',
    String? itemId,
    String? chatRoomId,
    String? transactionId,
    String? notificationId,
    bool sendPush = true,
  }) async {
    if (userId.trim().isEmpty) return;

    final resolvedRelatedId = relatedId.isNotEmpty
        ? relatedId
        : chatRoomId?.isNotEmpty == true
        ? chatRoomId!
        : transactionId?.isNotEmpty == true
        ? transactionId!
        : itemId ?? '';
    final resolvedRoute = route.isNotEmpty
        ? route
        : chatRoomId?.isNotEmpty == true
        ? 'chat'
        : transactionId?.isNotEmpty == true
        ? 'transaction'
        : itemId?.isNotEmpty == true
        ? 'item'
        : '';
    final resolvedRelatedType = relatedType.isNotEmpty
        ? relatedType
        : chatRoomId?.isNotEmpty == true
        ? 'chatRoom'
        : transactionId?.isNotEmpty == true
        ? 'transaction'
        : itemId?.isNotEmpty == true
        ? 'item'
        : '';

    final doc = notificationId == null || notificationId.isEmpty
        ? _notifications.doc()
        : _notifications.doc(notificationId);
    final model = NotificationModel(
      id: doc.id,
      userId: userId,
      title: _cleanText(title, fallback: 'Notification'),
      body: _cleanText(body),
      type: _normalizeType(type),
      relatedId: resolvedRelatedId,
      relatedType: resolvedRelatedType,
      route: resolvedRoute,
      createdAt: DateTime.now(),
      isRead: false,
    );

    try {
      await createNotification(model);
      debugPrint('Notification created for user $userId: ${model.title}');
    } catch (e) {
      debugPrint('Notification Firestore write failed: $e');
      return;
    }

    if (!sendPush) return;

    unawaited(
      FCMService.instance.sendPush(
        userId: userId,
        title: model.title,
        body: model.body,
        data: {
          'notificationId': model.id,
          'type': model.type,
          'relatedId': model.relatedId,
          'relatedType': model.relatedType,
          'route': model.route,
        },
      ),
    );
  }

  Future<void> notifyMultipleUsers({
    required Iterable<String> userIds,
    required String title,
    required String body,
    String type = 'system',
    String relatedId = '',
    String relatedType = '',
    String route = '',
    String? itemId,
    String? chatRoomId,
    String? transactionId,
    String? excludeUserId,
  }) async {
    final uniqueIds = userIds
        .where((id) => id.trim().isNotEmpty && id != excludeUserId)
        .toSet();
    for (final userId in uniqueIds) {
      unawaited(
        notifyUser(
          userId: userId,
          title: title,
          body: body,
          type: type,
          relatedId: relatedId,
          relatedType: relatedType,
          route: route,
          itemId: itemId,
          chatRoomId: chatRoomId,
          transactionId: transactionId,
        ),
      );
    }
  }

  Future<void> markAsRead(String notificationId) async {
    if (notificationId.isEmpty) return;
    await _notifications.doc(notificationId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllAsRead(String userId) async {
    final snapshot = await _notifications
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .limit(100)
        .get();

    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> markChatNotificationsAsRead({
    required String userId,
    required String chatRoomId,
  }) async {
    try {
      final snapshot = await _notifications
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .limit(100)
          .get()
          .timeout(const Duration(seconds: 5));

      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      var markedCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final relatedId = data['relatedId'] ?? data['chatRoomId'];
        final route = data['route'];
        final type = data['type'];
        if (relatedId == chatRoomId ||
            (route == 'chat' && relatedId == chatRoomId) ||
            (relatedId == null && (type == 'message' || type == 'offer'))) {
          batch.update(doc.reference, {
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
          });
          markedCount++;
        }
      }

      if (markedCount > 0) await batch.commit();
    } catch (e) {
      debugPrint('Error in markChatNotificationsAsRead: $e');
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    if (notificationId.isEmpty) return;
    await _notifications.doc(notificationId).delete();
  }

  Future<void> deleteAllNotifications(String userId) async {
    final snapshot = await _notifications
        .where('userId', isEqualTo: userId)
        .limit(100)
        .get();

    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  String _normalizeType(String type) {
    return allowedTypes.contains(type) ? type : 'system';
  }

  String _cleanText(String value, {String fallback = ''}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return fallback;
    return trimmed.length > 180 ? '${trimmed.substring(0, 177)}...' : trimmed;
  }
}
