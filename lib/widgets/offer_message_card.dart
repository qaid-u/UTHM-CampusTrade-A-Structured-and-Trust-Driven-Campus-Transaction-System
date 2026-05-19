import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/notification_service.dart';
import '../services/offer_service.dart';

class OfferMessageCard extends StatefulWidget {
  final bool isMe;
  final String offerId;
  final String roomId;
  final String itemId;
  final String itemTitle;
  final String buyerId;
  final String sellerId;
  final double offerPrice;
  final String status;
  final String time;
  final bool isExpired;
  final bool isSeller;
  final bool isBuyer;
  final bool isCounterOffer;

  const OfferMessageCard({
    super.key,
    required this.isMe,
    required this.roomId,
    required this.itemId,
    required this.offerId,
    required this.itemTitle,
    required this.buyerId,
    required this.sellerId,
    required this.offerPrice,
    required this.status,
    required this.time,
    this.isExpired = false,
    required this.isSeller,
    required this.isBuyer,
    this.isCounterOffer = false,
  });

  @override
  State<OfferMessageCard> createState() => _OfferMessageCardState();
}

class _OfferMessageCardState extends State<OfferMessageCard> {
  bool _isLoading = false;

  Future<void> _handleOfferAction(String action) async {
    setState(() => _isLoading = true);

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      await OfferService.updateOfferStatus(
        offerId: widget.offerId,
        roomId: widget.roomId,
        status: action,
        actionUserId: userId,
      );

      try {
        final notifyUserId = userId == widget.buyerId
            ? widget.sellerId
            : widget.buyerId;
        await NotificationService.instance.notifyUser(
          userId: notifyUserId,
          title: action == 'accepted'
              ? 'Offer accepted'
              : action == 'rejected'
                  ? 'Offer rejected'
                  : 'Offer cancelled',
          body:
              'The offer for ${widget.itemTitle} was ${action.replaceAll('_', ' ')}.',
          type: 'offer',
          itemId: widget.itemId,
          chatRoomId: widget.roomId,
        );
      } catch (e) {
        debugPrint('Offer notification failed: $e');
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyOfferError(e))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyOfferError(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _counterOffer() async {
    final controller = TextEditingController();
    final counterPrice = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Counter Offer'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Counter price',
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
              final value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0) return;
              Navigator.pop(context, value);
            },
            child: const Text('Send Counter'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (counterPrice == null) return;

    setState(() => _isLoading = true);
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      await OfferService.counterOffer(
        offerId: widget.offerId,
        roomId: widget.roomId,
        actionUserId: userId,
        counterPrice: counterPrice,
      );

      await NotificationService.instance.notifyUser(
        userId: widget.buyerId,
        title: 'Counter offer received',
        body:
            'Seller countered ${widget.itemTitle} at RM ${counterPrice.toStringAsFixed(2)}.',
        type: 'offer',
        itemId: widget.itemId,
        chatRoomId: widget.roomId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyOfferError(e))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyOfferError(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Offer update denied. Publish the latest Firestore rules, then try again.';
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return 'Failed to update offer: ${error.message}';
      }
      return 'Failed to update offer: ${error.code}';
    }

    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.contains('converted Future')) {
      return 'Failed to update offer. Please publish the latest Firestore rules and try again.';
    }
    return 'Failed to update offer: $message';
  }

  Widget _offerActionButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final child = Icon(icon, size: 18);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
    );
    final spinner = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(
          filled ? Colors.white : color,
        ),
      ),
    );

    if (filled) {
      return Tooltip(
        message: tooltip,
        child: SizedBox(
          height: 38,
          width: 58,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              shape: shape,
            ),
            child: _isLoading ? spinner : child,
          ),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 38,
        width: 58,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withOpacity(0.7)),
            padding: EdgeInsets.zero,
            shape: shape,
          ),
          child: _isLoading ? spinner : child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    switch (widget.status) {
      case 'accepted':
        statusColor = Colors.green;
        break;
      case 'rejected':
      case 'cancelled':
        statusColor = Colors.red;
        break;
      case 'countered':
        statusColor = Colors.blue;
        break;
      case 'expired':
        statusColor = Colors.grey;
        break;
      default:
        statusColor = widget.isExpired ? Colors.grey : Colors.orange;
    }

    final shownStatus = widget.isExpired && widget.status == 'pending'
        ? 'expired'
        : widget.status;

    return Column(
      crossAxisAlignment: widget.isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(
              left: widget.isMe ? 72 : 14,
              right: widget.isMe ? 14 : 72,
              top: 6,
              bottom: 2,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 252),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      topRight: Radius.circular(14),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_offer,
                        size: 16,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isCounterOffer
                              ? 'Counter Offer: ${widget.itemTitle}'
                              : widget.itemTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Offer Price'),
                          Text(
                            'RM ${widget.offerPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(
                              shownStatus.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.status == 'pending' && !widget.isExpired) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (!widget.isMe) ...[
                          _offerActionButton(
                            tooltip: 'Reject offer',
                            icon: Icons.close_rounded,
                            color: Colors.red,
                            onPressed: _isLoading
                                ? null
                                : () => _handleOfferAction('rejected'),
                          ),
                          if (widget.isSeller)
                            _offerActionButton(
                              tooltip: 'Counter offer',
                              icon: Icons.swap_horiz_rounded,
                              color: Colors.blue.shade700,
                              onPressed: _isLoading ? null : _counterOffer,
                            ),
                          _offerActionButton(
                            tooltip: 'Accept offer',
                            icon: Icons.check_rounded,
                            color: Colors.green,
                            filled: true,
                            onPressed: _isLoading
                                ? null
                                : () => _handleOfferAction('accepted'),
                          ),
                        ] else
                          _offerActionButton(
                            tooltip: 'Cancel offer',
                            icon: Icons.close_rounded,
                            color: Colors.red,
                            onPressed: _isLoading
                                ? null
                                : () => _handleOfferAction('cancelled'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: widget.isMe ? 72 : 18,
            right: widget.isMe ? 18 : 72,
            bottom: 4,
          ),
          child: Text(
            widget.time,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ),
      ],
    );
  }
}
