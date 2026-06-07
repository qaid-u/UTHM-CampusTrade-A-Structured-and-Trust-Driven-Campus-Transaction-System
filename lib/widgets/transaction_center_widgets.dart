import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import '../services/transaction_service.dart';
import 'status_badge.dart';

class TransactionCard extends StatelessWidget {
  const TransactionCard({
    super.key,
    required this.transaction,
    required this.currentUserId,
    required this.buyerName,
    required this.sellerName,
    required this.reviewStatus,
    required this.onOpenChat,
    required this.onOpenItem,
    required this.onOpenUserProfile,
    required this.onUploadReceipt,
    required this.onVerifyReceipt,
    required this.onConfirmMeetup,
    required this.onConfirmReceived,
    required this.onCancel,
    required this.onLeaveReview,
    required this.onViewReceipt,
    required this.onOpenMaps,
  });

  final TransactionModel transaction;
  final String currentUserId;
  final String buyerName;
  final String sellerName;
  final AsyncSnapshot<bool> reviewStatus;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenItem;
  final VoidCallback onOpenUserProfile;
  final VoidCallback onUploadReceipt;
  final VoidCallback onVerifyReceipt;
  final VoidCallback onConfirmMeetup;
  final VoidCallback onConfirmReceived;
  final VoidCallback onCancel;
  final VoidCallback onLeaveReview;
  final VoidCallback onViewReceipt;
  final VoidCallback onOpenMaps;

  bool get _isBuyer => transaction.buyerId == currentUserId;

  @override
  Widget build(BuildContext context) {
    final title = transaction.itemTitle.isNotEmpty
        ? transaction.itemTitle
        : 'Transaction ${transaction.id}';
    final partnerLabel = _isBuyer
        ? 'Buying from ${sellerName.isNotEmpty ? sellerName : "Seller"}'
        : 'Selling to ${buyerName.isNotEmpty ? buyerName : "Buyer"}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: _TransactionThumb(url: transaction.itemThumbnail),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(partnerLabel),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(status: transaction.status),
                  _RoleChip(label: _isBuyer ? 'Buyer' : 'Seller'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'RM ${transaction.finalPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${_dateLabel(transaction)} • ${_statusDescription(transaction, _isBuyer)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: 20),
          TransactionTimeline(transaction: transaction),
          const SizedBox(height: 12),
          ReceiptPreviewCard(
            transaction: transaction,
            onViewReceipt: onViewReceipt,
          ),
          const SizedBox(height: 12),
          MeetupInfoCard(transaction: transaction, onOpenMaps: onOpenMaps),
          const SizedBox(height: 12),
          TransactionActionButtons(
            transaction: transaction,
            currentUserId: currentUserId,
            hasReviewed: reviewStatus.data ?? false,
            reviewStatusLoading:
                reviewStatus.connectionState == ConnectionState.waiting,
            onOpenChat: onOpenChat,
            onOpenItem: onOpenItem,
            onOpenUserProfile: onOpenUserProfile,
            onUploadReceipt: onUploadReceipt,
            onVerifyReceipt: onVerifyReceipt,
            onConfirmMeetup: onConfirmMeetup,
            onConfirmReceived: onConfirmReceived,
            onCancel: onCancel,
            onLeaveReview: onLeaveReview,
          ),
        ],
      ),
    );
  }

  static String _dateLabel(TransactionModel tx) {
    final date = tx.updatedAt;
    return 'Updated ${date.day}/${date.month}/${date.year}';
  }

  static String _statusDescription(TransactionModel tx, bool isBuyer) {
    switch (tx.status) {
      case TransactionStatus.pending_offer:
        return isBuyer ? 'Waiting for seller response' : 'Offer needs action';
      case TransactionStatus.accepted:
        return tx.meetupLocation.isEmpty
            ? 'Meetup location not confirmed yet'
            : 'Meetup confirmation in progress';
      case TransactionStatus.rejected:
        return 'Offer was rejected';
      case TransactionStatus.meetup_pending:
        if (!tx.receiptUploaded) {
          return isBuyer
              ? 'Upload your payment receipt'
              : 'Waiting for buyer receipt';
        }
        if (!tx.paymentVerified) {
          return isBuyer
              ? 'Waiting for seller verification'
              : 'Verify payment receipt';
        }
        return isBuyer
            ? 'Confirm item received'
            : 'Waiting for buyer completion';
      case TransactionStatus.completed:
        return 'Transaction completed';
      case TransactionStatus.cancelled:
        return 'Transaction cancelled';
    }
  }
}

class TransactionTimeline extends StatelessWidget {
  const TransactionTimeline({super.key, required this.transaction});

  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final steps = [
      _TimelineStep('Offer Accepted', _offerAccepted),
      _TimelineStep('Meetup Pending', _meetupReady),
      _TimelineStep('Receipt Uploaded', transaction.receiptUploaded),
      _TimelineStep('Payment Verified', transaction.paymentVerified),
      _TimelineStep(
        'Completed',
        transaction.status == TransactionStatus.completed,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Progress', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Expanded(
                child: _TimelineNode(
                  label: steps[i].label,
                  done: steps[i].done,
                  active: i == _activeIndex(steps),
                ),
              ),
              if (i != steps.length - 1)
                Container(
                  width: 18,
                  height: 2,
                  margin: const EdgeInsets.only(top: 11),
                  color: steps[i].done
                      ? Colors.green.shade400
                      : Colors.grey.shade300,
                ),
            ],
          ],
        ),
      ],
    );
  }

  bool get _offerAccepted =>
      transaction.status != TransactionStatus.pending_offer &&
      transaction.status != TransactionStatus.rejected &&
      transaction.status != TransactionStatus.cancelled;

  bool get _meetupReady =>
      transaction.status == TransactionStatus.meetup_pending ||
      transaction.status == TransactionStatus.completed ||
      (transaction.buyerMeetupConfirmed && transaction.sellerMeetupConfirmed);

  int _activeIndex(List<_TimelineStep> steps) {
    final index = steps.lastIndexWhere((step) => step.done);
    return index < 0 ? 0 : index;
  }
}

class ReceiptPreviewCard extends StatelessWidget {
  const ReceiptPreviewCard({
    super.key,
    required this.transaction,
    required this.onViewReceipt,
  });

  final TransactionModel transaction;
  final VoidCallback onViewReceipt;

  @override
  Widget build(BuildContext context) {
    final receiptUrl = transaction.receiptUrl;
    final hasReceipt =
        transaction.receiptUploaded &&
        receiptUrl != null &&
        receiptUrl.trim().isNotEmpty;

    return _InfoPanel(
      title: 'Receipt',
      child: hasReceipt
          ? Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    receiptUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 64,
                      height: 64,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    transaction.paymentVerified
                        ? 'Payment verified'
                        : 'Pending verification',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: onViewReceipt,
                  child: const Text('View Receipt'),
                ),
              ],
            )
          : const Text('No receipt uploaded yet'),
    );
  }
}

class MeetupInfoCard extends StatelessWidget {
  const MeetupInfoCard({
    super.key,
    required this.transaction,
    required this.onOpenMaps,
  });

  final TransactionModel transaction;
  final VoidCallback onOpenMaps;

  @override
  Widget build(BuildContext context) {
    final hasMeetup = transaction.meetupLocation.trim().isNotEmpty;
    final safeZone = TransactionService.isSafeZone(
      transaction.meetupLatitude,
      transaction.meetupLongitude,
    );

    return _InfoPanel(
      title: 'Meetup',
      child: hasMeetup
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.meetupLocation,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${transaction.meetupLatitude.toStringAsFixed(5)}, '
                  '${transaction.meetupLongitude.toStringAsFixed(5)}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ConfirmChip(
                      label: 'Buyer',
                      confirmed: transaction.buyerMeetupConfirmed,
                    ),
                    _ConfirmChip(
                      label: 'Seller',
                      confirmed: transaction.sellerMeetupConfirmed,
                    ),
                    if (safeZone)
                      const _MiniBadge(
                        icon: Icons.verified_user_rounded,
                        label: 'Safe Zone Verified',
                        color: Colors.green,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onOpenMaps,
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('Open in Google Maps'),
                  ),
                ),
              ],
            )
          : const Text('Meetup location not confirmed yet'),
    );
  }
}

class TransactionActionButtons extends StatelessWidget {
  const TransactionActionButtons({
    super.key,
    required this.transaction,
    required this.currentUserId,
    required this.hasReviewed,
    required this.reviewStatusLoading,
    required this.onOpenChat,
    required this.onOpenItem,
    required this.onOpenUserProfile,
    required this.onUploadReceipt,
    required this.onVerifyReceipt,
    required this.onConfirmMeetup,
    required this.onConfirmReceived,
    required this.onCancel,
    required this.onLeaveReview,
  });

  final TransactionModel transaction;
  final String currentUserId;
  final bool hasReviewed;
  final bool reviewStatusLoading;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenItem;
  final VoidCallback onOpenUserProfile;
  final VoidCallback onUploadReceipt;
  final VoidCallback onVerifyReceipt;
  final VoidCallback onConfirmMeetup;
  final VoidCallback onConfirmReceived;
  final VoidCallback onCancel;
  final VoidCallback onLeaveReview;

  bool get _isBuyer => currentUserId == transaction.buyerId;
  bool get _isSeller => currentUserId == transaction.sellerId;
  bool get _canCancel =>
      transaction.status != TransactionStatus.completed &&
      transaction.status != TransactionStatus.cancelled;
  bool get _currentUserConfirmedMeetup => _isBuyer
      ? transaction.buyerMeetupConfirmed
      : transaction.sellerMeetupConfirmed;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      OutlinedButton.icon(
        onPressed: onOpenChat,
        icon: const Icon(Icons.chat_bubble_outline, size: 18),
        label: const Text('Chat'),
      ),
      OutlinedButton.icon(
        onPressed: onOpenItem,
        icon: const Icon(Icons.inventory_2_outlined, size: 18),
        label: const Text('Item'),
      ),
      OutlinedButton.icon(
        onPressed: onOpenUserProfile,
        icon: const Icon(Icons.person_outline, size: 18),
        label: Text(_isSeller ? 'Buyer Profile' : 'Seller Profile'),
      ),
    ];

    if (transaction.meetupLocation.isNotEmpty &&
        !_currentUserConfirmedMeetup &&
        (transaction.status == TransactionStatus.accepted ||
            transaction.status == TransactionStatus.meetup_pending)) {
      buttons.add(
        FilledButton.icon(
          onPressed: onConfirmMeetup,
          icon: const Icon(Icons.place_rounded, size: 18),
          label: const Text('Confirm Meetup'),
        ),
      );
    }

    if (_isBuyer &&
        transaction.status == TransactionStatus.meetup_pending &&
        !transaction.receiptUploaded) {
      buttons.add(
        FilledButton.icon(
          onPressed: onUploadReceipt,
          icon: const Icon(Icons.receipt_long, size: 18),
          label: const Text('Upload Receipt'),
        ),
      );
    }

    if (_isSeller &&
        transaction.receiptUploaded &&
        !transaction.paymentVerified &&
        transaction.status == TransactionStatus.meetup_pending) {
      buttons.add(
        FilledButton.icon(
          onPressed: onVerifyReceipt,
          icon: const Icon(Icons.verified_rounded, size: 18),
          label: const Text('Verify Receipt'),
        ),
      );
    }

    if (_isBuyer &&
        transaction.status == TransactionStatus.meetup_pending &&
        transaction.paymentVerified) {
      buttons.add(
        FilledButton.icon(
          onPressed: onConfirmReceived,
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: const Text('Confirm Item Received'),
        ),
      );
    }

    if (_canCancel) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Cancel Transaction'),
        ),
      );
    }

    if (transaction.status == TransactionStatus.completed) {
      if (reviewStatusLoading) {
        buttons.add(
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      } else if (hasReviewed) {
        buttons.add(
          const _MiniBadge(
            icon: Icons.rate_review_rounded,
            label: 'Review Submitted',
            color: Colors.green,
          ),
        );
      } else {
        buttons.add(
          FilledButton.icon(
            onPressed: onLeaveReview,
            icon: const Icon(Icons.star_rate_rounded, size: 18),
            label: const Text('Leave Review'),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Actions', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: buttons),
      ],
    );
  }
}

class _TransactionThumb extends StatelessWidget {
  const _TransactionThumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.inventory_2_outlined),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 54,
          height: 54,
          color: Colors.grey.shade100,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? Colors.green
        : active
        ? Theme.of(context).colorScheme.primary
        : Colors.grey;

    return Column(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 22,
          color: color,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: active || done ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TimelineStep {
  const _TimelineStep(this.label, this.done);

  final String label;
  final bool done;
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _MiniBadge(
      icon: Icons.account_circle_outlined,
      label: label,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}

class _ConfirmChip extends StatelessWidget {
  const _ConfirmChip({required this.label, required this.confirmed});

  final String label;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    return _MiniBadge(
      icon: confirmed ? Icons.check_circle_rounded : Icons.schedule_rounded,
      label: '$label ${confirmed ? "confirmed" : "pending"}',
      color: confirmed ? Colors.green : Colors.orange,
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
