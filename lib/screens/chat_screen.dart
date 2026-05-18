import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/notification_service.dart';
import '../services/chat_service.dart';
import '../widgets/feedback_helper.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/offer_message_card.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;

  const ChatScreen({super.key, required this.roomId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final user = FirebaseAuth.instance.currentUser;

  bool _sending = false;
  String? _sellerId;
  String? _buyerId;
  String? _itemTitle;

  String? _otherUserName;
  String? _itemStatus;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;

  @override
  void initState() {
    super.initState();

    _messagesStream = FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(widget.roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();

    // Load immediately for faster response
    _loadChatRoomInfo();
    _markNotificationsAsRead();
  }

  Future<void> _markNotificationsAsRead() async {
    if (user == null || !mounted) return;
    try {
      // Faster: Reduce timeout to 2 seconds
      await NotificationService.instance
          .markChatNotificationsAsRead(
            userId: user!.uid,
            chatRoomId: widget.roomId,
          )
          .timeout(
            const Duration(seconds: 2), // Reduced from 5s
            onTimeout: () {
              debugPrint('Mark notifications as read timed out');
            },
          );
    } catch (e) {
      // Silently fail - not critical for chat
      debugPrint('Error marking notifications as read: $e');
    }
  }

  Future<void> _loadChatRoomInfo() async {
    try {
      // 1. Get Chat Room Doc immediately
      final roomDoc = await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.roomId)
          .get()
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              debugPrint('Load chat room info timed out');
              throw Exception('Timeout loading chat room');
            },
          );

      if (roomDoc.exists && mounted) {
        final data = roomDoc.data();
        final sellerId = data?['sellerId'];
        final buyerId = data?['buyerId'];
        final itemId = data?['itemId'];
        final itemTitle = data?['itemTitle'] ?? 'Item';

        // Update the core layout instantly so buttons & context render without delay!
        setState(() {
          _sellerId = sellerId;
          _buyerId = buyerId;
          _itemTitle = itemTitle;
        });

        // 2. Fetch User Info & Item Status asynchronously with short timeouts
        _loadCounterpartNameAndItemStatus(sellerId, buyerId, itemId);
      }
    } catch (e) {
      debugPrint('Error loading chat room info: $e');
    }
  }

  Future<void> _loadCounterpartNameAndItemStatus(
    String? sellerId,
    String? buyerId,
    String? itemId,
  ) async {
    try {
      String? otherUserName;
      String? itemStatus;

      if (user != null && sellerId != null && buyerId != null) {
        final otherUserId = user!.uid == sellerId ? buyerId : sellerId;
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(otherUserId)
            .get()
            .timeout(const Duration(seconds: 2));
        otherUserName = userDoc.data()?['name'];
      }

      if (itemId != null) {
        final itemDoc = await FirebaseFirestore.instance
            .collection('items')
            .doc(itemId)
            .get()
            .timeout(const Duration(seconds: 2));
        itemStatus = itemDoc.data()?['status'];
      }

      if (mounted) {
        setState(() {
          if (otherUserName != null) _otherUserName = otherUserName;
          if (itemStatus != null) _itemStatus = itemStatus;
        });
      }
    } catch (e) {
      debugPrint('Error loading counterpart name or item status: $e');
    }
  }

  CollectionReference<Map<String, dynamic>> get messagesRef => FirebaseFirestore
      .instance
      .collection('chatRooms')
      .doc(widget.roomId)
      .collection('messages');

  Future<void> sendMessage() async {
    final text = _controller.text.trim();

    if (text.isEmpty) return;
    if (user == null) return;
    if (_sending) return;

    setState(() => _sending = true);

    _controller.clear();

    try {
      await ChatService.sendMessage(
        roomId: widget.roomId,
        senderId: user!.uid,
        text: text,
        type: 'text',
      );

      // NOTIFY THE OTHER USER
      await _notifyRecipient(text);
    } catch (e) {
      if (mounted) {
        FeedbackHelper.showError(context, "Message failed: $e");
      }
    }

    if (mounted) {
      setState(() => _sending = false);
    }
  }

  Future<void> _notifyRecipient(String messageText) async {
    // Determine who to notify
    String? recipientId;

    if (user!.uid == _buyerId) {
      // Buyer sent message, notify seller
      recipientId = _sellerId;
    } else if (user!.uid == _sellerId) {
      // Seller sent message, notify buyer
      recipientId = _buyerId;
    }

    if (recipientId == null || recipientId.isEmpty) {
      debugPrint('Cannot determine recipient for notification');
      return;
    }

    // Don't notify yourself
    if (recipientId == user!.uid) return;

    try {
      // Create in-app notification
      await NotificationService.instance.notifyUser(
        userId: recipientId,
        title: 'New Message',
        body: _itemTitle != null
            ? '$_itemTitle: ${messageText.length > 50 ? '${messageText.substring(0, 50)}...' : messageText}'
            : messageText,
      );

      debugPrint('Notification sent to user: $recipientId');
    } catch (e) {
      debugPrint('Failed to send notification: $e');
      // Don't throw - notification failure shouldn't break messaging
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _otherUserName ?? "Chat",
                    style: const TextStyle(fontSize: 18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_itemStatus != null && _itemStatus != 'available')
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _itemStatus == 'sold'
                          ? Colors.red.shade100
                          : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _itemStatus!.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _itemStatus == 'sold'
                            ? Colors.red.shade800
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
              ],
            ),
            if (_itemTitle != null)
              Text(
                user != null && _sellerId != null && user!.uid == _sellerId
                    ? "Selling: ${_itemTitle!}"
                    : "Buying: ${_itemTitle!}",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _messagesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          const Text("Failed to load chat"),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {}); // Retry
                            },
                            child: const Text("Retry"),
                          ),
                        ],
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    // Show skeleton UI instead of spinner for perceived speed
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: 3, // Show 3 skeleton messages
                      itemBuilder: (_, i) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: i % 2 == 0
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              Container(
                                width: 150 + (i * 30),
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }

                  final docs = snapshot.data!.docs;

                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "No messages yet",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Say hello! \\ud83d\\udc4b",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d = docs[i].data();
                      final timestamp = docs[i].data()['createdAt'];

                      final isMe = d['senderId'] == user!.uid;
                      final text = d['text']?.toString() ?? '';

                      final type = d['type']?.toString() ?? 'text';

                      if (type == 'offer') {
                        return OfferMessageCard(
                          isMe: isMe,
                          offerId: d['offerId'] ?? '',
                          roomId: widget.roomId,
                          itemId: d['itemId'] ?? '',
                          itemTitle: _itemTitle ?? 'Item',
                          offerPrice: _parsePrice(d['offerPrice']),
                          status: d['offerStatus'] ?? 'pending',
                          time: _formatTimestamp(timestamp),
                          isSeller: user!.uid == _sellerId,
                          isBuyer: user!.uid == _buyerId,
                        );
                      }

                      return ChatBubble(
                        isMe: isMe,
                        text: text,
                        time: _formatTimestamp(timestamp),
                        type: type,
                      );
                    },
                  );
                },
              ),
            ),

            // ---------------- INPUT BAR
            SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => sendMessage(),
                          maxLines: null,
                          decoration: InputDecoration(
                            hintText: "Type a message...",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                ),
                          onPressed: _sending ? null : sendMessage,
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(Object? timestampValue) {
    if (timestampValue == null) return '';

    DateTime date;
    if (timestampValue is Timestamp) {
      date = timestampValue.toDate();
    } else if (timestampValue is DateTime) {
      date = timestampValue;
    } else {
      return '';
    }

    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      // Today - show time
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      // Show date
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  double _parsePrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
