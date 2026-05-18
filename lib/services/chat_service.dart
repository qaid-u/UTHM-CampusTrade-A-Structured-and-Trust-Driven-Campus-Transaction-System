import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';

class ChatService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String generateRoomId({
    required String itemId,
    required String buyerId,
    required String sellerId,
  }) {
    final ids = [itemId, buyerId, sellerId];
    ids.sort();
    return ids.join('_');
  }

  static Future<String> getOrCreateRoom({
    required String itemId,
    required String itemTitle,
    required String itemThumbnail,
    required String buyerId,
    required String sellerId,
  }) async {
    final roomId = generateRoomId(
      itemId: itemId,
      buyerId: buyerId,
      sellerId: sellerId,
    );

    final ref = _db.collection('chatRooms').doc(roomId);

    final doc = await ref.get().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw Exception('Timeout fetching chat room info'),
    );
    if (!doc.exists) {
      final room = ChatRoomModel(
        roomId: roomId,
        itemId: itemId,
        itemTitle: itemTitle,
        itemThumbnail: itemThumbnail,
        buyerId: buyerId,
        sellerId: sellerId,
        participantIds: [buyerId, sellerId],
        lastMessage: 'Chat started',
        lastMessageType: 'system',
        updatedAt: DateTime.now(),
        unreadCounts: {buyerId: 0, sellerId: 0},
      );
      await ref.set(room.toFirestore(), SetOptions(merge: true));
    } else {
      // Update item title and thumbnail in case they changed
      await ref.update({
        'itemTitle': itemTitle,
        'itemThumbnail': itemThumbnail,
      });
    }

    return roomId;
  }

  static Future<void> sendMessage({
    required String roomId,
    required String senderId,
    required String text,
    String type = 'text',
    String? offerId,
    double? offerPrice,
    String? offerStatus,
    String? itemId,
  }) async {
    final msgRef = _db
        .collection('chatRooms')
        .doc(roomId)
        .collection('messages')
        .doc();

    final msg = MessageModel(
      id: msgRef.id,
      senderId: senderId,
      type: type,
      text: text,
      createdAt: DateTime.now(),
      offerId: offerId,
      offerPrice: offerPrice,
      offerStatus: offerStatus,
      itemId: itemId,
    );

    final batch = _db.batch();

    batch.set(msgRef, msg.toFirestore());

    final roomRef = _db.collection('chatRooms').doc(roomId);

    final updateData = {
      'lastMessage': text,
      'lastMessageType': type,
      'lastSenderId': senderId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (offerId != null) {
      updateData['latestOfferId'] = offerId;
    }

    batch.set(roomRef, updateData, SetOptions(merge: true));

    await batch.commit();
  }
}
