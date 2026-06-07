import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'item_detail_screen.dart';
import 'premium_screen.dart';
import 'transaction_history_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  Stream<List<NotificationModel>>? _notificationsStream;

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.currentUser;
    if (user != null) {
      _notificationsStream = NotificationService.instance.getUserNotifications(
        user.uid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view notifications.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () =>
                NotificationService.instance.markAllAsRead(user.uid),
            child: const Text('Mark all'),
          ),
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StateMessage(
              icon: Icons.error_outline,
              title: 'Unable to load notifications',
              message: 'Please try again in a moment.',
              actionLabel: 'Retry',
              onAction: () => setState(() {}),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data!;

          if (notifications.isEmpty) {
            return const _StateMessage(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications yet',
              message: 'Messages, offers, and transaction updates appear here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return Dismissible(
                key: ValueKey(notification.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 18),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) => NotificationService.instance
                    .deleteNotification(notification.id),
                child: Card(
                  color: notification.isRead
                      ? Colors.white
                      : AppColors.skyTint.withValues(alpha: 0.65),
                  child: ListTile(
                    onTap: () => _openNotification(notification),
                    leading: CircleAvatar(
                      backgroundColor: notification.isRead
                          ? AppColors.skyTint
                          : AppColors.electricBlue,
                      child: Icon(
                        _iconForType(notification.type),
                        color: notification.isRead
                            ? AppColors.navy
                            : Colors.white,
                      ),
                    ),
                    title: Text(
                      notification.title.isEmpty
                          ? 'Notification'
                          : notification.title,
                      style: TextStyle(
                        fontWeight: notification.isRead
                            ? FontWeight.w700
                            : FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                    subtitle: Text(
                      notification.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _formatDate(notification.createdAt),
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!notification.isRead) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openNotification(NotificationModel notification) async {
    try {
      if (!notification.isRead) {
        await NotificationService.instance.markAsRead(notification.id);
      }
    } catch (_) {}

    if (!mounted) return;
    final relatedId = notification.relatedId.trim();

    switch (notification.route) {
      case 'chat':
        final roomId = await _resolveChatRoomId(notification);
        if (roomId.isEmpty) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatScreen(roomId: roomId)),
        );
        break;
      case 'item':
        if (relatedId.isEmpty) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ItemDetailScreen(itemId: relatedId),
          ),
        );
        break;
      case 'transaction':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TransactionHistoryScreen()),
        );
        break;
      case 'premium':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PremiumScreen()),
        );
        break;
      default:
        break;
    }
  }

  Future<String> _resolveChatRoomId(NotificationModel notification) async {
    final relatedId = notification.relatedId.trim();
    if (relatedId.isEmpty) return '';
    if (notification.relatedType != 'offer') return relatedId;

    try {
      final offerDoc = await FirebaseFirestore.instance
          .collection('offers')
          .doc(relatedId)
          .get()
          .timeout(const Duration(seconds: 5));
      final roomId = offerDoc.data()?['roomId']?.toString() ?? '';
      return roomId.isNotEmpty ? roomId : relatedId;
    } catch (_) {
      return relatedId;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'message':
        return Icons.chat_bubble_outline;
      case 'offer':
      case 'offer_accepted':
      case 'offer_rejected':
        return Icons.local_offer_outlined;
      case 'transaction_update':
      case 'transaction_completed':
      case 'receipt_uploaded':
      case 'payment_verified':
        return Icons.receipt_long_outlined;
      case 'review_prompt':
        return Icons.star_border_rounded;
      case 'premium':
        return Icons.workspace_premium_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}';
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
