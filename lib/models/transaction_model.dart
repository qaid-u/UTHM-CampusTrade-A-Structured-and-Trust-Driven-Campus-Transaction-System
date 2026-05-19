import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionStatus {
  pending_offer,
  accepted,
  rejected,
  meetup_pending,
  completed,
  cancelled,
}

class TransactionModel {
  final String id;
  final String itemId;
  final String itemTitle;
  final String buyerId;
  final String sellerId;
  final double offerPrice;
  final double finalPrice;
  final double platformFee;
  final String meetupLocation;
  final double meetupLatitude;
  final double meetupLongitude;
  final TransactionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // New fields for complete transaction engine
  final bool buyerMeetupConfirmed;
  final bool sellerMeetupConfirmed;
  final bool receiptUploaded;
  final bool paymentVerified;
  final DateTime? verifiedAt;
  final String? receiptUrl;
  final String? cancelledBy;
  final String? cancelledReason;
  final DateTime? completedAt;

  TransactionModel({
    required this.id,
    required this.itemId,
    this.itemTitle = '',
    required this.buyerId,
    required this.sellerId,
    required this.offerPrice,
    required this.finalPrice,
    required this.platformFee,
    this.meetupLocation = '',
    this.meetupLatitude = 0.0,
    this.meetupLongitude = 0.0,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.buyerMeetupConfirmed = false,
    this.sellerMeetupConfirmed = false,
    this.receiptUploaded = false,
    this.paymentVerified = false,
    this.verifiedAt,
    this.receiptUrl,
    this.cancelledBy,
    this.cancelledReason,
    this.completedAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    final double offerPrice = _readDouble(json['offerPrice']);
    final double finalPrice = json['finalPrice'] != null
        ? _readDouble(json['finalPrice'])
        : offerPrice;
    final double platformFee = json['platformFee'] != null
        ? _readDouble(json['platformFee'])
        : (finalPrice * 0.05);

    return TransactionModel(
      id: json['id'] ?? json['transactionId'] ?? '',
      itemId: json['itemId'] ?? '',
      itemTitle: json['itemTitle'] ?? '',
      buyerId: json['buyerId'] ?? '',
      sellerId: json['sellerId'] ?? '',
      offerPrice: offerPrice,
      finalPrice: finalPrice,
      platformFee: platformFee,
      meetupLocation: json['meetupLocation'] ?? '',
      meetupLatitude: _readDouble(json['meetupLatitude']),
      meetupLongitude: _readDouble(json['meetupLongitude']),
      status: TransactionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TransactionStatus.pending_offer,
      ),
      createdAt: _readTimestamp(json['createdAt']),
      updatedAt: _readTimestamp(json['updatedAt']),
      buyerMeetupConfirmed: json['buyerMeetupConfirmed'] ?? false,
      sellerMeetupConfirmed: json['sellerMeetupConfirmed'] ?? false,
      receiptUploaded: json['receiptUploaded'] ?? false,
      paymentVerified: json['paymentVerified'] ?? false,
      verifiedAt: json['verifiedAt'] != null ? _readTimestamp(json['verifiedAt']) : null,
      receiptUrl: json['receiptUrl'],
      cancelledBy: json['cancelledBy'],
      cancelledReason: json['cancelledReason'],
      completedAt: json['completedAt'] != null ? _readTimestamp(json['completedAt']) : null,
    );
  }

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return TransactionModel.fromJson({...data, 'id': doc.id});
  }

  Map<String, dynamic> toFirestore() {
    return {
      'transactionId': id,
      'itemId': itemId,
      'itemTitle': itemTitle,
      'buyerId': buyerId,
      'sellerId': sellerId,
      'participants': [buyerId, sellerId],
      'offerPrice': offerPrice,
      'finalPrice': finalPrice,
      'platformFee': platformFee,
      'meetupLocation': meetupLocation,
      'meetupLatitude': meetupLatitude,
      'meetupLongitude': meetupLongitude,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'buyerMeetupConfirmed': buyerMeetupConfirmed,
      'sellerMeetupConfirmed': sellerMeetupConfirmed,
      'receiptUploaded': receiptUploaded,
      'paymentVerified': paymentVerified,
      if (verifiedAt != null) 'verifiedAt': Timestamp.fromDate(verifiedAt!),
      if (receiptUrl != null) 'receiptUrl': receiptUrl,
      if (cancelledBy != null) 'cancelledBy': cancelledBy,
      if (cancelledReason != null) 'cancelledReason': cancelledReason,
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
    };
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
