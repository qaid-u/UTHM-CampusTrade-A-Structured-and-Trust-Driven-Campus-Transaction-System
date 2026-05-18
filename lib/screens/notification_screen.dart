import 'package:flutter/material.dart';

import '../models/notification_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

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
      _notificationsStream = NotificationService.instance.getUserNotifications(user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<NotificationModel>>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load notifications.'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data!;

          if (notifications.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final notification = notifications[index];

              return Card(
                child: ListTile(
                  onTap: notification.isRead
                      ? null
                      : () => NotificationService.instance.markAsRead(
                          notification.id,
                        ),
                  leading: CircleAvatar(
                    backgroundColor: notification.isRead
                        ? AppColors.skyTint
                        : AppColors.red,
                    child: Icon(
                      notification.isRead
                          ? Icons.notifications_none_rounded
                          : Icons.notifications_active_rounded,
                      color: notification.isRead
                          ? AppColors.navy
                          : Colors.white,
                    ),
                  ),
                  title: Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: notification.isRead
                          ? FontWeight.w700
                          : FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                  subtitle: Text(notification.body),
                  trailing: Text(
                    '${notification.createdAt.day}/${notification.createdAt.month}',
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontWeight: FontWeight.w700,
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
}
