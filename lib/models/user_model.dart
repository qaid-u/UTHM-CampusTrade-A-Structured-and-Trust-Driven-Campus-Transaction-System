class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.studentId,
    required this.email,
    required this.phone,
    required this.password,
    this.trustScore = 50,
    this.completedTransactions = 0,
    this.rating = 4.5,
  });

  final String id;
  final String name;
  final String studentId;
  final String email;
  final String phone;
  final String password;
  final int trustScore;
  final int completedTransactions;
  final double rating;

  UserModel copyWith({
    String? id,
    String? name,
    String? studentId,
    String? email,
    String? phone,
    String? password,
    int? trustScore,
    int? completedTransactions,
    double? rating,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      studentId: studentId ?? this.studentId,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      password: password ?? this.password,
      trustScore: trustScore ?? this.trustScore,
      completedTransactions:
          completedTransactions ?? this.completedTransactions,
      rating: rating ?? this.rating,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'studentId': studentId,
    'email': email,
    'phone': phone,
    'password': password,
    'trustScore': trustScore,
    'completedTransactions': completedTransactions,
    'rating': rating,
  };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] as String,
    name: json['name'] as String,
    studentId: json['studentId'] as String,
    email: json['email'] as String,
    phone: json['phone'] as String,
    password: json['password'] as String,
    trustScore: json['trustScore'] as int? ?? 50,
    completedTransactions: json['completedTransactions'] as int? ?? 0,
    rating: (json['rating'] as num?)?.toDouble() ?? 4.5,
  );
}
