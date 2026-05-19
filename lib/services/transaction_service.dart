import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../models/offer_model.dart';
import 'chat_service.dart';

class TransactionService {
  TransactionService._();

  static final TransactionService instance = TransactionService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _transactions =>
      _firestore.collection('transactions');

  Stream<List<TransactionModel>> getUserTransactions(String userId) {
    return _transactions
        .where('participants', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => TransactionModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Create transaction from an accepted offer
  Future<void> createTransactionFromOffer(
    OfferModel offer,
    String itemTitle,
  ) async {
    final txRef = _transactions.doc(
      offer.id,
    ); // Mapping offerId to transactionId directly

    // Unique offerId -> transactionId mapping & existence check
    final txDoc = await txRef.get().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw Exception('Timeout checking transaction status'),
    );
    if (txDoc.exists) return;

    final platformFee = offer.price * 0.05;
    final transaction = TransactionModel(
      id: offer.id,
      offerId: offer.id,
      roomId: offer.roomId,
      itemId: offer.itemId,
      itemTitle: itemTitle,
      buyerId: offer.buyerId,
      sellerId: offer.sellerId,
      offerPrice: offer.price,
      finalPrice: offer.price,
      platformFee: platformFee,
      paymentMethod: '',
      paymentReference: '',
      paymentStatus: 'awaiting_selection',
      cancelReason: '',
      meetupLocation: '',
      meetupLatitude: 0.0,
      meetupLongitude: 0.0,
      status: TransactionStatus
          .accepted, // Accepted state upon successful acceptance
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final batch = _firestore.batch();
    batch.set(txRef, transaction.toFirestore());

    // Update ChatRoom to reference transactionId
    final roomRef = _firestore.collection('chatRooms').doc(offer.roomId);
    batch.update(roomRef, {
      'transactionId': offer.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Also update item status to sold
    final itemRef = _firestore.collection('items').doc(offer.itemId);
    batch.update(itemRef, {'status': 'sold'});

    await batch.commit();

    // Send "Transaction created" system message
    await ChatService.sendMessage(
      roomId: offer.roomId,
      senderId: offer.sellerId,
      type: 'system',
      text: 'Transaction created',
    );
  }

  /// Accepts an offer, updates database, and creates transaction securely (ensures only once)
  static Future<void> acceptOfferAndCreateTransaction({
    required String offerId,
    required String roomId,
    required String actionUserId,
  }) async {
    final db = FirebaseFirestore.instance;
    final offerRef = db.collection('offers').doc(offerId);
    final txRef = db.collection('transactions').doc(offerId);
    final roomRef = db.collection('chatRooms').doc(roomId);

    final offerDoc = await offerRef.get();
    if (!offerDoc.exists) {
      throw Exception('Offer not found');
    }

    final offerData = offerDoc.data() ?? {};
    final sellerId = offerData['sellerId']?.toString() ?? '';
    final buyerId = offerData['buyerId']?.toString() ?? '';
    final offerRoomId = offerData['roomId']?.toString() ?? '';
    final itemId = offerData['itemId']?.toString() ?? '';
    final createdBy = offerData['createdBy']?.toString() ?? buyerId;
    final currentStatus = offerData['status']?.toString() ?? 'pending';
    final createdAt = _readTimestamp(offerData['createdAt']);
    final price = _readDouble(offerData['price']);
    final recipientId = createdBy == sellerId ? buyerId : sellerId;

    if (actionUserId != recipientId) {
      throw Exception('Only the offer recipient can accept this offer');
    }

    if (offerRoomId != roomId) {
      throw Exception('Offer does not belong to this chat');
    }

    if (buyerId.isEmpty || sellerId.isEmpty || itemId.isEmpty) {
      throw Exception('Offer data is incomplete');
    }

    final itemRef = db.collection('items').doc(itemId);
    final itemDoc = await itemRef.get();
    if (!itemDoc.exists) {
      throw Exception('Item not found');
    }

    final itemData = itemDoc.data() ?? {};
    final itemSellerId = itemData['sellerId']?.toString() ?? '';
    final itemStatus = itemData['status']?.toString() ?? 'available';
    final itemTitle = itemData['title']?.toString() ?? 'Item';

    if (itemSellerId != sellerId) {
      throw Exception('Seller no longer owns this item');
    }

    final txDoc = await txRef.get();
    if (txDoc.exists || currentStatus == 'accepted') {
      return;
    }

    if (currentStatus != 'pending') {
      throw Exception('This offer has already been $currentStatus');
    }

    if (DateTime.now().difference(createdAt).inHours >= 48) {
      await offerRef.update({
        'status': 'expired',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      try {
        final msgs = await db
            .collection('chatRooms')
            .doc(roomId)
            .collection('messages')
            .where('offerId', isEqualTo: offerId)
            .limit(1)
            .get();
        if (msgs.docs.isNotEmpty) {
          await msgs.docs.first.reference.update({'offerStatus': 'expired'});
        }
      } catch (e) {
        debugPrint('Failed to mirror expired offer status: $e');
      }
      throw Exception('This offer has expired');
    }

    if (itemStatus != 'available') {
      throw Exception('This item is no longer available');
    }

    final platformFee = price * 0.05;
    final now = FieldValue.serverTimestamp();

    final batch = db.batch();
    batch.update(offerRef, {
      'status': 'accepted',
      'updatedAt': now,
    });
    batch.set(txRef, {
      'transactionId': offerId,
      'offerId': offerId,
      'roomId': roomId,
      'itemId': itemId,
      'itemTitle': itemTitle,
      'buyerId': buyerId,
      'sellerId': sellerId,
      'participants': [buyerId, sellerId],
      'offerPrice': price,
      'finalPrice': price,
      'platformFee': platformFee,
      'paymentMethod': '',
      'paymentReference': '',
      'paymentStatus': 'awaiting_selection',
      'paymentProofUrl': '',
      'cancelReason': '',
      'issueReason': '',
      'issueStatus': '',
      'buyerRating': 0,
      'sellerRating': 0,
      'buyerReview': '',
      'sellerReview': '',
      'meetupLocation': '',
      'meetupLatitude': 0.0,
      'meetupLongitude': 0.0,
      'status': TransactionStatus.accepted.name,
      'createdAt': now,
      'updatedAt': now,
    });
    batch.update(itemRef, {
      'status': 'sold',
      'updatedAt': now,
    });
    batch.set(
      roomRef,
      {
        'transactionId': offerId,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    try {
      // Update the message associated with this offer in chat.
      final msgs = await db
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
        await msgs.docs.first.reference.update({'offerStatus': 'accepted'});
      }

      final pendingOffers = await db
          .collection('offers')
          .where('itemId', isEqualTo: itemId)
          .where('status', isEqualTo: 'pending')
          .get();

      final batch = db.batch();
      var rejectedCount = 0;
      final rejectedOfferRooms = <String, String>{};
      for (final pendingOffer in pendingOffers.docs) {
        if (pendingOffer.id != offerId) {
          batch.update(pendingOffer.reference, {
            'status': 'rejected',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          final pendingData = pendingOffer.data();
          rejectedOfferRooms[pendingOffer.id] =
              pendingData['roomId']?.toString() ?? '';
          rejectedCount++;
        }
      }
      if (rejectedCount > 0) {
        await batch.commit();
      }

      for (final entry in rejectedOfferRooms.entries) {
        final rejectedRoomId = entry.value;
        if (rejectedRoomId.isEmpty) continue;

        final rejectedMessages = await db
            .collection('chatRooms')
            .doc(rejectedRoomId)
            .collection('messages')
            .where('offerId', isEqualTo: entry.key)
            .limit(1)
            .get();

        if (rejectedMessages.docs.isNotEmpty) {
          await rejectedMessages.docs.first.reference.update({
            'offerStatus': 'rejected',
          });
        }
      }

      await ChatService.sendMessage(
        roomId: roomId,
        senderId: actionUserId,
        type: 'system',
        text: 'Offer accepted. Transaction created for $itemTitle.',
      );
    } catch (e) {
      // The transaction itself is already created; do not make the UI report
      // a failed accept just because chat mirror updates or notifications lag.
      // The next app refresh can still read the canonical offer/transaction docs.
      debugPrint('Post-accept chat sync failed: $e');
    }
  }

  static double _readDouble(Object? value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static DateTime _readTimestamp(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  /// Strict transition of transaction state
  /// pending -> accepted -> payment_processing -> completed
  /// OR
  /// pending -> rejected -> cancelled
  Future<void> updateTransactionStatus({
    required String transactionId,
    required TransactionStatus newStatus,
    required String actionUserId,
    required String roomId,
    String cancelReason = '',
  }) async {
    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw Exception('Timeout fetching transaction'),
    );
    if (!txDoc.exists) return;

    final tx = TransactionModel.fromFirestore(txDoc);
    final currentStatus = tx.status;

    if (actionUserId != tx.buyerId && actionUserId != tx.sellerId) {
      throw Exception('You are not part of this transaction');
    }

    if (newStatus == TransactionStatus.payment_processing &&
        actionUserId != tx.buyerId) {
      throw Exception('Only the buyer can start payment processing');
    }

    if (newStatus == TransactionStatus.completed &&
        actionUserId != tx.sellerId) {
      throw Exception('Only the seller can complete the transaction');
    }

    if (newStatus == TransactionStatus.payment_processing &&
        tx.meetupLocation.isEmpty) {
      throw Exception('Please set a meetup location before payment');
    }

    if (newStatus == TransactionStatus.completed &&
        tx.paymentMethod.isEmpty) {
      throw Exception('Payment method must be selected before completion');
    }

    // Validate strict state transition rule
    bool isValid = false;
    if (currentStatus == TransactionStatus.pending) {
      if (newStatus == TransactionStatus.accepted ||
          newStatus == TransactionStatus.rejected) {
        isValid = true;
      }
    } else if (currentStatus == TransactionStatus.accepted) {
      if (newStatus == TransactionStatus.payment_processing ||
          newStatus == TransactionStatus.cancelled) {
        isValid = true;
      }
    } else if (currentStatus == TransactionStatus.payment_processing) {
      if (newStatus == TransactionStatus.completed ||
          newStatus == TransactionStatus.cancelled) {
        isValid = true;
      }
    }

    if (!isValid) {
      throw Exception(
        'Invalid transaction state transition from ${currentStatus.name} to ${newStatus.name}',
      );
    }

    final now = FieldValue.serverTimestamp();
    final batch = _firestore.batch();

    batch.update(txRef, {
      'status': newStatus.name,
      if (newStatus == TransactionStatus.completed) 'paymentStatus': 'verified',
      if (newStatus == TransactionStatus.cancelled)
        'cancelReason': cancelReason.trim(),
      'updatedAt': now,
    });

    if (newStatus == TransactionStatus.cancelled) {
      batch.update(_firestore.collection('items').doc(tx.itemId), {
        'status': 'available',
        'updatedAt': now,
      });

      if (tx.offerId.isNotEmpty) {
        batch.update(_firestore.collection('offers').doc(tx.offerId), {
          'status': 'cancelled',
          'updatedAt': now,
        });
      }
    }

    await batch.commit();

    String systemText = '';
    switch (newStatus) {
      case TransactionStatus.accepted:
        systemText = 'Offer accepted';
        break;
      case TransactionStatus.rejected:
        systemText = 'Offer rejected';
        break;
      case TransactionStatus.payment_processing:
        systemText = 'Payment processing';
        break;
      case TransactionStatus.completed:
        systemText = 'Transaction completed';
        break;
      case TransactionStatus.cancelled:
        systemText = 'Transaction cancelled';
        break;
      default:
        break;
    }

    if (systemText.isNotEmpty) {
      await ChatService.sendMessage(
        roomId: roomId,
        senderId: actionUserId,
        type: 'system',
        text: systemText,
      );
    }
  }

  Future<void> choosePaymentMethodAndStartPayment({
    required String transactionId,
    required String actionUserId,
    required String roomId,
    required String paymentMethod,
    String paymentReference = '',
    String paymentProofUrl = '',
  }) async {
    final trimmedMethod = paymentMethod.trim();
    if (trimmedMethod.isEmpty) {
      throw Exception('Please choose a payment method');
    }

    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) {
      throw Exception('Transaction not found');
    }

    final tx = TransactionModel.fromFirestore(txDoc);
    if (actionUserId != tx.buyerId) {
      throw Exception('Only the buyer can choose payment method');
    }

    if (tx.status != TransactionStatus.accepted) {
      throw Exception('Payment can only start after the offer is accepted');
    }

    if (tx.meetupLocation.isEmpty) {
      throw Exception('Please set a meetup location before choosing payment');
    }

    await txRef.update({
      'status': TransactionStatus.payment_processing.name,
      'paymentMethod': trimmedMethod,
      'paymentReference': paymentReference.trim(),
      'paymentStatus': 'awaiting_seller_confirmation',
      'paymentProofUrl': paymentProofUrl.trim(),
      'paymentSelectedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await ChatService.sendMessage(
      roomId: roomId,
      senderId: actionUserId,
      type: 'system',
      text: 'Buyer selected $trimmedMethod. Waiting for seller confirmation.',
    );
  }

  Future<void> reportTransactionIssue({
    required String transactionId,
    required String actionUserId,
    required String roomId,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw Exception('Please describe the issue');
    }

    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) {
      throw Exception('Transaction not found');
    }

    final tx = TransactionModel.fromFirestore(txDoc);
    if (actionUserId != tx.buyerId && actionUserId != tx.sellerId) {
      throw Exception('You are not part of this transaction');
    }

    await txRef.update({
      'issueReason': trimmedReason,
      'issueStatus': 'open',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await ChatService.sendMessage(
      roomId: roomId,
      senderId: actionUserId,
      type: 'system',
      text: 'Transaction issue reported: $trimmedReason',
    );
  }

  /// Helper to complete a transaction
  Future<void> completeTransaction(
    String transactionId,
    String actionUserId,
    String roomId,
  ) async {
    await updateTransactionStatus(
      transactionId: transactionId,
      newStatus: TransactionStatus.completed,
      actionUserId: actionUserId,
      roomId: roomId,
    );
  }

  Future<void> submitRating({
    required String transactionId,
    required String actionUserId,
    required double rating,
    String review = '',
  }) async {
    if (rating < 1 || rating > 5) {
      throw Exception('Rating must be between 1 and 5');
    }

    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) {
      throw Exception('Transaction not found');
    }

    final tx = TransactionModel.fromFirestore(txDoc);
    if (tx.status != TransactionStatus.completed) {
      throw Exception('You can rate only after transaction is completed');
    }

    if (actionUserId == tx.buyerId) {
      await txRef.update({
        'buyerRating': rating,
        'buyerReview': review.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    if (actionUserId == tx.sellerId) {
      await txRef.update({
        'sellerRating': rating,
        'sellerReview': review.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    throw Exception('You are not part of this transaction');
  }

  /// Helper to set meetup location
  Future<void> setMeetupLocation({
    required String transactionId,
    required String locationName,
    required double latitude,
    required double longitude,
  }) async {
    await _transactions.doc(transactionId).update({
      'meetupLocation': locationName,
      'meetupLatitude': latitude,
      'meetupLongitude': longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
