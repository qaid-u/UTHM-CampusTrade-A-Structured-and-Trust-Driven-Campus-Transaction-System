import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String type; // 'text', 'offer', 'system'
  final String text;
  final DateTime createdAt;

  // Offer specific fields
  final String? offerId;
  final double? offerPrice;
  final String?
  offerStatus; // 'pending', 'accepted', 'rejected', 'countered', 'cancelled'
  final String? itemId;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.type,
    required this.text,
    required this.createdAt,
    this.offerId,
    this.offerPrice,
    this.offerStatus,
    this.itemId,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'senderId': senderId,
      'type': type,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      if (offerId != null) 'offerId': offerId,
      if (offerPrice != null) 'offerPrice': offerPrice,
      if (offerStatus != null) 'offerStatus': offerStatus,
      if (itemId != null) 'itemId': itemId,
    };
  }

  factory MessageModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MessageModel(
      id: data['id'] ?? doc.id,
      senderId: data['senderId'] ?? '',
      type: data['type'] ?? 'text',
      text: data['text'] ?? '',
      createdAt: _readTimestamp(data['createdAt']),
      offerId: data['offerId'],
      offerPrice: _readDouble(data['offerPrice']),
      offerStatus: data['offerStatus'],
      itemId: data['itemId'],
    );
  }

  static DateTime _readTimestamp(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  static double? _readDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
