import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/custom_button.dart';
import 'chat_screen.dart';
import 'meetup_location_screen.dart';

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DatabaseService.instance,
      builder: (context, _) {
        final item = DatabaseService.instance.findItem(itemId)!;
        final seller = DatabaseService.instance.findUser(item.sellerId)!;
        return Scaffold(
          appBar: AppBar(title: const Text('Item details')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B2D5B), Color(0xFF1BA86D)],
                  ),
                ),
                child: Center(
                  child: Text(
                    item.imageLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 42,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                item.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'RM ${item.price.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(item.category)),
                  Chip(label: Text(item.condition)),
                  Chip(
                    avatar: const Icon(Icons.place_rounded, size: 16),
                    label: Text(item.meetupLocation),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _panel(
                context,
                title: 'Description',
                child: Text(item.description),
              ),
              const SizedBox(height: 12),
              _panel(
                context,
                title: 'Seller profile',
                child: Row(
                  children: [
                    CircleAvatar(child: Text(seller.name[0])),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seller.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text('${seller.studentId} | ${seller.email}'),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: seller.trustScore / 100,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          const SizedBox(height: 4),
                          Text('Trust score ${seller.trustScore}/100'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CustomButton(
                label: 'Make Offer',
                icon: Icons.local_offer_rounded,
                onPressed: () => _makeOffer(context, item.price),
              ),
              const SizedBox(height: 10),
              CustomButton(
                label: 'Chat Seller',
                icon: Icons.chat_rounded,
                isSecondary: true,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(itemId: item.id),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              CustomButton(
                label: 'View Meetup Location',
                icon: Icons.map_rounded,
                isSecondary: true,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        MeetupLocationScreen(selected: item.meetupLocation),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _panel(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _makeOffer(BuildContext context, double price) async {
    final controller = TextEditingController(text: price.toStringAsFixed(0));
    final item = DatabaseService.instance.findItem(itemId)!;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make an offer'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: 'RM '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result <= 0) return;
    await DatabaseService.instance.addTransaction(
      TransactionModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        itemId: item.id,
        buyerId: AuthService.instance.currentUser!.id,
        sellerId: item.sellerId,
        offerPrice: result,
        status: TransactionStatus.pending,
        meetupLocation: item.meetupLocation,
        createdAt: DateTime.now(),
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: const Text('Offer submitted. Seller can accept or reject it.'),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
  }
}
