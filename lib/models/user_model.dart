import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String name;
  final String studentId;
  final String email;
  final String phone;
  final double trustScore;
  final int completedTransactions;
  final double rating;

  // Subscription fields
  final String subscriptionTier;
  final bool premiumActive;
  final DateTime? premiumStartDate;
  final DateTime? premiumExpiryDate;
  final int activeListingCount;

  const UserModel({
    required this.id,
    required this.name,
    required this.studentId,
    required this.email,
    required this.phone,
    required this.trustScore,
    required this.completedTransactions,
    required this.rating,
    this.subscriptionTier = 'free',
    this.premiumActive = false,
    this.premiumStartDate,
    this.premiumExpiryDate,
    this.activeListingCount = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      studentId: json['studentId'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      trustScore: (json['trustScore'] ?? 0).toDouble(),
      completedTransactions: json['completedTransactions'] ?? 0,
      rating: (json['rating'] ?? 0).toDouble(),
      subscriptionTier: json['subscriptionTier'] ?? 'free',
      premiumActive: json['premiumActive'] ?? false,
      premiumStartDate: _readDateTime(json['premiumStartDate']),
      premiumExpiryDate: _readDateTime(json['premiumExpiryDate']),
      activeListingCount: json['activeListingCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'studentId': studentId,
      'email': email,
      'phone': phone,
      'trustScore': trustScore,
      'completedTransactions': completedTransactions,
      'rating': rating,
      'subscriptionTier': subscriptionTier,
      'premiumActive': premiumActive,
      'premiumStartDate': premiumStartDate,
      'premiumExpiryDate': premiumExpiryDate,
      'activeListingCount': activeListingCount,
    };
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
