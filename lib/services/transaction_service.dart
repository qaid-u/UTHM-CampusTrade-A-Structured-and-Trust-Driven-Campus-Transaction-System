import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/transaction_model.dart';
import '../models/offer_model.dart';
import '../models/message_model.dart';
import 'chat_service.dart';
import 'notification_service.dart';

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

  /// Create transaction from an accepted offer (legacy fallback)
  Future<void> createTransactionFromOffer(
    OfferModel offer,
    String itemTitle,
  ) async {
    final txRef = _transactions.doc(offer.id);

    final txDoc = await txRef.get().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw Exception('Timeout checking transaction status'),
    );
    if (txDoc.exists) return;

    final platformFee = offer.price * 0.05;
    final transaction = TransactionModel(
      id: offer.id,
      itemId: offer.itemId,
      itemTitle: itemTitle,
      buyerId: offer.buyerId,
      sellerId: offer.sellerId,
      offerPrice: offer.price,
      finalPrice: offer.price,
      platformFee: platformFee,
      meetupLocation: '',
      meetupLatitude: 0.0,
      meetupLongitude: 0.0,
      status: TransactionStatus.accepted,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      buyerMeetupConfirmed: false,
      sellerMeetupConfirmed: false,
      receiptUploaded: false,
      paymentVerified: false,
    );

    final batch = _firestore.batch();
    batch.set(txRef, transaction.toFirestore());

    final roomRef = _firestore.collection('chatRooms').doc(offer.roomId);
    batch.update(roomRef, {
      'transactionId': offer.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final itemRef = _firestore.collection('items').doc(offer.itemId);
    batch.update(itemRef, {'status': 'sold'});

    await batch.commit();

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
    final firestore = FirebaseFirestore.instance;
    final offerRef = firestore.collection('offers').doc(offerId);

    // Fetch details
    final offerDoc = await offerRef.get().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw Exception('Timeout fetching offer details'),
    );
    if (!offerDoc.exists) return;

    final offerData = offerDoc.data()!;
    final currentStatus = offerData['status'];

    if (currentStatus == 'accepted') return;

    final itemId = offerData['itemId'] ?? '';
    final buyerId = offerData['buyerId'] ?? '';
    final price = (offerData['price'] ?? 0.0).toDouble();

    // Fetch item
    final itemDoc = await firestore.collection('items').doc(itemId).get().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw Exception('Timeout fetching item details'),
    );
    final itemTitle = itemDoc.data()?['title'] ?? 'Item';

    // Fetch accepted offer message
    final msgs = await firestore
        .collection('chatRooms')
        .doc(roomId)
        .collection('messages')
        .where('offerId', isEqualTo: offerId)
        .limit(1)
        .get();

    // Fetch competing offers
    final otherOffers = await firestore
        .collection('offers')
        .where('itemId', isEqualTo: itemId)
        .where('status', isEqualTo: 'pending')
        .get();

    // Parallel fetch of other offers' messages
    final rejectionQueries = otherOffers.docs
        .where((doc) => doc.id != offerId)
        .map((doc) async {
          final otherRoomId = doc.data()['roomId'] as String?;
          if (otherRoomId == null) return null;
          final otherMsgs = await firestore
              .collection('chatRooms')
              .doc(otherRoomId)
              .collection('messages')
              .where('offerId', isEqualTo: doc.id)
              .limit(1)
              .get();
          return {
            'offerDoc': doc,
            'roomId': otherRoomId,
            'messageDoc': otherMsgs.docs.isNotEmpty ? otherMsgs.docs.first : null,
          };
        });
    final rejectionData = (await Future.wait(rejectionQueries)).whereType<Map<String, dynamic>>().toList();

    // Construct atomic WriteBatch
    final batch = firestore.batch();

    // 1. Update accepted offer status
    batch.update(offerRef, {
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Create transaction document
    final txRef = firestore.collection('transactions').doc(offerId);
    final platformFee = price * 0.05;
    final transaction = TransactionModel(
      id: offerId,
      itemId: itemId,
      itemTitle: itemTitle,
      buyerId: buyerId,
      sellerId: actionUserId,
      offerPrice: price,
      finalPrice: price,
      platformFee: platformFee,
      meetupLocation: '',
      meetupLatitude: 0.0,
      meetupLongitude: 0.0,
      status: TransactionStatus.accepted,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      buyerMeetupConfirmed: false,
      sellerMeetupConfirmed: false,
      receiptUploaded: false,
      paymentVerified: false,
    );
    batch.set(txRef, transaction.toFirestore());

    // 3. Lock item
    final itemRef = firestore.collection('items').doc(itemId);
    batch.update(itemRef, {'status': 'sold'});

    // 4. Update the message card associated with accepted offer
    if (msgs.docs.isNotEmpty) {
      batch.update(msgs.docs.first.reference, {'offerStatus': 'accepted'});
    }

    // 5. Add system message to accepted chat room
    final acceptedMsgRef = firestore
        .collection('chatRooms')
        .doc(roomId)
        .collection('messages')
        .doc();
    final acceptedMsg = MessageModel(
      id: acceptedMsgRef.id,
      senderId: actionUserId,
      type: 'system',
      text: 'Offer accepted',
      createdAt: DateTime.now(),
    );
    batch.set(acceptedMsgRef, acceptedMsg.toFirestore());

    // 6. Update chatRoom metadata for accepted room
    final roomRef = firestore.collection('chatRooms').doc(roomId);
    batch.update(roomRef, {
      'transactionId': offerId,
      'lastMessage': 'Offer accepted',
      'lastMessageType': 'system',
      'lastSenderId': actionUserId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 7. Reject competing offers and update their messages/rooms
    final List<Future<void>> notifyTasks = [];
    for (final item in rejectionData) {
      final otherOfferDoc = item['offerDoc'] as QueryDocumentSnapshot<Map<String, dynamic>>;
      final otherRoomId = item['roomId'] as String;
      final otherMsgDoc = item['messageDoc'] as DocumentSnapshot<Map<String, dynamic>>?;

      // Reject offer doc
      batch.update(otherOfferDoc.reference, {
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update offer message card status
      if (otherMsgDoc != null) {
        batch.update(otherMsgDoc.reference, {'offerStatus': 'rejected'});
      }

      // Add system message
      final otherMsgRef = firestore
          .collection('chatRooms')
          .doc(otherRoomId)
          .collection('messages')
          .doc();
      final otherMsg = MessageModel(
        id: otherMsgRef.id,
        senderId: actionUserId,
        type: 'system',
        text: 'Offer rejected: Item sold to another buyer.',
        createdAt: DateTime.now(),
      );
      batch.set(otherMsgRef, otherMsg.toFirestore());

      // Update chatRoom metadata
      final otherRoomRef = firestore.collection('chatRooms').doc(otherRoomId);
      batch.update(otherRoomRef, {
        'lastMessage': 'Offer rejected: Item sold to another buyer.',
        'lastMessageType': 'system',
        'lastSenderId': actionUserId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Notify users
      final otherBuyerId = otherOfferDoc.data()['buyerId'] as String?;
      if (otherBuyerId != null) {
        notifyTasks.add(
          NotificationService.instance.notifyUser(
            userId: otherBuyerId,
            title: "Offer Rejected",
            body: "The item has been sold to another buyer.",
            type: 'system',
            itemId: itemId,
            chatRoomId: otherRoomId,
          ),
        );
      }
    }

    // Commit atomic write batch
    await batch.commit();

    // Trigger notification tasks
    await Future.wait(notifyTasks);

    // Notify accepted buyer
    await NotificationService.instance.notifyUser(
      userId: buyerId,
      title: "Offer Accepted 🎉",
      body: "Seller accepted your offer of RM ${price.toStringAsFixed(2)}!",
      type: 'system',
      itemId: itemId,
      chatRoomId: roomId,
    );
  }

  /// Synchronizes transaction state with items, offers, and chatRooms
  Future<void> syncTransactionState({
    required String transactionId,
    required TransactionStatus status,
    required String roomId,
    required String itemId,
    required String actionUserId,
    String? cancelledBy,
    String? cancelledReason,
  }) async {
    final batch = _firestore.batch();
    final txRef = _transactions.doc(transactionId);

    final updates = <String, dynamic>{
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (status == TransactionStatus.cancelled) {
      if (cancelledBy != null) updates['cancelledBy'] = cancelledBy;
      if (cancelledReason != null) updates['cancelledReason'] = cancelledReason;
    }

    batch.update(txRef, updates);

    // Sync to Item
    final itemRef = _firestore.collection('items').doc(itemId);
    if (status == TransactionStatus.completed) {
      batch.update(itemRef, {'status': 'completed'});
    } else if (status == TransactionStatus.cancelled) {
      batch.update(itemRef, {'status': 'available'});
    } else if (status == TransactionStatus.accepted) {
      batch.update(itemRef, {'status': 'sold'});
    }

    // Sync to ChatRoom (Remove transactionId on cancel to allow fresh offers)
    final roomRef = _firestore.collection('chatRooms').doc(roomId);
    if (status == TransactionStatus.cancelled) {
      batch.update(roomRef, {
        'transactionId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.update(roomRef, {
        'transactionId': transactionId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  /// Sends a transaction system message to a chat room
  Future<void> sendTransactionSystemMessage({
    required String roomId,
    required String senderId,
    required String text,
    required String type, // 'system', 'transaction_update', 'rating_prompt', etc.
  }) async {
    await ChatService.sendMessage(
      roomId: roomId,
      senderId: senderId,
      text: text,
      type: type,
    );
  }

  /// Strict transition of transaction state (Backward compatible helper)
  Future<void> updateTransactionStatus({
    required String transactionId,
    required TransactionStatus newStatus,
    required String actionUserId,
    required String roomId,
  }) async {
    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) return;

    final tx = TransactionModel.fromFirestore(txDoc);

    if (newStatus == TransactionStatus.cancelled) {
      await cancelTransaction(
        transactionId: transactionId,
        actionUserId: actionUserId,
        roomId: roomId,
        reason: 'Cancelled by user request',
      );
      return;
    }

    if (newStatus == TransactionStatus.completed) {
      await completeTransaction(
        transactionId: transactionId,
        roomId: roomId,
        actionUserId: actionUserId,
      );
      return;
    }

    await syncTransactionState(
      transactionId: transactionId,
      status: newStatus,
      roomId: roomId,
      itemId: tx.itemId,
      actionUserId: actionUserId,
    );

    String systemText = '';
    String msgType = 'system';
    switch (newStatus) {
      case TransactionStatus.meetup_pending:
        systemText = 'Meetup scheduled';
        msgType = 'transaction_update';
        break;
      default:
        systemText = 'Transaction updated';
    }

    await sendTransactionSystemMessage(
      roomId: roomId,
      senderId: actionUserId,
      text: systemText,
      type: msgType,
    );
  }

  /// Suggests a meetup location
  Future<void> suggestMeetupLocation({
    required String transactionId,
    required String locationName,
    required double latitude,
    required double longitude,
    required String actionUserId,
    required String roomId,
  }) async {
    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) throw Exception('Transaction not found');
    final tx = TransactionModel.fromFirestore(txDoc);

    if (tx.status != TransactionStatus.accepted && tx.status != TransactionStatus.meetup_pending) {
      throw Exception('Cannot schedule meetup in current state');
    }

    final isBuyer = actionUserId == tx.buyerId;

    await txRef.update({
      'meetupLocation': locationName,
      'meetupLatitude': latitude,
      'meetupLongitude': longitude,
      'buyerMeetupConfirmed': isBuyer,
      'sellerMeetupConfirmed': !isBuyer,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final userName = isBuyer ? "Buyer" : "Seller";
    await sendTransactionSystemMessage(
      roomId: roomId,
      senderId: actionUserId,
      text: '$userName suggested meetup location: $locationName. Awaiting confirmation.',
      type: 'transaction_update',
    );
  }

  /// Confirms a suggested meetup location
  Future<void> confirmMeetupLocation({
    required String transactionId,
    required String actionUserId,
    required String roomId,
  }) async {
    final txRef = _transactions.doc(transactionId);

    await _firestore.runTransaction((transaction) async {
      final txSnapshot = await transaction.get(txRef);
      if (!txSnapshot.exists) throw Exception('Transaction not found');

      final tx = TransactionModel.fromFirestore(txSnapshot);
      final isBuyer = actionUserId == tx.buyerId;

      final buyerConfirmed = isBuyer ? true : tx.buyerMeetupConfirmed;
      final sellerConfirmed = !isBuyer ? true : tx.sellerMeetupConfirmed;
      final bothConfirmed = buyerConfirmed && sellerConfirmed;

      transaction.update(txRef, {
        'buyerMeetupConfirmed': buyerConfirmed,
        'sellerMeetupConfirmed': sellerConfirmed,
        if (bothConfirmed) 'status': TransactionStatus.meetup_pending.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    final updatedTxDoc = await txRef.get();
    final updatedTx = TransactionModel.fromFirestore(updatedTxDoc);

    final userName = actionUserId == updatedTx.buyerId ? "Buyer" : "Seller";

    await sendTransactionSystemMessage(
      roomId: roomId,
      senderId: actionUserId,
      text: '$userName confirmed meetup location: ${updatedTx.meetupLocation}',
      type: 'transaction_update',
    );

    if (updatedTx.buyerMeetupConfirmed && updatedTx.sellerMeetupConfirmed) {
      await syncTransactionState(
        transactionId: transactionId,
        status: TransactionStatus.meetup_pending,
        roomId: roomId,
        itemId: updatedTx.itemId,
        actionUserId: actionUserId,
      );

      await sendTransactionSystemMessage(
        roomId: roomId,
        senderId: actionUserId,
        text: 'Meetup Confirmed 📍 Meetup point: ${updatedTx.meetupLocation}',
        type: 'transaction_update',
      );

      final otherUserId = actionUserId == updatedTx.buyerId ? updatedTx.sellerId : updatedTx.buyerId;
      await NotificationService.instance.notifyUser(
        userId: otherUserId,
        title: "Meetup Confirmed 📍",
        body: "Meetup scheduled at ${updatedTx.meetupLocation}",
        type: 'transaction_update',
        itemId: updatedTx.itemId,
        chatRoomId: roomId,
      );
    }
  }

  /// Safe Zone validation helper for UTHM campuses
  static bool isSafeZone(double lat, double lng) {
    // UTHM Parit Raja campus approximate boundary
    if (lat >= 1.848 && lat <= 1.865 && lng >= 103.078 && lng <= 103.095) {
      return true;
    }
    // UTHM Pagoh campus approximate boundary
    if (lat >= 2.140 && lat <= 2.160 && lng >= 102.720 && lng <= 102.740) {
      return true;
    }
    return false;
  }

  /// Dummy payment receipt submission
  Future<void> uploadPaymentReceipt({
    required String transactionId,
    required String roomId,
    required String actionUserId,
    required String receiptUrl,
  }) async {
    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) throw Exception('Transaction not found');
    final tx = TransactionModel.fromFirestore(txDoc);

    if (tx.status != TransactionStatus.meetup_pending) {
      throw Exception('Cannot upload receipt in current state');
    }

    await txRef.update({
      'receiptUploaded': true,
      'receiptUrl': receiptUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Send the image message as requested: Message type: image
    await ChatService.sendMessage(
      roomId: roomId,
      senderId: actionUserId,
      text: receiptUrl,
      type: 'image',
    );

    await sendTransactionSystemMessage(
      roomId: roomId,
      senderId: actionUserId,
      text: 'Payment receipt uploaded. Seller, please verify the payment.',
      type: 'transaction_update',
    );
  }

  /// Manual verification of DuitNow receipts by Seller
  Future<void> verifyPayment({
    required String transactionId,
    required String roomId,
    required String actionUserId,
  }) async {
    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) throw Exception('Transaction not found');
    final tx = TransactionModel.fromFirestore(txDoc);

    if (!tx.receiptUploaded) {
      throw Exception('No receipt has been uploaded yet');
    }

    await txRef.update({
      'paymentVerified': true,
      'verifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await sendTransactionSystemMessage(
      roomId: roomId,
      senderId: actionUserId,
      text: 'Payment verified by seller. Awaiting item collection confirmation.',
      type: 'transaction_update',
    );

    await NotificationService.instance.notifyUser(
      userId: tx.buyerId,
      title: "Payment Verified",
      body: "Seller verified your payment. You can now confirm item collection.",
      type: 'transaction_update',
      itemId: tx.itemId,
      chatRoomId: roomId,
    );
  }

  /// Cancellation logic: buyer or seller can cancel BEFORE completion
  Future<void> cancelTransaction({
    required String transactionId,
    required String actionUserId,
    required String roomId,
    required String reason,
  }) async {
    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) throw Exception('Transaction not found');

    final tx = TransactionModel.fromFirestore(txDoc);

    if (tx.status == TransactionStatus.completed) {
      throw Exception('Cannot cancel a completed transaction');
    }
    if (tx.status == TransactionStatus.cancelled) {
      throw Exception('Transaction is already cancelled');
    }

    await syncTransactionState(
      transactionId: transactionId,
      status: TransactionStatus.cancelled,
      roomId: roomId,
      itemId: tx.itemId,
      actionUserId: actionUserId,
      cancelledBy: actionUserId,
      cancelledReason: reason,
    );

    final otherUserId = actionUserId == tx.buyerId ? tx.sellerId : tx.buyerId;

    await sendTransactionSystemMessage(
      roomId: roomId,
      senderId: actionUserId,
      text: 'Transaction cancelled by ${actionUserId == tx.buyerId ? "buyer" : "seller"}. Reason: $reason',
      type: 'transaction_update',
    );

    await NotificationService.instance.notifyUser(
      userId: otherUserId,
      title: "Transaction Cancelled",
      body: "The deal for ${tx.itemTitle} was cancelled.",
      type: 'transaction_update',
      itemId: tx.itemId,
      chatRoomId: roomId,
    );
  }

  /// Completion logic: ONLY buyer can finalize completion
  Future<void> completeTransaction({
    required String transactionId,
    required String roomId,
    required String actionUserId,
  }) async {
    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) throw Exception('Transaction not found');
    final tx = TransactionModel.fromFirestore(txDoc);

    if (actionUserId != tx.buyerId) {
      throw Exception('Only the buyer can finalize transaction completion');
    }

    if (tx.status == TransactionStatus.completed) {
      throw Exception('Transaction is already completed');
    }
    if (tx.status == TransactionStatus.cancelled) {
      throw Exception('Cannot complete a cancelled transaction');
    }

    await syncTransactionState(
      transactionId: transactionId,
      status: TransactionStatus.completed,
      roomId: roomId,
      itemId: tx.itemId,
      actionUserId: actionUserId,
    );

    await txRef.update({
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await sendTransactionSystemMessage(
      roomId: roomId,
      senderId: actionUserId,
      text: 'Transaction completed! Tap here to leave a review.',
      type: 'rating_prompt',
    );

    await NotificationService.instance.notifyUser(
      userId: tx.sellerId,
      title: "Transaction Completed 🎉",
      body: "Buyer confirmed receipt of the item.",
      type: 'transaction_update',
      itemId: tx.itemId,
      chatRoomId: roomId,
    );
  }
}
