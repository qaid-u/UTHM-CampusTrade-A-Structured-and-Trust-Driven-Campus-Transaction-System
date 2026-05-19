import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionStatus {
  pending,
  accepted,
  rejected,
  payment_processing,
  completed,
  cancelled,
}

class TransactionModel {
  final String id;
  final String offerId;
  final String roomId;
  final String itemId;
  final String itemTitle;
  final String buyerId;
  final String sellerId;
  final double offerPrice;
  final double finalPrice;
  final double platformFee;
  final String paymentMethod;
  final String paymentReference;
  final String paymentStatus;
  final String paymentProofUrl;
  final String cancelReason;
  final String issueReason;
  final String issueStatus;
  final double buyerRating;
  final double sellerRating;
  final String buyerReview;
  final String sellerReview;
  final String meetupLocation;
  final double meetupLatitude;
  final double meetupLongitude;
  final TransactionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  TransactionModel({
    required this.id,
    this.offerId = '',
    this.roomId = '',
    required this.itemId,
    this.itemTitle = '',
    required this.buyerId,
    required this.sellerId,
    required this.offerPrice,
    required this.finalPrice,
    required this.platformFee,
    this.paymentMethod = '',
    this.paymentReference = '',
    this.paymentStatus = '',
    this.paymentProofUrl = '',
    this.cancelReason = '',
    this.issueReason = '',
    this.issueStatus = '',
    this.buyerRating = 0.0,
    this.sellerRating = 0.0,
    this.buyerReview = '',
    this.sellerReview = '',
    this.meetupLocation = '',
    this.meetupLatitude = 0.0,
    this.meetupLongitude = 0.0,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
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
      offerId: json['offerId'] ?? json['id'] ?? json['transactionId'] ?? '',
      roomId: json['roomId'] ?? '',
      itemId: json['itemId'] ?? '',
      itemTitle: json['itemTitle'] ?? '',
      buyerId: json['buyerId'] ?? '',
      sellerId: json['sellerId'] ?? '',
      offerPrice: offerPrice,
      finalPrice: finalPrice,
      platformFee: platformFee,
      paymentMethod: json['paymentMethod'] ?? '',
      paymentReference: json['paymentReference'] ?? '',
      paymentStatus: json['paymentStatus'] ?? '',
      paymentProofUrl: json['paymentProofUrl'] ?? '',
      cancelReason: json['cancelReason'] ?? '',
      issueReason: json['issueReason'] ?? '',
      issueStatus: json['issueStatus'] ?? '',
      buyerRating: _readDouble(json['buyerRating']),
      sellerRating: _readDouble(json['sellerRating']),
      buyerReview: json['buyerReview'] ?? '',
      sellerReview: json['sellerReview'] ?? '',
      meetupLocation: json['meetupLocation'] ?? '',
      meetupLatitude: _readDouble(json['meetupLatitude']),
      meetupLongitude: _readDouble(json['meetupLongitude']),
      status: TransactionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TransactionStatus.pending,
      ),
      createdAt: _readTimestamp(json['createdAt']),
      updatedAt: _readTimestamp(json['updatedAt']),
    );
  }

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return TransactionModel.fromJson({...data, 'id': doc.id});
  }

  Map<String, dynamic> toFirestore() {
    return {
      'transactionId': id,
      'offerId': offerId.isNotEmpty ? offerId : id,
      'roomId': roomId,
      'itemId': itemId,
      'itemTitle': itemTitle,
      'buyerId': buyerId,
      'sellerId': sellerId,
      'participants': [buyerId, sellerId],
      'offerPrice': offerPrice,
      'finalPrice': finalPrice,
      'platformFee': platformFee,
      'paymentMethod': paymentMethod,
      'paymentReference': paymentReference,
      'paymentStatus': paymentStatus,
      'paymentProofUrl': paymentProofUrl,
      'cancelReason': cancelReason,
      'issueReason': issueReason,
      'issueStatus': issueStatus,
      'buyerRating': buyerRating,
      'sellerRating': sellerRating,
      'buyerReview': buyerReview,
      'sellerReview': sellerReview,
      'meetupLocation': meetupLocation,
      'meetupLatitude': meetupLatitude,
      'meetupLongitude': meetupLongitude,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
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
