import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/offer_model.dart';
import 'chat_service.dart';
import 'transaction_service.dart';

class OfferService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> createOffer({
    required String roomId,
    required String itemId,
    required String itemTitle,
    required String buyerId,
    required String sellerId,
    required double price,
  }) async {
    if (buyerId == sellerId) {
      throw Exception('You cannot make an offer on your own item');
    }

    if (price <= 0) {
      throw Exception('Offer price must be greater than 0');
    }

    final itemRef = _db.collection('items').doc(itemId);
    final itemDoc = await itemRef.get();

    if (!itemDoc.exists) {
      throw Exception('Item not found');
    }

    final itemData = itemDoc.data() ?? {};
    final actualSellerId = itemData['sellerId']?.toString() ?? '';
    final itemStatus = itemData['status']?.toString() ?? 'available';

    if (actualSellerId != sellerId) {
      throw Exception('Seller information is no longer valid');
    }

    if (itemStatus != 'available') {
      throw Exception('This item is no longer accepting offers');
    }

    final existingOffers = await _db
        .collection('offers')
        .where('buyerId', isEqualTo: buyerId)
        .get();

    final hasPendingOffer = existingOffers.docs.any((doc) {
      final data = doc.data();
      return data['itemId'] == itemId && data['status'] == 'pending';
    });

    if (hasPendingOffer) {
      throw Exception('You already have a pending offer for this item');
    }

    final roomDoc = await _db.collection('chatRooms').doc(roomId).get();
    if (!roomDoc.exists) {
      throw Exception('Chat room not found');
    }

    final roomData = roomDoc.data() ?? {};
    final participants = List<String>.from(roomData['participantIds'] ?? []);
    if (!participants.contains(buyerId) || !participants.contains(sellerId)) {
      throw Exception('Invalid chat participants for this offer');
    }

    final offerRef = _db.collection('offers').doc();

    final offer = OfferModel(
      id: offerRef.id,
      roomId: roomId,
      itemId: itemId,
      buyerId: buyerId,
      sellerId: sellerId,
      createdBy: buyerId,
      price: price,
      status: 'pending',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final batch = _db.batch();
    batch.set(offerRef, offer.toFirestore());

    await batch.commit();

    await ChatService.sendMessage(
      roomId: roomId,
      senderId: buyerId,
      type: 'offer',
      text: 'RM ${price.toStringAsFixed(2)}',
      offerId: offerRef.id,
      offerPrice: price,
      offerStatus: 'pending',
      itemId: itemId,
    );
  }

  static Future<void> updateOfferStatus({
    required String offerId,
    required String roomId,
    required String status, // 'accepted', 'rejected', 'countered', 'cancelled'
    required String actionUserId,
  }) async {
    if (!['accepted', 'rejected', 'cancelled', 'countered'].contains(status)) {
      throw Exception('Unsupported offer status');
    }

    if (status == 'accepted') {
      // Delegate to TransactionService to ensure atomic execution and single transaction mapping
      await TransactionService.acceptOfferAndCreateTransaction(
        offerId: offerId,
        roomId: roomId,
        actionUserId: actionUserId,
      );
      return;
    }

    final offerRef = _db.collection('offers').doc(offerId);

    final offerDoc = await offerRef.get().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw Exception('Timeout fetching offer details'),
    );
    if (!offerDoc.exists) return;

    final offerData = offerDoc.data() ?? {};
    final sellerId = offerData['sellerId']?.toString() ?? '';
    final buyerId = offerData['buyerId']?.toString() ?? '';
    final createdBy = offerData['createdBy']?.toString() ?? buyerId;
    final currentStatus = offerData['status']?.toString() ?? 'pending';
    final recipientId = createdBy == sellerId ? buyerId : sellerId;

    if (currentStatus != 'pending') {
      throw Exception('This offer has already been $currentStatus');
    }

    if (status == 'rejected' && actionUserId != recipientId) {
      throw Exception('Only the offer recipient can reject this offer');
    }

    if (status == 'countered' && actionUserId != sellerId) {
      throw Exception('Only the seller can counter this offer');
    }

    if (status == 'cancelled' && actionUserId != createdBy) {
      throw Exception('Only the offer sender can cancel this offer');
    }

    final batch = _db.batch();

    batch.update(offerRef, {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update the message associated with this offer in chat
    final msgs = await _db
        .collection('chatRooms')
        .doc(roomId)
        .collection('messages')
        .where('offerId', isEqualTo: offerId)
        .limit(1)
        .get()
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw Exception('Timeout fetching offer message'),
        );

    if (msgs.docs.isNotEmpty) {
      batch.update(msgs.docs.first.reference, {'offerStatus': status});
    }

    await batch.commit();

    String systemText = '';
    switch (status) {
      case 'rejected':
        systemText = 'Offer rejected';
        break;
      case 'cancelled':
        systemText = 'Offer cancelled';
        break;
      case 'countered':
        systemText = 'Seller sent a counter offer';
        break;
      default:
        systemText = 'Offer updated';
    }

    await ChatService.sendMessage(
      roomId: roomId,
      senderId: actionUserId,
      type: 'system',
      text: systemText,
    );
  }

  static Future<void> counterOffer({
    required String offerId,
    required String roomId,
    required String actionUserId,
    required double counterPrice,
  }) async {
    if (counterPrice <= 0) {
      throw Exception('Counter offer must be greater than 0');
    }

    final originalRef = _db.collection('offers').doc(offerId);
    final originalDoc = await originalRef.get();
    if (!originalDoc.exists) {
      throw Exception('Offer not found');
    }

    final data = originalDoc.data() ?? {};
    final sellerId = data['sellerId']?.toString() ?? '';
    final buyerId = data['buyerId']?.toString() ?? '';
    final itemId = data['itemId']?.toString() ?? '';
    if (actionUserId != sellerId) {
      throw Exception('Only the seller can counter this offer');
    }

    await updateOfferStatus(
      offerId: offerId,
      roomId: roomId,
      status: 'countered',
      actionUserId: actionUserId,
    );

    final counterRef = _db.collection('offers').doc();
    final now = DateTime.now();
    final counter = OfferModel(
      id: counterRef.id,
      roomId: roomId,
      itemId: itemId,
      buyerId: buyerId,
      sellerId: sellerId,
      createdBy: sellerId,
      price: counterPrice,
      status: 'pending',
      createdAt: now,
      updatedAt: now,
    );

    await counterRef.set(counter.toFirestore());

    await ChatService.sendMessage(
      roomId: roomId,
      senderId: actionUserId,
      type: 'offer',
      text: 'RM ${counterPrice.toStringAsFixed(2)}',
      offerId: counterRef.id,
      offerPrice: counterPrice,
      offerStatus: 'pending',
      itemId: itemId,
    );
  }
}
