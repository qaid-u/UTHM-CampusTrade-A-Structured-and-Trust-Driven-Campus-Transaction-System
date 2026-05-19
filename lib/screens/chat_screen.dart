import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/offer_message_card.dart';
import 'package:image_picker/image_picker.dart';
import '../services/storage_service.dart';
import '../services/review_service.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;

  const ChatScreen({super.key, required this.roomId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  User? user;
  bool _sending = false;

  String? _sellerId;
  String? _buyerId;
  String? _itemTitle;
  String? _itemId;
  String? _otherUserName;
  String? _itemStatus;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;

  @override
  void initState() {
    super.initState();
    // CRITICAL: Initialize user after auth is ready
    user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      debugPrint('⚠️ ChatScreen: User not authenticated');
    }
    
    _messagesStream = FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(widget.roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markNotificationsAsRead();
      _loadChatRoomInfo();
    });
  }

  Future<void> _loadChatRoomInfo() async {
    try {
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

        setState(() {
          _sellerId = sellerId;
          _buyerId = buyerId;
          _itemTitle = itemTitle;
          _itemId = itemId;
        });

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

  Future<void> _markNotificationsAsRead() async {
    if (user == null || !mounted) return;
    try {
      await NotificationService.instance
          .markChatNotificationsAsRead(
            userId: user!.uid,
            chatRoomId: widget.roomId,
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              debugPrint('Mark notifications as read timed out');
            },
          );
    } catch (e) {
      debugPrint('Error marking notifications as read: $e');
    }
  }

  Future<void> _pickImage() async {
    if (user == null) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (picked == null) return;

      setState(() => _sending = true);
      final bytes = await picked.readAsBytes();
      
      final imageUrl = await StorageService.instance.uploadChatImage(
        roomId: widget.roomId,
        bytes: bytes,
      );

      await ChatService.sendMessage(
        roomId: widget.roomId,
        senderId: user!.uid,
        text: imageUrl,
        type: 'image',
      );

    } catch (e) {
      debugPrint('Error picking/uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    
    // CRITICAL: Check if user is authenticated
    if (user == null) {
      debugPrint('❌ ChatScreen: Cannot send message - user not authenticated');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Authentication required. Please log in again.")),
        );
      }
      return;
    }

    setState(() => _sending = true);
    _controller.clear();

    try {
      debugPrint('📤 Sending message from user: ${user!.uid}');
      debugPrint('📝 Room ID: ${widget.roomId}');
      
      await ChatService.sendMessage(
        roomId: widget.roomId,
        senderId: user!.uid,
        text: text,
        type: 'text',
      );
      
      debugPrint('✅ Message sent successfully');
    } catch (e) {
      debugPrint('❌ Failed to send message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send message: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  double _parsePrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showReviewDialog() async {
    int rating = 5;
    final reviewController = TextEditingController();
    bool submitting = false;

    // Fetch the transaction ID from the chat room metadata
    final roomDoc = await FirebaseFirestore.instance.collection('chatRooms').doc(widget.roomId).get();
    final transactionId = roomDoc.data()?['transactionId'];

    if (transactionId == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Transaction not found.')));
      return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Leave a Review'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Rate your experience out of 5 stars:'),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 32,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            rating = index + 1;
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reviewController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Any comments? (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: submitting ? null : () async {
                    setDialogState(() => submitting = true);
                    try {
                      final targetUserId = (user!.uid == _buyerId) ? _sellerId! : _buyerId!;
                      await ReviewService.submitReview(
                        transactionId: transactionId,
                        reviewerId: user!.uid,
                        revieweeId: targetUserId,
                        rating: rating,
                        comment: reviewController.text.trim(),
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Review submitted! This will be public once both parties review.'))
                        );
                      }
                    } catch (e) {
                      setDialogState(() => submitting = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                  child: submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit'),
                ),
              ],
            );
          }
        );
      }
    );
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
                  color: Colors.white.withOpacity(0.8),
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
                    return Center(child: Text("Error loading messages"));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;

                  if (docs.isEmpty) {
                    return const Center(child: Text("No messages yet"));
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d = docs[i].data();
                      final isMe = d['senderId'] == user!.uid;
                      final text = d['text']?.toString() ?? '';
                      final type = d['type']?.toString() ?? 'text';
                      final timestamp = d['createdAt'];

                      String timeStr = '';
                      if (timestamp is Timestamp) {
                        final date = timestamp.toDate();
                        timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      }

                      if (type == 'offer') {
                        return OfferMessageCard(
                          isMe: isMe,
                          offerId: d['offerId'] ?? '',
                          roomId: widget.roomId,
                          itemId: d['itemId'] ?? '',
                          itemTitle: _itemTitle ?? 'Item',
                          offerPrice: _parsePrice(d['offerPrice']),
                          status: d['offerStatus'] ?? 'pending',
                          time: timeStr,
                          isSeller: user!.uid == _sellerId,
                          isBuyer: user!.uid == _buyerId,
                        );
                      }

                      return ChatBubble(
                        isMe: isMe,
                        text: text,
                        time: timeStr,
                        type: type,
                        onReviewTap: type == 'rating_prompt' ? () => _showReviewDialog() : null,
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_outlined, color: Colors.blue),
                    onPressed: _sending ? null : _pickImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: "Type a message...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _sending ? null : sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
