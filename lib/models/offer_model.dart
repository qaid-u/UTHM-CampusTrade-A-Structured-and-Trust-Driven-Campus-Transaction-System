import 'package:cloud_firestore/cloud_firestore.dart';

class OfferModel {
  final String id;
  final String roomId;
  final String itemId;
  final String buyerId;
  final String sellerId;
  final double price;
  final String
  status; // 'pending', 'accepted', 'rejected', 'countered', 'cancelled'
  final DateTime createdAt;
  final DateTime updatedAt;

  const OfferModel({
    required this.id,
    required this.roomId,
    required this.itemId,
    required this.buyerId,
    required this.sellerId,
    required this.price,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'roomId': roomId,
      'itemId': itemId,
      'buyerId': buyerId,
      'sellerId': sellerId,
      'price': price,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory OfferModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return OfferModel(
      id: data['id'] ?? doc.id,
      roomId: data['roomId'] ?? '',
      itemId: data['itemId'] ?? '',
      buyerId: data['buyerId'] ?? '',
      sellerId: data['sellerId'] ?? '',
      price: _readDouble(data['price']),
      status: data['status'] ?? 'pending',
      createdAt: _readTimestamp(data['createdAt']),
      updatedAt: _readTimestamp(data['updatedAt']),
    );
  }

  static DateTime _readTimestamp(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  static double _readDouble(Object? value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
