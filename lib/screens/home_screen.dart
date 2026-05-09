import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../models/item_model.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/recommendation_service.dart';
import '../widgets/category_chip.dart';
import '../widgets/item_card.dart';
import 'add_item_screen.dart';
import 'item_detail_screen.dart';
import 'notification_screen.dart';
import 'profile_screen.dart';
import 'transaction_history_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const AddItemScreen(),
      const TransactionHistoryScreen(),
      const NotificationScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_rounded),
            label: 'Market',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_box_rounded),
            label: 'Sell',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'Deals',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_rounded),
            label: 'Alerts',
          ),
          NavigationDestination(icon: Icon(Icons.person_rounded), label: 'Me'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  String? _category;
  String? _viewedCategory;
  String? _meetupPreference = meetupLocations.first;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DatabaseService.instance,
      builder: (context, _) {
        final user = AuthService.instance.currentUser!;
        final items = _filteredItems(DatabaseService.instance.items);
        final featured = items.where((item) => item.isFeatured).toList();
        final recent = [...items]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final recommended = RecommendationService().recommend(
          items: DatabaseService.instance.items,
          viewedCategory: _viewedCategory,
          meetupLocation: _meetupPreference,
          currentUserId: user.id,
        );
        return Scaffold(
          appBar: AppBar(
            title: const Text('UTHMCampus Trade'),
            actions: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationScreen()),
                ),
                icon: const Icon(Icons.notifications_rounded),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search textbooks, calculators, hostel items...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _meetupPreference,
                  decoration: const InputDecoration(
                    labelText: 'Preferred meetup location',
                    prefixIcon: Icon(Icons.place_rounded),
                  ),
                  items: meetupLocations
                      .map(
                        (location) => DropdownMenuItem(
                          value: location,
                          child: Text(location),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _meetupPreference = value),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      CategoryChip(
                        label: 'All',
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                      const SizedBox(width: 8),
                      ...categories.map(
                        (category) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: CategoryChip(
                            label: category,
                            selected: _category == category,
                            onSelected: (_) => setState(() {
                              _category = category;
                              _viewedCategory = category;
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (items.isEmpty)
                  _emptyState()
                else ...[
                  _section('Featured listings'),
                  _itemGrid(
                    featured.isEmpty ? items.take(2).toList() : featured,
                  ),
                  const SizedBox(height: 22),
                  _section('Recent listings'),
                  _itemGrid(recent),
                  const SizedBox(height: 22),
                  _section('Recommended For You'),
                  Text(
                    'Recommended based on your browsing activity and campus trading preferences.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  _itemGrid(
                    recommended.isEmpty ? recent.take(3).toList() : recommended,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<ItemModel> _filteredItems(List<ItemModel> items) {
    final query = _search.text.trim().toLowerCase();
    return items.where((item) {
      final matchesCategory = _category == null || item.category == _category;
      final matchesSearch =
          query.isEmpty ||
          item.title.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _itemGrid(List<ItemModel> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items.map((item) {
            final seller = DatabaseService.instance.findUser(item.sellerId)!;
            return SizedBox(
              width: width,
              child: ItemCard(
                item: item,
                seller: seller,
                onTap: () {
                  setState(() => _viewedCategory = item.category);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ItemDetailScreen(itemId: item.id),
                    ),
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _emptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(Icons.inventory_2_rounded, size: 54),
            const SizedBox(height: 12),
            Text(
              'No listings yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text('Post the first item for the UTHM community.'),
          ],
        ),
      ),
    );
  }
}
