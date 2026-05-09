class ItemModel {
  const ItemModel({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.category,
    required this.description,
    required this.price,
    required this.condition,
    required this.imageLabel,
    required this.meetupLocation,
    required this.createdAt,
    this.isFeatured = false,
  });

  final String id;
  final String sellerId;
  final String title;
  final String category;
  final String description;
  final double price;
  final String condition;
  final String imageLabel;
  final String meetupLocation;
  final DateTime createdAt;
  final bool isFeatured;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sellerId': sellerId,
    'title': title,
    'category': category,
    'description': description,
    'price': price,
    'condition': condition,
    'imageLabel': imageLabel,
    'meetupLocation': meetupLocation,
    'createdAt': createdAt.toIso8601String(),
    'isFeatured': isFeatured,
  };

  factory ItemModel.fromJson(Map<String, dynamic> json) => ItemModel(
    id: json['id'] as String,
    sellerId: json['sellerId'] as String,
    title: json['title'] as String,
    category: json['category'] as String,
    description: json['description'] as String,
    price: (json['price'] as num).toDouble(),
    condition: json['condition'] as String,
    imageLabel: json['imageLabel'] as String? ?? 'Photo',
    meetupLocation: json['meetupLocation'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    isFeatured: json['isFeatured'] as bool? ?? false,
  );
}
