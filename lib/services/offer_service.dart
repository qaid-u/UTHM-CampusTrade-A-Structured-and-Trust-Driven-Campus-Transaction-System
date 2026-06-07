import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/offer_model.dart';
import 'chat_service.dart';
import 'notification_service.dart';
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
    final itemDoc = await _db.collection('items').doc(itemId).get();
    if (itemDoc.exists && itemDoc.data()?['status'] != 'available') {
      throw Exception('This item is no longer available.');
    }

    final offerRef = _db.collection('offers').doc();

    final offer = OfferModel(
      id: offerRef.id,
      roomId: roomId,
      itemId: itemId,
      buyerId: buyerId,
      sellerId: sellerId,
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

    try {
      final buyerDoc = await _db.collection('users').doc(buyerId).get();
      final buyerName =
          buyerDoc.data()?['name']?.toString().trim().isNotEmpty == true
          ? buyerDoc.data()!['name'].toString()
          : 'Buyer';
      await NotificationService.instance.notifyUser(
        userId: sellerId,
        title: 'New Offer Received',
        body: '$buyerName offered RM${price.toStringAsFixed(2)} for $itemTitle',
        type: 'offer',
        relatedId: offerRef.id,
        relatedType: 'offer',
        route: 'chat',
        chatRoomId: roomId,
      );
    } catch (_) {}
  }

  static Future<void> updateOfferStatus({
    required String offerId,
    required String roomId,
    required String status, // 'accepted', 'rejected', 'countered', 'cancelled'
    required String actionUserId,
  }) async {
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
      default:
        systemText = 'Offer updated';
    }

    await ChatService.sendMessage(
      roomId: roomId,
      senderId: actionUserId,
      type: 'system',
      text: systemText,
    );

    if (status == 'rejected') {
      try {
        final data = offerDoc.data()!;
        final itemDoc = await _db.collection('items').doc(data['itemId']).get();
        final itemTitle = itemDoc.data()?['title'] ?? 'your item';
        await NotificationService.instance.notifyUser(
          userId: data['buyerId'],
          title: 'Offer Rejected',
          body: 'Your offer for $itemTitle was rejected.',
          type: 'offer_rejected',
          relatedId: offerId,
          relatedType: 'offer',
          route: 'chat',
          chatRoomId: roomId,
        );
      } catch (_) {}
    }
  }
}
