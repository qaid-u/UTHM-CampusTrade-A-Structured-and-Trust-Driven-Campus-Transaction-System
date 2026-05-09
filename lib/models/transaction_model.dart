enum TransactionStatus { pending, accepted, rejected, completed }

class TransactionModel {
  const TransactionModel({
    required this.id,
    required this.itemId,
    required this.buyerId,
    required this.sellerId,
    required this.offerPrice,
    required this.status,
    required this.meetupLocation,
    required this.createdAt,
  });

  final String id;
  final String itemId;
  final String buyerId;
  final String sellerId;
  final double offerPrice;
  final TransactionStatus status;
  final String meetupLocation;
  final DateTime createdAt;

  TransactionModel copyWith({TransactionStatus? status}) => TransactionModel(
    id: id,
    itemId: itemId,
    buyerId: buyerId,
    sellerId: sellerId,
    offerPrice: offerPrice,
    status: status ?? this.status,
    meetupLocation: meetupLocation,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'itemId': itemId,
    'buyerId': buyerId,
    'sellerId': sellerId,
    'offerPrice': offerPrice,
    'status': status.name,
    'meetupLocation': meetupLocation,
    'createdAt': createdAt.toIso8601String(),
  };

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      itemId: json['itemId'] as String,
      buyerId: json['buyerId'] as String,
      sellerId: json['sellerId'] as String,
      offerPrice: (json['offerPrice'] as num).toDouble(),
      status: TransactionStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => TransactionStatus.pending,
      ),
      meetupLocation: json['meetupLocation'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
