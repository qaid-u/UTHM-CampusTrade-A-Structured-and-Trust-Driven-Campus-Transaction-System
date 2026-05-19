import 'package:cloud_firestore/cloud_firestore.dart';
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
    final offerRef = FirebaseFirestore.instance
        .collection('offers')
        .doc(offerId);

    // Document existence check
    final offerDoc = await offerRef.get().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw Exception('Timeout fetching offer details'),
    );
    if (!offerDoc.exists) return;

    final offerData = offerDoc.data()!;
    final currentStatus = offerData['status'];

    // Prevent duplicate accepted state changes
    if (currentStatus == 'accepted') return;

    final batch = FirebaseFirestore.instance.batch();

    batch.update(offerRef, {
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update the message associated with this offer in chat
    final msgs = await FirebaseFirestore.instance
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
      batch.update(msgs.docs.first.reference, {'offerStatus': 'accepted'});
    }

    final itemId = offerData['itemId'] ?? '';
    final itemDoc = await FirebaseFirestore.instance
        .collection('items')
        .doc(itemId)
        .get()
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw Exception('Timeout fetching item details'),
        );
    final itemTitle = itemDoc.data()?['title'] ?? 'Item';

    await batch.commit();

    // Send "Offer accepted" system message
    await ChatService.sendMessage(
      roomId: roomId,
      senderId: actionUserId,
      type: 'system',
      text: 'Offer accepted',
    );

    // Creates the transaction document (with duplicate checks inside)
    final offerModel = OfferModel.fromFirestore(offerDoc);
    await instance.createTransactionFromOffer(offerModel, itemTitle);
  }

  /// Strict transition of transaction state
  /// pending_offer -> accepted -> meetup_pending -> completed
  /// OR
  /// pending_offer -> rejected -> cancelled
  Future<void> updateTransactionStatus({
    required String transactionId,
    required TransactionStatus newStatus,
    required String actionUserId,
    required String roomId,
  }) async {
    final txRef = _transactions.doc(transactionId);
    final txDoc = await txRef.get().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw Exception('Timeout fetching transaction'),
    );
    if (!txDoc.exists) return;

    final tx = TransactionModel.fromFirestore(txDoc);
    final currentStatus = tx.status;

    // Validate strict state transition rule
    bool isValid = false;
    if (currentStatus == TransactionStatus.pending_offer) {
      if (newStatus == TransactionStatus.accepted ||
          newStatus == TransactionStatus.rejected) {
        isValid = true;
      }
    } else if (currentStatus == TransactionStatus.accepted) {
      if (newStatus == TransactionStatus.meetup_pending ||
          newStatus == TransactionStatus.cancelled) {
        isValid = true;
      }
    } else if (currentStatus == TransactionStatus.meetup_pending) {
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

    await txRef.update({
      'status': newStatus.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    String systemText = '';
    String msgType = 'system';
    switch (newStatus) {
      case TransactionStatus.accepted:
        systemText = 'Offer accepted';
        msgType = 'system';
        break;
      case TransactionStatus.rejected:
        systemText = 'Offer rejected';
        msgType = 'system';
        break;
      case TransactionStatus.meetup_pending:
        systemText = 'Meetup scheduled';
        msgType = 'transaction_update';
        break;
      case TransactionStatus.completed:
        systemText = 'Transaction completed';
        msgType = 'transaction_update';
        break;
      case TransactionStatus.cancelled:
        systemText = 'Transaction cancelled';
        msgType = 'transaction_update';
        break;
      default:
        break;
    }

    if (systemText.isNotEmpty) {
      await ChatService.sendMessage(
        roomId: roomId,
        senderId: actionUserId,
        type: msgType,
        text: systemText,
      );
    }
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
