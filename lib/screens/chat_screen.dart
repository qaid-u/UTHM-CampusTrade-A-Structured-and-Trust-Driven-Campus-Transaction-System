import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/offer_service.dart';
import '../services/storage_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/offer_message_card.dart';
import 'transaction_history_screen.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;

  const ChatScreen({super.key, required this.roomId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _imagePicker = ImagePicker();
  final user = FirebaseAuth.instance.currentUser;
  bool _sending = false;
  bool _uploadingImage = false;
  Timer? _typingTimer;

  String? _sellerId;
  String? _buyerId;
  String? _itemTitle;
  String? _itemId;
  String? _otherUserName;
  String? _itemStatus;
  bool _accessDenied = false;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _transactionStream;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _roomStream;

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
    _transactionStream = FirebaseFirestore.instance
        .collection('transactions')
        .where('roomId', isEqualTo: widget.roomId)
        .limit(1)
        .snapshots();
    _roomStream = FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(widget.roomId)
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
        final participants = List<String>.from(data?['participantIds'] ?? []);

        if (user == null || !participants.contains(user!.uid)) {
          setState(() => _accessDenied = true);
          return;
        }

        setState(() {
          _sellerId = sellerId;
          _buyerId = buyerId;
          _itemTitle = itemTitle;
          _itemId = itemId;
        });

        await ChatService.markRoomRead(roomId: widget.roomId, userId: user!.uid);

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

  Future<void> sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || user == null || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      await ChatService.sendMessage(
        roomId: widget.roomId,
        senderId: user!.uid,
        text: text,
        type: 'text',
      );
    } catch (e) {
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

  Future<void> _sendImage() async {
    if (user == null || _uploadingImage) return;

    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploadingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await StorageService.instance.uploadChatImage(
        roomId: widget.roomId,
        senderId: user!.uid,
        bytes: bytes,
      );
      await ChatService.sendImageMessage(
        roomId: widget.roomId,
        senderId: user!.uid,
        imageUrl: url,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send photo: $e')));
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  void _handleTyping(String value) {
    if (user == null) return;
    ChatService.setTyping(
      roomId: widget.roomId,
      userId: user!.uid,
      isTyping: value.trim().isNotEmpty,
    );
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      ChatService.setTyping(
        roomId: widget.roomId,
        userId: user!.uid,
        isTyping: false,
      );
    });
  }

  Future<void> _makeOfferFromChat() async {
    if (user == null || _buyerId == null || _sellerId == null || _itemId == null) {
      return;
    }

    if (user!.uid != _buyerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the buyer can make an offer.')),
      );
      return;
    }

    if (_itemStatus != null && _itemStatus != 'available') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This item is no longer accepting offers.')),
      );
      return;
    }

    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make Offer'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Offer price',
            prefixText: 'RM ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final price = double.tryParse(controller.text.trim());
              if (price == null || price <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter an offer greater than 0.')),
                );
                return;
              }
              Navigator.pop(context, price);
            },
            child: const Text('Send Offer'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (result == null) return;

    try {
      await OfferService.createOffer(
        roomId: widget.roomId,
        itemId: _itemId!,
        itemTitle: _itemTitle ?? 'Item',
        buyerId: _buyerId!,
        sellerId: _sellerId!,
        price: result,
      );

      await NotificationService.instance.notifyUser(
        userId: _sellerId!,
        title: 'New Offer',
        body: 'RM ${result.toStringAsFixed(2)} for ${_itemTitle ?? 'your item'}',
        type: 'offer',
        itemId: _itemId,
        chatRoomId: widget.roomId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send offer: $e')),
      );
    }
  }

  double _parsePrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  bool _isExpiredOffer(dynamic timestamp) {
    if (timestamp is! Timestamp) return false;
    final createdAt = timestamp.toDate();
    return DateTime.now().difference(createdAt).inHours >= 48;
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final days = today.difference(target).inDays;

    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _deliveryStatus(Map<String, dynamic> data) {
    if (user == null) return '';
    final otherId = user!.uid == _sellerId ? _buyerId : _sellerId;
    final readBy = List<String>.from(data['readBy'] ?? []);
    final deliveredTo = List<String>.from(data['deliveredTo'] ?? []);
    if (otherId != null && readBy.contains(otherId)) return 'Seen';
    if (otherId != null && deliveredTo.contains(otherId)) return 'Delivered';
    return 'Sent';
  }

  String _friendlyTransactionStatus(String status) {
    switch (status) {
      case 'payment_processing':
        return 'Awaiting seller confirmation';
      case 'accepted':
        return 'Meetup and payment pending';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  String _roleLabel() {
    if (user == null) return '';
    if (user!.uid == _sellerId) return 'Seller';
    if (user!.uid == _buyerId) return 'Buyer';
    return '';
  }

  void _showFullImage(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Icon(Icons.broken_image, color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                color: Colors.white,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateSeparator(String label) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _typingIndicator() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _roomStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data == null || user == null) return const SizedBox.shrink();
        final otherId = user!.uid == _sellerId ? _buyerId : _sellerId;
        final typing = Map<String, dynamic>.from(data['typing'] ?? {});
        if (otherId == null || typing[otherId] != true) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_otherUserName ?? 'User'} is typing...',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        );
      },
    );
  }

  Widget _transactionBanner() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _transactionStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final tx = snapshot.data!.docs.first.data();
        final status = (tx['status'] ?? 'accepted').toString();
        final payment = (tx['paymentMethod'] ?? '').toString();
        final price = _parsePrice(tx['finalPrice'] ?? tx['offerPrice']);
        final itemStatus = (_itemStatus ?? '').toUpperCase();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.blue.shade50,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Transaction Active',
                            style: TextStyle(
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (itemStatus.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              itemStatus,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const TransactionHistoryScreen(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text('View'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        'RM ${price.toStringAsFixed(2)}',
                        if (payment.isNotEmpty) payment,
                        _friendlyTransactionStatus(status),
                      ].join(' | '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _messageComposer() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _roomStream,
      builder: (context, snapshot) {
        final room = snapshot.data?.data();
        final blockedBy = List<String>.from(room?['blockedBy'] ?? []);

        if (blockedBy.isNotEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: Colors.white,
            child: Row(
              children: [
                Icon(Icons.block_rounded, color: Colors.red.shade600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This chat is blocked.',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(8),
          color: Colors.white,
          child: Row(
            children: [
              if (user!.uid == _buyerId &&
                  (_itemStatus == null || _itemStatus == 'available')) ...[
                IconButton(
                  tooltip: 'Make offer',
                  onPressed: _makeOfferFromChat,
                  color: Colors.blueGrey.shade500,
                  icon: const Icon(Icons.local_offer_outlined),
                ),
              ],
              IconButton(
                tooltip: 'Send photo',
                onPressed: _uploadingImage ? null : _sendImage,
                color: Colors.blueGrey.shade500,
                icon: _uploadingImage
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_outlined),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: _handleTyping,
                  decoration: InputDecoration(
                    hintText: "Type a message...",
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide(color: Colors.blue.shade100),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide(color: Colors.blue.shade100),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide(color: Colors.blue.shade300),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                color: Colors.blue.shade800,
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
        );
      },
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    if (user != null) {
      ChatService.setTyping(
        roomId: widget.roomId,
        userId: user!.uid,
        isTyping: false,
      );
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    if (_accessDenied) {
      return const Scaffold(
        body: Center(child: Text("You do not have access to this chat.")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEFF3FA),
        foregroundColor: const Color(0xFF0B2F6B),
        elevation: 0,
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
              ],
            ),
            if (_itemTitle != null)
              Text(
                [
                  user != null && _sellerId != null && user!.uid == _sellerId
                      ? "Selling: ${_itemTitle!}"
                      : "Buying: ${_itemTitle!}",
                  if (_roleLabel().isNotEmpty) _roleLabel(),
                ].join(' | '),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey.shade600,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'report') _reportChat();
              if (value == 'block') _blockChat();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'report',
                child: Text('Report chat'),
              ),
              PopupMenuItem(
                value: 'block',
                child: Text('Block chat'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _transactionBanner(),
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
                      final messageDate = timestamp is Timestamp
                          ? timestamp.toDate()
                          : DateTime.now();
                      final nextDate = i + 1 < docs.length
                          ? docs[i + 1].data()['createdAt']
                          : null;
                      final showDate = nextDate is! Timestamp ||
                          !_isSameDate(messageDate, nextDate.toDate());

                      final bubble = type == 'offer'
                          ? OfferMessageCard(
                              isMe: isMe,
                              offerId: d['offerId'] ?? '',
                              roomId: widget.roomId,
                              itemId: d['itemId'] ?? '',
                              itemTitle: _itemTitle ?? 'Item',
                              buyerId: _buyerId ?? '',
                              sellerId: _sellerId ?? '',
                              offerPrice: _parsePrice(d['offerPrice']),
                              status: d['offerStatus'] ?? 'pending',
                              time: timeStr,
                              isExpired: _isExpiredOffer(timestamp),
                              isSeller: user!.uid == _sellerId,
                              isBuyer: user!.uid == _buyerId,
                              isCounterOffer:
                                  d['senderId']?.toString() == _sellerId,
                            )
                          : ChatBubble(
                              isMe: isMe,
                              text: text,
                              time: timeStr,
                              type: type,
                              imageUrl: d['mediaUrl']?.toString() ?? '',
                              deliveryStatus: isMe ? _deliveryStatus(d) : '',
                              onImageTap: d['mediaUrl'] == null
                                  ? null
                                  : () => _showFullImage(
                                        d['mediaUrl'].toString(),
                                      ),
                            );

                      return Column(
                        children: [
                          if (showDate) _dateSeparator(_dateLabel(messageDate)),
                          bubble,
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            _typingIndicator(),
            _messageComposer(),
          ],
        ),
      ),
    );
  }

  Future<void> _reportChat() async {
    if (user == null) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Describe what happened',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;

    try {
      await ChatService.reportChat(
        roomId: widget.roomId,
        reporterId: user!.uid,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat reported.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to report chat: $e')));
    }
  }

  Future<void> _blockChat() async {
    if (user == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block this chat?'),
        content: const Text('You and the other user will no longer be able to send messages here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ChatService.blockChat(roomId: widget.roomId, userId: user!.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat blocked.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to block chat: $e')));
    }
  }
}
