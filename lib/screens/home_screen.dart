import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/item_model.dart';
import '../models/notification_model.dart';
import '../services/auth_service.dart';
import '../services/app_config_service.dart';
import '../services/notification_service.dart';
import '../services/item_service.dart';
import '../widgets/category_chip.dart';
import '../widgets/item_card.dart';
import 'item_detail_screen.dart';
import 'notification_screen.dart';
import 'add_item_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();

  String? _category;
  String? _meetupLocation;

  List<ItemModel> _items = [];
  bool _loading = true;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;

  // Add debouncing to prevent rapid reloads
  bool _isReloading = false;
  DateTime? _lastLoadTime;
  Stream<List<NotificationModel>>? _notificationsStream;

  List<String> get _categories => AppConfigService.instance.categories;

  @override
  void initState() {
    super.initState();
    // OPTIMIZED: Wait for first frame, then check auth before loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = AuthService.instance.currentUser;
      if (user != null) {
        // Only initialize notifications if user is authenticated
        _notificationsStream = NotificationService.instance.getUserNotifications(user.uid);
        // Load items for authenticated user
        _loadItems();
      } else {
        // User not authenticated yet, show loading
        if (mounted) {
          setState(() {
            _loading = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadItems({bool refresh = false}) async {
    // CRITICAL: Check if user is authenticated before making Firestore calls
    final user = AuthService.instance.currentUser;
    if (user == null) {
      debugPrint('⚠️ User not authenticated, skipping item load');
      return;
    }

    // Prevent rapid successive calls (debounce) - but allow first load
    final now = DateTime.now();
    if (_lastLoadTime != null &&
        now.difference(_lastLoadTime!).inMilliseconds < 300 &&
        !_items.isEmpty) {
      // Always allow if no items
      return;
    }
    _lastLoadTime = now;

    if (refresh) {
      _lastDocument = null;
      _hasMore = true;
      // Don't clear items immediately - wait for new data
    }

    if (!_hasMore || _isReloading) return;

    // Set loading state
    if (mounted) {
      setState(() {
        _isReloading = true;
        // Only show full-screen loader on initial load
        if (_items.isEmpty) {
          _loading = true;
        }
      });
    }

    try {
      // Use smaller batch size for faster initial load
      final batchSize = 15;

      debugPrint(
        '🔍 Loading items: refresh=$refresh, category=$_category, location=$_meetupLocation',
      );
      debugPrint('👤 User: ${user.uid}');


      // Add timeout to prevent hanging
      final result = await ItemService.instance
          .getHomeFeed(
            category: _category,
            meetupLocation: _meetupLocation,
            limit: batchSize,
            lastDocument: _lastDocument,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception(
                'Request timed out. Please check your connection.',
              );
            },
          );

      final items = result['items'] as List<ItemModel>;
      final lastDoc = result['lastDocument'] as DocumentSnapshot?;

      if (!mounted) return;

      debugPrint('Loaded ${items.length} items successfully');

      if (items.length < batchSize) {
        _hasMore = false;
      }

      if (lastDoc != null) {
        _lastDocument = lastDoc;
      }

      setState(() {
        if (refresh) {
          _items = items; // Replace all items on refresh
        } else {
          _items.addAll(items); // Append on pagination
        }
        _loading = false;
        _isReloading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _isReloading = false;
      });

      // DETAILED ERROR LOGGING
      debugPrint('❌ Error loading items: $e');
      debugPrint('Error type: ${e.runtimeType}');
      if (e.toString().contains('permission-denied')) {
        debugPrint('🔒 PERMISSION DENIED - Check:');
        debugPrint('  1. User authenticated: ${user.uid}');
        debugPrint('  2. Firestore rules deployed');
        debugPrint('  3. Rules allow read on items collection');
      }

      // Show user-friendly error message
      if (_items.isEmpty) {
        // Only show snackbar if we have no items to display
        if (e.toString().contains('timed out')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Connection timeout. Pull down to refresh.'),
                  ),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _loadItems(refresh: true),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Failed to load items. Please try again.'),
                  ),
                ],
              ),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _loadItems(refresh: true),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _refreshData() async {
    await _loadItems(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Session expired. Please login again.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Campus Trade"),
        actions: [_notificationButton(user.uid)],
      ),

      body: Column(
        children: [
          _heroHeader(),
          _searchBar(),
          _categoryBar(),
          const SizedBox(height: 10),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              child: _buildItemsList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    // Initial loading - show skeleton or spinner
    if (_loading && _items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading items...'),
          ],
        ),
      );
    }

    final filtered = _filter(_items);

    if (filtered.isEmpty && !_loading) {
      return _emptyState();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (!_isReloading &&
            _hasMore &&
            scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent) {
          _loadItems();
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: filtered.length + (_hasMore && _isReloading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= filtered.length) {
            // Loading indicator at bottom
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: _isReloading
                    ? const CircularProgressIndicator()
                    : const SizedBox.shrink(),
              ),
            );
          }

          final item = filtered[index];

          return ItemCard(
            item: item,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemDetailScreen(itemId: item.id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ---------------- SEARCH FILTER
  List<ItemModel> _filter(List<ItemModel> items) {
    final q = _search.text.trim().toLowerCase();

    if (q.isEmpty) return items;

    return items.where((i) {
      final title = i.title.toLowerCase();
      final desc = i.description.toLowerCase();

      return title.contains(q) || desc.contains(q);
    }).toList();
  }

  // ---------------- UI COMPONENTS

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search items...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: _showLocationFilter,
          ),
        ),
      ),
    );
  }

  void _onFilterChange({String? category}) {
    setState(() {
      _category = category;
      // Don't clear items - show existing items while loading new ones
      _lastDocument = null;
      _hasMore = true;
    });

    // Show loading feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            category != null
                ? "Filtering by: $category"
                : "Showing all categories",
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.blue.shade700,
        ),
      );
    }

    _loadItems(refresh: true);
  }

  Future<void> _showLocationFilter() async {
    final locations = AppConfigService.instance.meetupLocations;

    final selected = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) {
        return ListView(
          children: [
            ListTile(
              title: const Text("All locations"),
              onTap: () => Navigator.pop(context, null),
            ),
            ...locations.map(
              (loc) => ListTile(
                title: Text(loc),
                onTap: () => Navigator.pop(context, loc),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _meetupLocation = selected;
      _items.clear();
      _lastDocument = null;
      _hasMore = true;
    });
    _loadItems(refresh: true);
  }

  Widget _heroHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        "Buy & sell safely in your campus",
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _categoryBar() {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          CategoryChip(
            label: 'All',
            selected: _category == null,
            onSelected: (_) => _onFilterChange(),
          ),
          const SizedBox(width: 8),
          ..._categories.map(
            (c) => CategoryChip(
              label: c,
              selected: _category == c,
              onSelected: (_) => _onFilterChange(category: c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    // Check if filters are active
    final hasActiveFilters = _category != null || _meetupLocation != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Icon(
              hasActiveFilters
                  ? Icons.filter_list_off
                  : Icons.shopping_bag_outlined,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 24),

            // Main message
            Text(
              hasActiveFilters ? "No Items Found" : "No Items for Sale Yet",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),

            // Subtitle
            Text(
              hasActiveFilters
                  ? "Try adjusting your filters\nor search for something else."
                  : "Be the first to sell something!\nList your items and reach thousands of students.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            // Call-to-action button (only show when no filters)
            if (!hasActiveFilters)
              ElevatedButton.icon(
                onPressed: () {
                  // Navigate to add item screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddItemScreen()),
                  );
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text("Start Selling Now"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

            // Clear filters button (only show when filters active)
            if (hasActiveFilters)
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _category = null;
                    _meetupLocation = null;
                    _items.clear();
                    _lastDocument = null;
                    _hasMore = true;
                  });
                  _loadItems(refresh: true);
                },
                icon: const Icon(Icons.clear_all, size: 20),
                label: const Text("Clear All Filters"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Helpful tip
            if (!hasActiveFilters)
              Text(
                "💡 Tip: Textbooks, electronics, and clothes sell fast!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _notificationButton(String userId) {
    return StreamBuilder(
      stream: _notificationsStream,
      builder: (context, snapshot) {
        final list = snapshot.data ?? [];

        final count = list.where((n) => n.isRead == false).length;

        return IconButton(
          icon: Stack(
            children: [
              const Icon(Icons.notifications),
              if (count > 0)
                Positioned(
                  right: 0,
                  child: CircleAvatar(
                    radius: 8,
                    child: Text("$count", style: const TextStyle(fontSize: 10)),
                  ),
                ),
            ],
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            );
          },
        );
      },
    );
  }
}
