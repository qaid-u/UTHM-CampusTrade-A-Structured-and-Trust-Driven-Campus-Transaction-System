import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/transaction_service.dart';
import '../widgets/status_badge.dart';
import 'meetup_location_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _transactionsStream;

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.currentUser;
    if (user != null) {
      _transactionsStream = FirebaseFirestore.instance
          .collection('transactions')
          .where('participants', arrayContains: user.uid)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _transactionsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load transactions.'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('No transactions yet.'));
          }

          final txs = docs.map(TransactionModel.fromFirestore).toList();
          txs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: txs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final tx = txs[index];

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.itemTitle.isNotEmpty ? tx.itemTitle : tx.itemId,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      StatusBadge(status: tx.status),
                      const SizedBox(height: 4),
                      Text(
                        'Offer Price: RM ${tx.offerPrice.toStringAsFixed(2)}',
                      ),
                      Text(
                        'Platform Fee: RM ${tx.platformFee.toStringAsFixed(2)}',
                      ),
                      if (tx.meetupLocation.isNotEmpty)
                        Text('Meetup: ${tx.meetupLocation}'),
                      const SizedBox(height: 10),
                      if (tx.sellerId == user.uid &&
                          tx.status == TransactionStatus.pending_offer)
                        Row(
                          children: [
                            FilledButton(
                              onPressed: () =>
                                  _update(tx.id, 'accepted', user.uid),
                              child: const Text('Accept'),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: () =>
                                  _update(tx.id, 'rejected', user.uid),
                              child: const Text('Reject'),
                            ),
                          ],
                        ),
                      if (tx.status == TransactionStatus.accepted)
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => MeetupLocationScreen(
                                        selected: tx.meetupLocation,
                                      ),
                                    ),
                                  );
                                  if (result != null && result is Map) {
                                    // Fetch roomId
                                    String rId = '';
                                    final offerDoc = await FirebaseFirestore.instance
                                        .collection('offers')
                                        .doc(tx.id)
                                        .get();
                                    if (offerDoc.exists) {
                                      rId = offerDoc.data()?['roomId'] ?? '';
                                    }
                                    if (rId.isEmpty) {
                                      final rooms = await FirebaseFirestore.instance
                                          .collection('chatRooms')
                                          .where('participantIds', arrayContains: user.uid)
                                          .get();
                                      if (rooms.docs.isNotEmpty) {
                                        rId = rooms.docs.first.id;
                                      }
                                    }

                                    await TransactionService.instance.suggestMeetupLocation(
                                      transactionId: tx.id,
                                      locationName: result['location'],
                                      latitude: result['latitude'],
                                      longitude: result['longitude'],
                                      actionUserId: user.uid,
                                      roomId: rId,
                                    );
                                  }
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.blue.shade600,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.map_rounded, size: 16),
                                label: const Text('Set Meetup', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _update(tx.id, 'meetup_pending', user.uid),
                                child: const Text('Confirm Meetup', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                      if (tx.status == TransactionStatus.meetup_pending)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (tx.buyerId == user.uid)
                              FilledButton(
                                onPressed: () =>
                                    _update(tx.id, 'completed', user.uid),
                                child: const Text('Confirm Item Received'),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Awaiting buyer to confirm receipt',
                                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                                ),
                              ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () =>
                                  _update(tx.id, 'cancelled', user.uid),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                              child: const Text('Cancel Deal'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _update(String id, String status, String currentUserId) async {
    final txRef = FirebaseFirestore.instance.collection('transactions').doc(id);
    final txDoc = await txRef.get();
    if (!txDoc.exists) return;

    final txData = txDoc.data()!;
    final buyerId = txData['buyerId'] as String?;
    final sellerId = txData['sellerId'] as String?;
    final itemTitle = txData['itemTitle'] ?? txData['itemId'] ?? 'your item';

    // Find roomId from offers or chatRooms
    String roomId = '';
    final offerDoc = await FirebaseFirestore.instance
        .collection('offers')
        .doc(id)
        .get();
    if (offerDoc.exists) {
      roomId = offerDoc.data()?['roomId'] ?? '';
    }

    if (roomId.isEmpty) {
      final rooms = await FirebaseFirestore.instance
          .collection('chatRooms')
          .where('participantIds', arrayContains: currentUserId)
          .get();
      if (rooms.docs.isNotEmpty) {
        roomId = rooms.docs.first.id;
      }
    }

    final newStatus = TransactionStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => TransactionStatus.pending_offer,
    );

    try {
      if (newStatus == TransactionStatus.meetup_pending) {
        await TransactionService.instance.confirmMeetupLocation(
          transactionId: id,
          actionUserId: currentUserId,
          roomId: roomId,
        );
      } else {
        await TransactionService.instance.updateTransactionStatus(
          transactionId: id,
          newStatus: newStatus,
          actionUserId: currentUserId,
          roomId: roomId,
        );
      }

      // Backwards compatible notification triggering
      if (status == 'accepted' || status == 'rejected') {
        if (buyerId != null) {
          await NotificationService.instance.notifyUser(
            userId: buyerId,
            title: status == 'accepted' ? 'Offer accepted' : 'Offer rejected',
            body: 'Your offer for $itemTitle was $status.',
            type: 'offer',
            itemId: txData['itemId'],
            chatRoomId: roomId,
          );
        }
      } else if (status == 'completed') {
        final recipientId = currentUserId == buyerId ? sellerId : buyerId;
        if (recipientId != null) {
          await NotificationService.instance.notifyUser(
            userId: recipientId,
            title: 'Transaction completed',
            body: 'The transaction for $itemTitle was marked completed.',
            type: 'transaction',
            itemId: txData['itemId'],
            chatRoomId: roomId,
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to update transaction status: $e');
    }
  }
}
