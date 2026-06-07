import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.relatedId = '',
    this.relatedType = '',
    this.route = '',
    this.isRead = false,
  });

  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final String relatedId;
  final String relatedType;
  final String route;
  final DateTime createdAt;
  final bool isRead;

  Map<String, dynamic> toFirestore() {
    return {
      'notificationId': id,
      'id': id,
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      'relatedId': relatedId,
      'relatedType': relatedType,
      'route': route,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
    };
  }

  factory NotificationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final json = doc.data() ?? {};
    final legacyRelatedId =
        json['relatedId'] ?? json['chatRoomId'] ?? json['itemId'] ?? '';
    final legacyRoute =
        json['route'] ??
        (json['chatRoomId'] != null
            ? 'chat'
            : json['itemId'] != null
            ? 'item'
            : '');

    return NotificationModel(
      id: (json['notificationId'] ?? json['id'] ?? doc.id).toString(),
      userId: (json['userId'] ?? '').toString(),
      title: (json['title'] ?? 'Notification').toString(),
      body: (json['body'] ?? '').toString(),
      type: (json['type'] ?? 'system').toString(),
      relatedId: legacyRelatedId.toString(),
      relatedType: (json['relatedType'] ?? '').toString(),
      route: legacyRoute.toString(),
      createdAt: _readTimestamp(json['createdAt']),
      isRead: json['isRead'] == true,
    );
  }

  static DateTime _readTimestamp(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}
