import 'package:flutter/material.dart';

import '../models/message_model.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.itemId});

  final String itemId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _message = TextEditingController();
  final _suggestions = const [
    'Is this still available?',
    'Can we meet at the library?',
    'Can you reduce the price?',
  ];

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = DatabaseService.instance.findItem(widget.itemId)!;
    final seller = DatabaseService.instance.findUser(item.sellerId)!;
    final currentUser = AuthService.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(title: Text('Chat with ${seller.name}')),
      body: AnimatedBuilder(
        animation: DatabaseService.instance,
        builder: (context, _) {
          final messages = DatabaseService.instance.messages
              .where((message) => message.itemId == widget.itemId)
              .toList();
          return Column(
            children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: _suggestions
                      .map(
                        (text) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(text),
                            onPressed: () => _send(text),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              Expanded(
                child: messages.isEmpty
                    ? const Center(
                        child: Text('Start the conversation safely.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final mine = message.senderId == currentUser.id;
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 290),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: mine
                                    ? const Color(0xFF0B2D5B)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE5EAF1),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.text,
                                    style: TextStyle(
                                      color: mine
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _time(message.sentAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: mine
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _message,
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: () => _send(_message.text),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _send(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final item = DatabaseService.instance.findItem(widget.itemId)!;
    final current = AuthService.instance.currentUser!;
    await DatabaseService.instance.addMessage(
      MessageModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        itemId: widget.itemId,
        senderId: current.id,
        receiverId: item.sellerId == current.id ? 'buyer' : item.sellerId,
        text: clean,
        sentAt: DateTime.now(),
      ),
    );
    _message.clear();
  }

  String _time(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
