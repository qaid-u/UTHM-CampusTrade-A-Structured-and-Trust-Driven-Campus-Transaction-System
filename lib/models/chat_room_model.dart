import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoomModel {
  final String roomId;
  final String itemId;
  final String itemTitle;
  final String itemThumbnail;
  final String buyerId;
  final String sellerId;
  final List<String> participantIds;
  final String lastMessage;
  final String lastMessageType;
  final DateTime updatedAt;
  final Map<String, int> unreadCounts;
  final String? latestOfferId;

  const ChatRoomModel({
    required this.roomId,
    required this.itemId,
    required this.itemTitle,
    required this.itemThumbnail,
    required this.buyerId,
    required this.sellerId,
    required this.participantIds,
    required this.lastMessage,
    required this.lastMessageType,
    required this.updatedAt,
    required this.unreadCounts,
    this.latestOfferId,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'roomId': roomId,
      'itemId': itemId,
      'itemTitle': itemTitle,
      'itemThumbnail': itemThumbnail,
      'buyerId': buyerId,
      'sellerId': sellerId,
      'participantIds': participantIds,
      'lastMessage': lastMessage,
      'lastMessageType': lastMessageType,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'unreadCounts': unreadCounts,
      if (latestOfferId != null) 'latestOfferId': latestOfferId,
    };
  }

  factory ChatRoomModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ChatRoomModel(
      roomId: data['roomId'] ?? doc.id,
      itemId: data['itemId'] ?? '',
      itemTitle: data['itemTitle'] ?? '',
      itemThumbnail: data['itemThumbnail'] ?? '',
      buyerId: data['buyerId'] ?? '',
      sellerId: data['sellerId'] ?? '',
      participantIds: List<String>.from(data['participantIds'] ?? []),
      lastMessage: data['lastMessage'] ?? '',
      lastMessageType: data['lastMessageType'] ?? 'text',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      unreadCounts: Map<String, int>.from(data['unreadCounts'] ?? {}),
      latestOfferId: data['latestOfferId'],
    );
  }
}
