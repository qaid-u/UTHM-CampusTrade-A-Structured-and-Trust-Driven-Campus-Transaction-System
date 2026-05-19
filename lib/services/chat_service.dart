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
    if (buyerId == sellerId) {
      throw Exception('You cannot start a buyer chat for your own item');
    }

    final roomId = generateRoomId(
      itemId: itemId,
      buyerId: buyerId,
      sellerId: sellerId,
    );

    final ref = _db.collection('chatRooms').doc(roomId);

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

    await ref.set(room.toFirestore(), SetOptions(merge: true)).timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw Exception('Timeout creating chat room'),
    );

    return roomId;
  }

  static Future<void> sendMessage({
    required String roomId,
    required String senderId,
    required String text,
    String type = 'text',
    String mediaUrl = '',
    String? offerId,
    double? offerPrice,
    String? offerStatus,
    String? itemId,
  }) async {
    final roomRef = _db.collection('chatRooms').doc(roomId);
    final roomDoc = await roomRef.get();

    if (!roomDoc.exists) {
      throw Exception('Chat room not found');
    }

    final roomData = roomDoc.data() ?? {};
    final participants = List<String>.from(roomData['participantIds'] ?? []);
    final blockedBy = List<String>.from(roomData['blockedBy'] ?? []);

    if (!participants.contains(senderId)) {
      throw Exception('You are not allowed to send messages in this chat');
    }

    if (blockedBy.isNotEmpty) {
      throw Exception('This chat is blocked');
    }

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
      mediaUrl: mediaUrl,
      readBy: [senderId],
      deliveredTo: participants,
      createdAt: DateTime.now(),
      offerId: offerId,
      offerPrice: offerPrice,
      offerStatus: offerStatus,
      itemId: itemId,
    );

    final batch = _db.batch();

    batch.set(msgRef, msg.toFirestore());

    final updateData = <String, dynamic>{
      'lastMessage': text,
      'lastMessageType': type,
      'lastSenderId': senderId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    for (final participantId in participants) {
      if (participantId != senderId) {
        updateData['unreadCounts.$participantId'] = FieldValue.increment(1);
      }
    }

    if (offerId != null) {
      updateData['latestOfferId'] = offerId;
    }

    batch.set(roomRef, updateData, SetOptions(merge: true));

    await batch.commit();
  }

  static Future<void> sendImageMessage({
    required String roomId,
    required String senderId,
    required String imageUrl,
  }) {
    return sendMessage(
      roomId: roomId,
      senderId: senderId,
      type: 'image',
      text: 'Photo',
      mediaUrl: imageUrl,
    );
  }

  static Future<void> markRoomRead({
    required String roomId,
    required String userId,
  }) async {
    final roomRef = _db.collection('chatRooms').doc(roomId);
    final unreadMessages = await roomRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    final batch = _db.batch();
    for (final doc in unreadMessages.docs) {
      if (doc.data()['senderId'] == userId) continue;
      final readBy = List<String>.from(doc.data()['readBy'] ?? []);
      if (!readBy.contains(userId)) {
        batch.update(doc.reference, {
          'readBy': FieldValue.arrayUnion([userId]),
        });
      }
    }
    batch.set(roomRef, {'unreadCounts.$userId': 0}, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<void> setTyping({
    required String roomId,
    required String userId,
    required bool isTyping,
  }) {
    return _db.collection('chatRooms').doc(roomId).set({
      'typing.$userId': isTyping,
      'typingUpdatedAt.$userId': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> blockChat({
    required String roomId,
    required String userId,
  }) {
    return _db.collection('chatRooms').doc(roomId).set({
      'blockedBy': FieldValue.arrayUnion([userId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> reportChat({
    required String roomId,
    required String reporterId,
    required String reason,
  }) {
    return _db.collection('chatReports').add({
      'roomId': roomId,
      'reporterId': reporterId,
      'reason': reason.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
