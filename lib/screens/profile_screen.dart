import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/item_card.dart';
import 'item_detail_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: AnimatedBuilder(
        animation: DatabaseService.instance,
        builder: (context, _) {
          AuthService.instance.refreshCurrentUser();
          final user = AuthService.instance.currentUser!;
          final myListings = DatabaseService.instance.items
              .where((item) => item.sellerId == user.id)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      CircleAvatar(radius: 34, child: Text(user.name[0])),
                      const SizedBox(height: 10),
                      Text(
                        user.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(user.studentId),
                      Text(user.email),
                      Text(user.phone),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: user.trustScore / 100,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      const SizedBox(height: 8),
                      Text('Trust score: ${user.trustScore}/100'),
                      Text(
                        '${user.completedTransactions} completed transactions',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return Icon(
                            index < user.rating.round()
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: Colors.amber.shade700,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'My listings',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              if (myListings.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('You have not posted any items yet.'),
                  ),
                )
              else
                ...myListings.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ItemCard(
                      item: item,
                      seller: user,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ItemDetailScreen(itemId: item.id),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: AuthService.instance.logout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
              ),
            ],
          );
        },
      ),
    );
  }
}
