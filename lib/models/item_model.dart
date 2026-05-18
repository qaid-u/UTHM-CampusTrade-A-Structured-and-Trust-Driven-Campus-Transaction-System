import 'package:cloud_firestore/cloud_firestore.dart';

class ItemModel {
  final String id;
  final String sellerId;

  // Seller snapshot (embedded to avoid joins)
  final String sellerName;
  final String sellerImage;
  final String sellerStudentId;

  // Item data
  final String title;
  final String description;
  final double price;
  final String category;
  final String condition;
  final String meetupLocation;

  // Images (optimized)
  final String thumbnail; // First image for fast feed loading
  final List<String> images; // All images (max 4)

  // Metadata
  final String status; // available, sold, reserved
  final DateTime createdAt;
  final bool isFeatured;

  ItemModel({
    required this.id,
    required this.sellerId,
    this.sellerName = '',
    this.sellerImage = '',
    this.sellerStudentId = '',
    required this.title,
    this.description = '',
    required this.price,
    required this.category,
    this.condition = '',
    this.meetupLocation = '',
    this.thumbnail = '',
    this.images = const [],
    this.status = 'available',
    required this.createdAt,
    this.isFeatured = false,
  });

  factory ItemModel.fromJson(Map<String, dynamic> json) {
    final imagesList = json['images'] as List<dynamic>? ?? [];
    final images = imagesList.map((e) => e.toString()).toList();

    return ItemModel(
      id: json['id'] ?? json['itemId'] ?? '',
      sellerId: json['sellerId'] ?? '',
      sellerName: json['sellerName'] ?? '',
      sellerImage: json['sellerImage'] ?? '',
      sellerStudentId: json['sellerStudentId'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      price: _readDouble(json['price']),
      category: json['category'] ?? '',
      condition: json['condition'] ?? '',
      meetupLocation: json['meetupLocation'] ?? '',
      thumbnail: json['thumbnail'] ?? (images.isNotEmpty ? images.first : ''),
      images: images,
      status: json['status'] ?? 'available',
      createdAt: _readTimestamp(json['createdAt']),
      isFeatured: json['isFeatured'] ?? false,
    );
  }

  factory ItemModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ItemModel.fromJson({'id': doc.id, ...data});
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sellerId': sellerId,
      'sellerName': sellerName,
      'sellerImage': sellerImage,
      'sellerStudentId': sellerStudentId,
      'title': title,
      'description': description,
      'price': price,
      'category': category,
      'condition': condition,
      'meetupLocation': meetupLocation,
      'thumbnail': thumbnail,
      'images': images,
      'status': status,
      'createdAt': createdAt,
      'isFeatured': isFeatured,
    };
  }

  static DateTime _readTimestamp(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now(); // Fallback to current time instead of epoch
  }

  static double _readDouble(Object? value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
