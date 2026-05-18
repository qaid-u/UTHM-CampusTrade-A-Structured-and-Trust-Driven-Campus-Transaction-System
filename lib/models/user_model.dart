class UserModel {
  final String id;
  final String name;
  final String studentId;
  final String email;
  final String phone;
  final double trustScore;
  final int completedTransactions;
  final double rating;

  const UserModel({
    required this.id,
    required this.name,
    required this.studentId,
    required this.email,
    required this.phone,
    required this.trustScore,
    required this.completedTransactions,
    required this.rating,
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
    };
  }
}
