import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'premium_badge.dart';
import '../services/subscription_service.dart';

class ChatRoomTile extends StatefulWidget {
  final Map<String, dynamic> room;
  final String roomId;
  final String currentUserId;
  final VoidCallback onTap;

  const ChatRoomTile({
    super.key,
    required this.room,
    required this.roomId,
    required this.currentUserId,
    required this.onTap,
  });

  @override
  State<ChatRoomTile> createState() => _ChatRoomTileState();
}

class _ChatRoomTileState extends State<ChatRoomTile> {
  String _otherUserName = 'Loading...';
  String _itemStatus = '';
  bool _isLoading = true;
  bool _otherIsPremium = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final sellerId = widget.room['sellerId'];
      final buyerId = widget.room['buyerId'];
      final itemId = widget.room['itemId'];

      final otherUserId = widget.currentUserId == sellerId ? buyerId : sellerId;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(otherUserId)
          .get();
      final itemDoc = await FirebaseFirestore.instance
          .collection('items')
          .doc(itemId)
          .get();

      if (mounted) {
        setState(() {
          _otherUserName = userDoc.data()?['name'] ?? 'Unknown User';
          _otherIsPremium =
              SubscriptionService.isPremiumActive(userDoc.data());
          _itemStatus = itemDoc.data()?['status'] ?? 'available';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _otherUserName = 'Unknown User';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemTitle = widget.room['itemTitle'] ?? 'Item Chat';
    final itemThumbnail = widget.room['itemThumbnail'] ?? '';
    final lastMessage = widget.room['lastMessage'] ?? 'No messages yet';
    final lastMessageType = widget.room['lastMessageType'] ?? 'text';
    final updatedAt = widget.room['updatedAt'];

    final unreadCounts = widget.room['unreadCounts'] as Map<String, dynamic>?;
    final unreadCount = unreadCounts != null
        ? (unreadCounts[widget.currentUserId] ?? 0)
        : 0;

    String displayMessage = lastMessage;
    if (lastMessageType == 'offer') {
      displayMessage = 'New Offer: $lastMessage';
    } else if (lastMessageType == 'system') {
      displayMessage = '[System] $lastMessage';
    }

    final isSeller = widget.currentUserId == widget.room['sellerId'];

    return ListTile(
      leading: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade200,
          image: itemThumbnail.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(itemThumbnail),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: itemThumbnail.isEmpty
            ? const Icon(Icons.image_not_supported)
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _isLoading ? itemTitle : '$_otherUserName • $itemTitle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: unreadCount > 0
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
          if (_otherIsPremium) ...[                
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: PremiumBadge(compact: true),
            ),
            const SizedBox(width: 4),
          ],
          _buildStatusBadge(),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isSeller && !_isLoading)
            Text(
              'Seller: $_otherUserName',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          Text(
            displayMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: unreadCount > 0 ? Colors.black87 : Colors.grey.shade600,
              fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildTimestamp(updatedAt),
          if (unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      onTap: widget.onTap,
    );
  }

  Widget _buildTimestamp(Object? timestampValue) {
    if (timestampValue == null) return const SizedBox.shrink();

    DateTime time;
    if (timestampValue is Timestamp) {
      time = timestampValue.toDate();
    } else if (timestampValue is DateTime) {
      time = timestampValue;
    } else {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final difference = now.difference(time);
    String timeText;

    if (difference.inDays == 0) {
      timeText =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      timeText = 'Yesterday';
    } else if (difference.inDays < 7) {
      timeText = '${difference.inDays}d';
    } else {
      timeText = '${time.day}/${time.month}';
    }

    return Text(
      timeText,
      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
    );
  }

  Widget _buildStatusBadge() {
    if (_isLoading) return const SizedBox.shrink();

    String label = '';
    Color bgColor = Colors.transparent;
    Color textColor = Colors.transparent;

    if (_itemStatus == 'available') {
      label = 'AVAILABLE';
      bgColor = Colors.blue.shade50;
      textColor = Colors.blue.shade800;
    } else if (_itemStatus == 'sold') {
      final transactionId = widget.room['transactionId'];
      final hasBought = transactionId != null && transactionId.toString().isNotEmpty;

      if (hasBought) {
        if (widget.currentUserId == widget.room['buyerId']) {
          label = 'BOUGHT BY YOU';
        } else {
          label = 'SOLD BY YOU';
        }
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
      } else {
        label = 'SOLD TO OTHERS';
        bgColor = Colors.red.shade100;
        textColor = Colors.red.shade800;
      }
    } else {
      label = _itemStatus.toUpperCase();
      bgColor = Colors.orange.shade100;
      textColor = Colors.orange.shade800;
    }

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}
