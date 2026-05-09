import 'package:flutter/material.dart';

import '../services/database_service.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: AnimatedBuilder(
        animation: DatabaseService.instance,
        builder: (context, _) {
          final notifications = DatabaseService.instance.notifications;
          if (notifications.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.notifications_rounded),
                  ),
                  title: Text(notification.title),
                  subtitle: Text(notification.body),
                  trailing: Text(_date(notification.createdAt)),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: notifications.length,
          );
        },
      ),
    );
  }

  String _date(DateTime date) => '${date.day}/${date.month}';
}
