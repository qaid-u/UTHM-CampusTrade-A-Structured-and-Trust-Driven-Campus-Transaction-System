import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/status_badge.dart';

class TransactionHistoryScreen extends StatelessWidget {
  const TransactionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction history')),
      body: AnimatedBuilder(
        animation: DatabaseService.instance,
        builder: (context, _) {
          AuthService.instance.refreshCurrentUser();
          final user = AuthService.instance.currentUser!;
          final transactions = DatabaseService.instance.transactions
              .where((tx) => tx.buyerId == user.id || tx.sellerId == user.id)
              .toList();
          if (transactions.isEmpty) {
            return const Center(child: Text('No offers or transactions yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final tx = transactions[index];
              final item = DatabaseService.instance.findItem(tx.itemId);
              final buyer = DatabaseService.instance.findUser(tx.buyerId);
              final seller = DatabaseService.instance.findUser(tx.sellerId);
              final isSeller = tx.sellerId == user.id;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item?.title ?? 'Deleted item',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          StatusBadge(status: tx.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${isSeller ? 'Buyer' : 'Seller'}: ${isSeller ? buyer?.name : seller?.name}',
                      ),
                      Text(
                        'Offer price: RM ${tx.offerPrice.toStringAsFixed(2)}',
                      ),
                      Text('Meetup: ${tx.meetupLocation}'),
                      Text(
                        'Date: ${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year}',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (isSeller &&
                              tx.status == TransactionStatus.pending)
                            FilledButton.icon(
                              onPressed: () => DatabaseService.instance
                                  .updateTransactionStatus(
                                    tx.id,
                                    TransactionStatus.accepted,
                                  ),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Accept'),
                            ),
                          if (isSeller &&
                              tx.status == TransactionStatus.pending)
                            OutlinedButton.icon(
                              onPressed: () => DatabaseService.instance
                                  .updateTransactionStatus(
                                    tx.id,
                                    TransactionStatus.rejected,
                                  ),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Reject'),
                            ),
                          if (tx.status == TransactionStatus.accepted)
                            FilledButton.icon(
                              onPressed: () => DatabaseService.instance
                                  .updateTransactionStatus(
                                    tx.id,
                                    TransactionStatus.completed,
                                  ),
                              icon: const Icon(Icons.done_all_rounded),
                              label: const Text('Mark completed'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: transactions.length,
          );
        },
      ),
    );
  }
}
