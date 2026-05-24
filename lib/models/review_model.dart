import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewModel {
  final String id;
  final String transactionId;
  final String reviewerId;
  final String revieweeId;
  final int rating;
  final String comment;
  final DateTime createdAt;

  const ReviewModel({
    required this.id,
    required this.transactionId,
    required this.reviewerId,
    required this.revieweeId,
    required this.rating,
    this.comment = '',
    required this.createdAt,
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    return ReviewModel(
      id: json['id'] ?? '',
      transactionId: json['transactionId'] ?? '',
      reviewerId: json['reviewerId'] ?? '',
      revieweeId: json['revieweeId'] ?? '',
      rating: json['rating'] ?? 0,
      comment: json['comment'] ?? '',
      createdAt: _readTimestamp(json['createdAt']),
    );
  }

  factory ReviewModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ReviewModel.fromJson({'id': doc.id, ...data});
  }

  Map<String, dynamic> toFirestore() {
    return {
      'transactionId': transactionId,
      'reviewerId': reviewerId,
      'revieweeId': revieweeId,
      'rating': rating,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  static DateTime _readTimestamp(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}
