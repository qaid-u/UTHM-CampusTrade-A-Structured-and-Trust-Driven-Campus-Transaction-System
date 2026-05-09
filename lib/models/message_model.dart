class MessageModel {
  const MessageModel({
    required this.id,
    required this.itemId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.sentAt,
  });

  final String id;
  final String itemId;
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime sentAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'itemId': itemId,
    'senderId': senderId,
    'receiverId': receiverId,
    'text': text,
    'sentAt': sentAt.toIso8601String(),
  };

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
    id: json['id'] as String,
    itemId: json['itemId'] as String,
    senderId: json['senderId'] as String,
    receiverId: json['receiverId'] as String,
    text: json['text'] as String,
    sentAt: DateTime.parse(json['sentAt'] as String),
  );
}
