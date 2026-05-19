import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/transaction_service.dart';
import '../widgets/status_badge.dart';
import 'meetup_location_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _transactionsStream;
  final _imagePicker = ImagePicker();
  static const _paymentMethods = [
    'Cash on Meetup',
    'Online Banking',
    'Touch n Go eWallet',
    'DuitNow QR',
    'Bank Transfer',
  ];

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.currentUser;
    if (user != null) {
      _transactionsStream = FirebaseFirestore.instance
          .collection('transactions')
          .where('participants', arrayContains: user.uid)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _transactionsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load transactions.'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('No transactions yet.'));
          }

          final txs = docs.map(TransactionModel.fromFirestore).toList();
          txs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: txs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final tx = txs[index];
              final isBuyer = tx.buyerId == user.uid;
              final isSeller = tx.sellerId == user.uid;

              return _transactionCard(
                tx: tx,
                currentUserId: user.uid,
                isBuyer: isBuyer,
                isSeller: isSeller,
              );
            },
          );
        },
      ),
    );
  }

  Widget _transactionCard({
    required TransactionModel tx,
    required String currentUserId,
    required bool isBuyer,
    required bool isSeller,
  }) {
    final title = tx.itemTitle.isNotEmpty ? tx.itemTitle : tx.itemId;
    final canAct =
        tx.status == TransactionStatus.accepted ||
        tx.status == TransactionStatus.payment_processing;
    final canCancel =
        tx.status == TransactionStatus.accepted ||
        tx.status == TransactionStatus.payment_processing;
    final canRate =
        tx.status == TransactionStatus.completed &&
        ((isBuyer && tx.buyerRating == 0) ||
            (isSeller && tx.sellerRating == 0));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'View receipt',
                  icon: const Icon(Icons.receipt_long_rounded),
                  onPressed: () => _showReceipt(tx, isBuyer: isBuyer),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusBadge(status: tx.status),
                Chip(
                  label: Text(isBuyer ? 'Buyer' : 'Seller'),
                  visualDensity: VisualDensity.compact,
                ),
                if (tx.paymentMethod.isNotEmpty)
                  _infoChip(
                    icon: Icons.payments_rounded,
                    label: _shortPaymentLabel(tx.paymentMethod),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _nextStepBanner(tx, isBuyer: isBuyer, isSeller: isSeller),
            const SizedBox(height: 12),
            _transactionTimeline(tx),
            const SizedBox(height: 12),
            _detailRow(
              Icons.sell_rounded,
              'Offer price',
              'RM ${tx.offerPrice.toStringAsFixed(2)}',
            ),
            _detailRow(
              Icons.account_balance_wallet_rounded,
              'Platform fee',
              'RM ${tx.platformFee.toStringAsFixed(2)}',
            ),
            if (tx.paymentMethod.isNotEmpty)
              _detailRow(Icons.payments_rounded, 'Payment', tx.paymentMethod),
            if (tx.paymentReference.isNotEmpty)
              _detailRow(
                Icons.receipt_rounded,
                'Reference',
                tx.paymentReference,
              ),
            if (tx.paymentStatus.isNotEmpty)
              _detailRow(
                Icons.verified_user_rounded,
                'Payment status',
                _friendlyPaymentStatus(tx.paymentStatus),
              ),
            if (tx.paymentProofUrl.isNotEmpty) _paymentProofPreview(tx),
            if (tx.meetupLocation.isNotEmpty)
              _detailRow(Icons.place_rounded, 'Meetup', tx.meetupLocation),
            if (tx.issueReason.isNotEmpty)
              _detailRow(
                Icons.report_problem_rounded,
                'Issue',
                '${tx.issueStatus.isEmpty ? 'open' : tx.issueStatus}: ${tx.issueReason}',
              ),
            if (tx.cancelReason.isNotEmpty)
              _detailRow(
                Icons.info_outline_rounded,
                'Cancel reason',
                tx.cancelReason,
              ),
            if (canAct) ...[
              const SizedBox(height: 12),
              _actionArea(
                tx: tx,
                currentUserId: currentUserId,
                isBuyer: isBuyer,
                isSeller: isSeller,
              ),
            ],
            if (canCancel) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _reportIssue(tx, currentUserId),
                    icon: const Icon(Icons.report_problem_outlined, size: 18),
                    label: const Text('Report Issue'),
                  ),
                  TextButton.icon(
                    onPressed: () => _confirmCancel(tx, currentUserId),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel Transaction'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ],
            if (canRate) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _rateTransaction(tx, currentUserId),
                  icon: const Icon(Icons.star_rounded),
                  label: const Text('Rate User'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionArea({
    required TransactionModel tx,
    required String currentUserId,
    required bool isBuyer,
    required bool isSeller,
  }) {
    if (tx.status == TransactionStatus.accepted) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => _setMeetupLocation(tx),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.map_rounded, size: 16),
            label: const Text('Set Meetup'),
          ),
          if (isBuyer)
            Tooltip(
              message: tx.meetupLocation.isEmpty
                  ? 'Set meetup location first'
                  : 'Select payment method',
              child: OutlinedButton.icon(
                onPressed: tx.meetupLocation.isEmpty
                    ? null
                    : () => _choosePaymentMethod(tx, currentUserId),
                icon: const Icon(Icons.payments_rounded, size: 16),
                label: const Text('Select Payment Method'),
              ),
            ),
        ],
      );
    }
    if (isSeller && tx.status == TransactionStatus.payment_processing) {
      return FilledButton.icon(
        onPressed: () => _confirmPaymentReceived(tx, currentUserId),
        icon: const Icon(Icons.verified_rounded),
        label: const Text('Confirm Payment Received'),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _transactionTimeline(TransactionModel tx) {
    final steps = [
      _TimelineStep(
        label: 'Offer Sent',
        done: true,
        icon: Icons.local_offer_rounded,
      ),
      _TimelineStep(
        label: 'Accepted',
        done:
            tx.status.index >= TransactionStatus.accepted.index &&
            tx.status != TransactionStatus.cancelled,
        icon: Icons.handshake_rounded,
      ),
      _TimelineStep(
        label: 'Meetup Set',
        done: tx.meetupLocation.isNotEmpty,
        icon: Icons.place_rounded,
      ),
      _TimelineStep(
        label: 'Payment',
        done:
            tx.paymentMethod.isNotEmpty ||
            tx.status == TransactionStatus.payment_processing ||
            tx.status == TransactionStatus.completed,
        icon: Icons.payments_rounded,
      ),
      _TimelineStep(
        label: tx.status == TransactionStatus.cancelled
            ? 'Cancelled'
            : 'Completed',
        done:
            tx.status == TransactionStatus.completed ||
            tx.status == TransactionStatus.cancelled,
        icon: tx.status == TransactionStatus.cancelled
            ? Icons.cancel_rounded
            : Icons.check_circle_rounded,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(child: _timelineNode(steps[i])),
          if (i < steps.length - 1)
            Container(
              width: 18,
              height: 2,
              color: steps[i + 1].done ? Colors.green : Colors.grey.shade300,
            ),
        ],
      ],
    );
  }

  Widget _timelineNode(_TimelineStep step) {
    final color = step.done ? Colors.green : Colors.grey;
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(step.icon, size: 16, color: color.shade700),
        ),
        const SizedBox(height: 4),
        Text(
          step.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            color: step.done ? Colors.green.shade800 : Colors.grey.shade600,
            fontWeight: step.done ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(
            width: 94,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nextStepBanner(
    TransactionModel tx, {
    required bool isBuyer,
    required bool isSeller,
  }) {
    final text = _nextStepText(tx, isBuyer: isBuyer, isSeller: isSeller);
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _nextStepText(
    TransactionModel tx, {
    required bool isBuyer,
    required bool isSeller,
  }) {
    if (tx.status == TransactionStatus.accepted) {
      if (tx.meetupLocation.isEmpty) return 'Next: set the meetup location.';
      if (isBuyer) return 'Next: select payment method and upload proof if available.';
      return 'Waiting for buyer to select payment.';
    }
    if (tx.status == TransactionStatus.payment_processing) {
      if (isSeller) return 'Review payment details, then confirm payment received.';
      return 'Waiting for seller to confirm payment received.';
    }
    if (tx.status == TransactionStatus.completed) return 'Completed. Rating is available.';
    if (tx.status == TransactionStatus.cancelled) return 'This transaction was cancelled.';
    return '';
  }

  String _friendlyPaymentStatus(String status) {
    switch (status) {
      case 'awaiting_selection':
        return 'Awaiting buyer selection';
      case 'awaiting_seller_confirmation':
        return 'Awaiting seller confirmation';
      case 'verified':
        return 'Verified';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Widget _paymentProofPreview(TransactionModel tx) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: GestureDetector(
        onTap: () => _showProofImage(tx.paymentProofUrl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            tx.paymentProofUrl,
            height: 120,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _detailRow(
              Icons.image_not_supported_rounded,
              'Proof',
              'Unable to load image',
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoChip({required IconData icon, required String label}) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  void _showProofImage(String imageUrl) {
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

  Future<void> _update(
    TransactionModel tx,
    TransactionStatus newStatus,
    String currentUserId, {
    String cancelReason = '',
  }) async {
    try {
      await TransactionService.instance.updateTransactionStatus(
        transactionId: tx.id,
        newStatus: newStatus,
        actionUserId: currentUserId,
        roomId: tx.roomId,
        cancelReason: cancelReason,
      );

      // Backwards compatible notification triggering
      if (newStatus == TransactionStatus.completed) {
        await NotificationService.instance.notifyUser(
          userId: tx.buyerId,
          title: 'Transaction completed',
          body: 'The transaction for ${tx.itemTitle} was marked completed.',
          type: 'transaction',
          itemId: tx.itemId,
          chatRoomId: tx.roomId,
        );
      }

      if (newStatus == TransactionStatus.cancelled) {
        final otherUserId = currentUserId == tx.buyerId
            ? tx.sellerId
            : tx.buyerId;
        await NotificationService.instance.notifyUser(
          userId: otherUserId,
          title: 'Transaction cancelled',
          body: 'The transaction for ${tx.itemTitle} was cancelled.',
          type: 'transaction',
          itemId: tx.itemId,
          chatRoomId: tx.roomId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transaction updated to ${newStatus.name}.')),
        );
      }
    } catch (e) {
      debugPrint('Failed to update transaction status: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update transaction: $e')),
      );
    }
  }

  Future<void> _setMeetupLocation(TransactionModel tx) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MeetupLocationScreen(selected: tx.meetupLocation),
      ),
    );

    if (result == null || result is! Map) return;

    try {
      await TransactionService.instance.setMeetupLocation(
        transactionId: tx.id,
        locationName: result['location'],
        latitude: result['latitude'],
        longitude: result['longitude'],
      );

      await NotificationService.instance.notifyUser(
        userId: tx.buyerId == AuthService.instance.currentUser?.uid
            ? tx.sellerId
            : tx.buyerId,
        title: 'Meetup location set',
        body: 'Meetup for ${tx.itemTitle} set to ${result['location']}.',
        type: 'transaction',
        itemId: tx.itemId,
        chatRoomId: tx.roomId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Meetup location saved.')));
    } catch (e) {
      debugPrint('Failed to set meetup location: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to set meetup: $e')));
    }
  }

  Future<void> _confirmPaymentReceived(
    TransactionModel tx,
    String currentUserId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm payment received?'),
        content: Text(
          'Mark this transaction for ${tx.itemTitle} as completed only after you have verified the payment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.verified_rounded),
            label: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _update(tx, TransactionStatus.completed, currentUserId);
    }
  }

  Future<void> _reportIssue(TransactionModel tx, String currentUserId) async {
    final controller = TextEditingController(text: tx.issueReason);
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report transaction issue'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Issue details',
            hintText: 'Example: payment not received or meetup problem',
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
      await TransactionService.instance.reportTransactionIssue(
        transactionId: tx.id,
        actionUserId: currentUserId,
        roomId: tx.roomId,
        reason: reason,
      );

      final otherUserId = currentUserId == tx.buyerId ? tx.sellerId : tx.buyerId;
      await NotificationService.instance.notifyUser(
        userId: otherUserId,
        title: 'Transaction issue reported',
        body: reason,
        type: 'transaction',
        itemId: tx.itemId,
        chatRoomId: tx.roomId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Issue reported.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to report issue: $e')));
    }
  }

  Future<void> _confirmCancel(TransactionModel tx, String currentUserId) async {
    String selectedReason = 'Buyer/Seller changed mind';
    final reasons = [
      'Buyer/Seller changed mind',
      'Meetup unavailable',
      'Payment issue',
      'Item no longer available',
      'Other',
    ];
    final noteController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Cancel transaction?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will mark the transaction for ${tx.itemTitle} as cancelled.',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: reasons
                      .map(
                        (reason) => DropdownMenuItem(
                          value: reason,
                          child: Text(reason),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => selectedReason = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Extra note',
                    hintText: 'Optional',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Cancel Transaction'),
              ),
            ],
          );
        },
      ),
    );

    if (confirm != true) {
      noteController.dispose();
      return;
    }

    final note = noteController.text.trim();
    noteController.dispose();
    final reason = note.isEmpty ? selectedReason : '$selectedReason: $note';
    await _update(
      tx,
      TransactionStatus.cancelled,
      currentUserId,
      cancelReason: reason,
    );
  }

  Future<void> _rateTransaction(
    TransactionModel tx,
    String currentUserId,
  ) async {
    double rating = 5;
    final reviewController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Rate this transaction'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentUserId == tx.buyerId
                      ? 'Rate the seller'
                      : 'Rate the buyer',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final starValue = index + 1;
                    return IconButton(
                      onPressed: () {
                        setDialogState(() => rating = starValue.toDouble());
                      },
                      icon: Icon(
                        starValue <= rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: Colors.amber.shade700,
                      ),
                    );
                  }),
                ),
                TextField(
                  controller: reviewController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Review',
                    hintText: 'Optional',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Submit Rating'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) {
      reviewController.dispose();
      return;
    }

    final review = reviewController.text.trim();
    reviewController.dispose();

    try {
      await TransactionService.instance.submitRating(
        transactionId: tx.id,
        actionUserId: currentUserId,
        rating: rating,
        review: review,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rating submitted.')));
    } catch (e) {
      debugPrint('Failed to submit rating: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit rating: $e')));
    }
  }

  void _showReceipt(TransactionModel tx, {required bool isBuyer}) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.receipt_long_rounded),
            SizedBox(width: 8),
            Text('Transaction Receipt'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _receiptLine('Reference', _transactionReference(tx.id)),
              _receiptLine(
                'Item',
                tx.itemTitle.isNotEmpty ? tx.itemTitle : tx.itemId,
              ),
              _receiptLine('Role', isBuyer ? 'Buyer' : 'Seller'),
              _receiptLine('Status', _friendlyTransactionStatus(tx.status)),
              _receiptLine(
                'Offer price',
                'RM ${tx.offerPrice.toStringAsFixed(2)}',
              ),
              _receiptLine(
                'Final price',
                'RM ${tx.finalPrice.toStringAsFixed(2)}',
              ),
              _receiptLine(
                'Platform fee',
                'RM ${tx.platformFee.toStringAsFixed(2)}',
              ),
              _receiptLine(
                'Payment',
                tx.paymentMethod.isNotEmpty ? tx.paymentMethod : 'Not selected',
              ),
              if (tx.paymentReference.isNotEmpty)
                _receiptLine('Reference', tx.paymentReference),
              if (tx.paymentStatus.isNotEmpty)
                _receiptLine(
                  'Payment status',
                  _friendlyPaymentStatus(tx.paymentStatus),
                ),
              if (tx.issueReason.isNotEmpty)
                _receiptLine(
                  'Issue',
                  '${tx.issueStatus.isEmpty ? 'open' : tx.issueStatus}: ${tx.issueReason}',
                ),
              if (tx.cancelReason.isNotEmpty)
                _receiptLine('Cancel reason', tx.cancelReason),
              if (tx.buyerRating > 0)
                _receiptLine(
                  'Buyer rating',
                  '${tx.buyerRating.toStringAsFixed(1)} / 5',
                ),
              if (tx.sellerRating > 0)
                _receiptLine(
                  'Seller rating',
                  '${tx.sellerRating.toStringAsFixed(1)} / 5',
                ),
              _receiptLine(
                'Meetup',
                tx.meetupLocation.isNotEmpty ? tx.meetupLocation : 'Not set',
              ),
              _receiptLine('Created', _formatDate(tx.createdAt)),
              _receiptLine('Updated', _formatDate(tx.updatedAt)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _receiptLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _transactionReference(String id) {
    final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (clean.length <= 6) return 'TX-$clean';
    return 'TX-${clean.substring(clean.length - 6)}';
  }

  String _friendlyTransactionStatus(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.payment_processing:
        return 'Awaiting seller confirmation';
      case TransactionStatus.accepted:
        return 'Meetup and payment pending';
      case TransactionStatus.completed:
        return 'Completed';
      case TransactionStatus.cancelled:
        return 'Cancelled';
      case TransactionStatus.pending:
        return 'Pending';
      case TransactionStatus.rejected:
        return 'Rejected';
    }
  }

  String _shortPaymentLabel(String method) {
    switch (method) {
      case 'Cash on Meetup':
        return 'Cash';
      case 'Touch n Go eWallet':
        return 'TNG';
      case 'Online Banking':
        return 'Banking';
      case 'Bank Transfer':
        return 'Transfer';
      default:
        return method;
    }
  }

  String _formatDate(DateTime value) {
    final date =
        '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
    final time =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  Future<void> _choosePaymentMethod(
    TransactionModel tx,
    String currentUserId,
  ) async {
    String selectedMethod = tx.paymentMethod.isNotEmpty
        ? tx.paymentMethod
        : _paymentMethods.first;
    final referenceController = TextEditingController(
      text: tx.paymentReference,
    );
    XFile? selectedProof;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 18,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose Payment Method',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'RM ${tx.finalPrice.toStringAsFixed(2)} for ${tx.itemTitle}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 14),
                    ..._paymentMethods.map(
                      (method) => RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: method,
                        groupValue: selectedMethod,
                        title: Text(method),
                        onChanged: (value) {
                          if (value == null) return;
                          setModalState(() => selectedMethod = value);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: referenceController,
                      decoration: const InputDecoration(
                        labelText: 'Payment reference / note',
                        hintText: 'Optional',
                        prefixIcon: Icon(Icons.receipt_long_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await _imagePicker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                        );
                        if (picked == null) return;
                        setModalState(() => selectedProof = picked);
                      },
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(
                        selectedProof == null
                            ? 'Upload payment proof'
                            : 'Proof selected',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context, {
                            'method': selectedMethod,
                            'reference': referenceController.text.trim(),
                          });
                        },
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Confirm Payment Method'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    referenceController.dispose();
    if (result == null) return;

    try {
      String proofUrl = tx.paymentProofUrl;
      if (selectedProof != null) {
        final bytes = await selectedProof!.readAsBytes();
        proofUrl = await StorageService.instance.uploadTransactionProof(
          transactionId: tx.id,
          userId: currentUserId,
          bytes: bytes,
        );
      }

      await TransactionService.instance.choosePaymentMethodAndStartPayment(
        transactionId: tx.id,
        actionUserId: currentUserId,
        roomId: tx.roomId,
        paymentMethod: result['method'] ?? '',
        paymentReference: result['reference'] ?? '',
        paymentProofUrl: proofUrl,
      );

      await NotificationService.instance.notifyUser(
        userId: tx.sellerId,
        title: 'Payment method selected',
        body:
            'Buyer selected ${result['method']} for ${tx.itemTitle}. Please verify and complete the transaction after meetup.',
        type: 'transaction',
        itemId: tx.itemId,
        chatRoomId: tx.roomId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment method saved.')));
    } catch (e) {
      debugPrint('Failed to choose payment method: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save payment method: $e')),
      );
    }
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.label,
    required this.done,
    required this.icon,
  });

  final String label;
  final bool done;
  final IconData icon;
}
