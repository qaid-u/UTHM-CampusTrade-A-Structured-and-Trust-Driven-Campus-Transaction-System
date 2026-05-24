import 'package:flutter/material.dart';

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
