import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';
import 'chats_screen.dart';
import 'profile_screen.dart';
import 'add_item_screen.dart';
import 'transaction_history_screen.dart';

import '../theme/app_theme.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();

    /// 🔥 FIX: prevent re-creation issues
    pages = const [
      HomeScreen(),
      ChatsScreen(),
      TransactionHistoryScreen(),
      ProfileScreen(),
    ];

    _generateSilentDemoData();
  }

  Future<void> _generateSilentDemoData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final db = FirebaseFirestore.instance;
      final roomDoc = await db.collection('chatRooms').doc('mock_room_123').get();
      
      // If already exists, do not overwrite or re-create
      if (roomDoc.exists) {
        debugPrint('Silent Demo Data: Already exists, skipping creation.');
        return;
      }

      debugPrint('Silent Demo Data: Generating test transaction and chat room documents...');

      // 1. Ensure mock buyer exists
      await db.collection('users').doc('mock_buyer_123').set({
        'uid': 'mock_buyer_123',
        'name': 'Ahmad (Test Buyer)',
        'studentId': 'AI210099',
        'email': 'ahmad_test@student.uthm.edu.my',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. Ensure mock item exists and status is available
      await db.collection('items').doc('mock_item_123').set({
        'id': 'mock_item_123',
        'title': 'Test UTHM T-Shirt',
        'description': 'A beautiful test shirt for CampusTrade testing.',
        'price': 50.0,
        'sellerId': user.uid,
        'images': ['https://picsum.photos/200'],
        'status': 'available',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3. Ensure mock chat room exists
      await db.collection('chatRooms').doc('mock_room_123').set({
        'id': 'mock_room_123',
        'itemId': 'mock_item_123',
        'itemTitle': 'Test UTHM T-Shirt',
        'itemThumbnail': 'https://picsum.photos/200',
        'buyerId': 'mock_buyer_123',
        'sellerId': user.uid,
        'lastMessage': 'RM 50.00',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 4. Create a mock offer document in pending state
      await db.collection('offers').doc('mock_offer_123').set({
        'id': 'mock_offer_123',
        'roomId': 'mock_room_123',
        'itemId': 'mock_item_123',
        'buyerId': 'mock_buyer_123',
        'sellerId': user.uid,
        'price': 50.0,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 5. Add the offer message inside the chat room messages subcollection
      await db
          .collection('chatRooms')
          .doc('mock_room_123')
          .collection('messages')
          .doc('mock_msg_123')
          .set({
        'id': 'mock_msg_123',
        'senderId': 'mock_buyer_123',
        'type': 'offer',
        'text': 'RM 50.00',
        'offerId': 'mock_offer_123',
        'offerPrice': 50.0,
        'offerStatus': 'pending',
        'itemId': 'mock_item_123',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('Silent Demo Data: Successfully populated test documents!');
    } catch (e) {
      debugPrint('Silent Demo Data Error: $e');
    }
  }

  void _onTab(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  Future<void> _openSell() async {
    /// 🔥 FIX: prevent navigation issues if widget unmounted
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddItemScreen()),
    );

    /// optional safety refresh after returning
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),

      floatingActionButton: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x3DE3223A),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: _openSell,
          child: const Icon(Icons.add_rounded, size: 30),
        ),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: Container(
        height: 78,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.navGlow,
        ),

        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home, "Home", 0),
            _navItem(Icons.chat_bubble, "Chats", 1),

            const SizedBox(width: 42),

            _navItem(Icons.receipt_long, "Transactions", 2),
            _navItem(Icons.person, "Profile", 3),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _index == index;

    return GestureDetector(
      onTap: () => _onTab(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? AppColors.navy : AppColors.slate,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.red : AppColors.slate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
