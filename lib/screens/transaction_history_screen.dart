import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/media_feedback_service.dart';
import '../services/review_service.dart';
import '../services/storage_service.dart';
import '../services/transaction_service.dart';
import '../widgets/feedback_helper.dart';
import '../widgets/transaction_center_widgets.dart';
import 'chat_screen.dart';
import 'item_detail_screen.dart';
import 'seller_profile_screen.dart';

enum _TransactionTab { buying, selling, completed, cancelled }

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ImagePicker _picker = ImagePicker();
  final Map<String, Future<bool>> _reviewStatusCache = {};
  final Map<String, String> _userNameCache = {};

  _TransactionTab _selectedTab = _TransactionTab.buying;
  String? _busyTransactionId;

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: _TransactionTab.values.length, vsync: this)
          ..addListener(() {
            if (_tabController.indexIsChanging) return;
            setState(() {
              _selectedTab = _TransactionTab.values[_tabController.index];
            });
          });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view transactions.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Buying'),
            Tab(text: 'Selling'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: StreamBuilder<List<TransactionModel>>(
        stream: _streamForTab(user.uid, _selectedTab),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              message: 'Unable to load transactions.',
              onRetry: () => setState(() {}),
            );
          }

          final transactions = snapshot.data ?? const <TransactionModel>[];
          if (transactions.isEmpty) {
            return _EmptyState(tab: _selectedTab);
          }

          return FutureBuilder<Map<String, String>>(
            future: _loadUserNames(transactions),
            builder: (context, namesSnapshot) {
              final names = namesSnapshot.data ?? _userNameCache;

              return RefreshIndicator(
                onRefresh: () async => setState(() {}),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: transactions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final reviewFuture = _reviewStatusCache.putIfAbsent(
                      '${tx.id}_${user.uid}',
                      () => ReviewService.hasUserReviewed(
                        transactionId: tx.id,
                        reviewerId: user.uid,
                      ),
                    );

                    return Stack(
                      children: [
                        FutureBuilder<bool>(
                          future: tx.status == TransactionStatus.completed
                              ? reviewFuture
                              : Future.value(false),
                          builder: (context, reviewSnapshot) {
                            return TransactionCard(
                              transaction: tx,
                              currentUserId: user.uid,
                              buyerName: names[tx.buyerId] ?? '',
                              sellerName: names[tx.sellerId] ?? '',
                              reviewStatus: reviewSnapshot,
                              onOpenChat: () => _openChat(tx),
                              onOpenItem: () => _openItem(tx),
                              onOpenUserProfile: () => _openPartnerProfile(tx),
                              onUploadReceipt: () => _uploadReceipt(tx),
                              onVerifyReceipt: () => _verifyReceipt(tx),
                              onConfirmMeetup: () => _confirmMeetup(tx),
                              onConfirmReceived: () => _confirmReceived(tx),
                              onCancel: () => _cancelTransaction(tx),
                              onLeaveReview: () => _leaveReview(tx),
                              onViewReceipt: () => _viewReceipt(tx),
                              onOpenMaps: () => _openMaps(tx),
                            );
                          },
                        ),
                        if (_busyTransactionId == tx.id)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<Map<String, String>> _loadUserNames(
    List<TransactionModel> transactions,
  ) async {
    final ids = <String>{
      for (final tx in transactions) ...[
        if (tx.buyerId.isNotEmpty) tx.buyerId,
        if (tx.sellerId.isNotEmpty) tx.sellerId,
      ],
    }.where((id) => !_userNameCache.containsKey(id)).toList();

    if (ids.isEmpty) return _userNameCache;

    for (var i = 0; i < ids.length; i += 10) {
      final batch = ids.skip(i).take(10).toList();
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get()
          .timeout(const Duration(seconds: 5));

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['name'] ?? data['studentId'] ?? '').toString();
        if (name.trim().isNotEmpty) {
          _userNameCache[doc.id] = name.trim();
        }
      }
    }

    return _userNameCache;
  }

  Stream<List<TransactionModel>> _streamForTab(
    String uid,
    _TransactionTab tab,
  ) {
    return switch (tab) {
      _TransactionTab.buying =>
        TransactionService.instance.getBuyingTransactions(uid),
      _TransactionTab.selling =>
        TransactionService.instance.getSellingTransactions(uid),
      _TransactionTab.completed =>
        TransactionService.instance.getTransactionsByStatusForUser(
          userId: uid,
          status: TransactionStatus.completed,
        ),
      _TransactionTab.cancelled =>
        TransactionService.instance.getTransactionsByStatusForUser(
          userId: uid,
          status: TransactionStatus.cancelled,
        ),
    };
  }

  Future<void> _openChat(TransactionModel tx) async {
    try {
      final roomId = await _resolveRoomId(tx);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(roomId: roomId)),
      );
    } catch (e) {
      _showError('Unable to open chat: $e');
    }
  }

  void _openItem(TransactionModel tx) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: tx.itemId)),
    );
  }

  void _openPartnerProfile(TransactionModel tx) {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final partnerId = user.uid == tx.buyerId ? tx.sellerId : tx.buyerId;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerProfileScreen(sellerId: partnerId),
      ),
    );
  }

  Future<void> _uploadReceipt(TransactionModel tx) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take Receipt Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    await _runTransactionAction(tx, () async {
      final roomId = await _resolveRoomId(tx);
      final receiptUrl = await StorageService.instance.uploadReceiptImage(
        roomId: roomId,
        bytes: Uint8List.fromList(bytes),
      );
      await TransactionService.instance.uploadPaymentReceipt(
        transactionId: tx.id,
        roomId: roomId,
        actionUserId: AuthService.instance.currentUser!.uid,
        receiptUrl: receiptUrl,
      );
      MediaFeedbackService.instance.playNotification();
      _showSuccess('Receipt uploaded. Waiting for seller verification.');
    });
  }

  Future<void> _verifyReceipt(TransactionModel tx) async {
    final confirmed = await FeedbackHelper.showConfirmation(
      context,
      title: 'Verify Receipt',
      message: 'Confirm that this receipt matches the payment you received.',
      confirmText: 'Verify',
    );
    if (!confirmed) return;

    await _runTransactionAction(tx, () async {
      final roomId = await _resolveRoomId(tx);
      await TransactionService.instance.verifyPayment(
        transactionId: tx.id,
        roomId: roomId,
        actionUserId: AuthService.instance.currentUser!.uid,
      );
      MediaFeedbackService.instance.playSuccess();
      _showSuccess('Payment verified.');
    });
  }

  Future<void> _confirmMeetup(TransactionModel tx) async {
    await _runTransactionAction(tx, () async {
      final roomId = await _resolveRoomId(tx);
      await TransactionService.instance.confirmMeetupLocation(
        transactionId: tx.id,
        actionUserId: AuthService.instance.currentUser!.uid,
        roomId: roomId,
      );
      _showSuccess('Meetup confirmed.');
    });
  }

  Future<void> _confirmReceived(TransactionModel tx) async {
    final confirmed = await FeedbackHelper.showConfirmation(
      context,
      title: 'Confirm Item Received',
      message:
          'Only confirm after you have received the item and are satisfied.',
      confirmText: 'Confirm',
    );
    if (!confirmed) return;

    await _runTransactionAction(tx, () async {
      final roomId = await _resolveRoomId(tx);
      await TransactionService.instance.completeTransaction(
        transactionId: tx.id,
        roomId: roomId,
        actionUserId: AuthService.instance.currentUser!.uid,
      );
      MediaFeedbackService.instance.playTransactionComplete();
      _showSuccess('Transaction completed.');
    });
  }

  Future<void> _cancelTransaction(TransactionModel tx) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Transaction'),
        content: TextField(
          controller: reasonController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Briefly explain why this transaction is cancelled',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep Transaction'),
          ),
          FilledButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, value);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Transaction'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || reason.isEmpty) return;

    await _runTransactionAction(tx, () async {
      final roomId = await _resolveRoomId(tx);
      await TransactionService.instance.cancelTransaction(
        transactionId: tx.id,
        actionUserId: AuthService.instance.currentUser!.uid,
        roomId: roomId,
        reason: reason,
      );
      MediaFeedbackService.instance.playError();
      _showSuccess('Transaction cancelled.');
    });
  }

  Future<void> _leaveReview(TransactionModel tx) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    var rating = 5;
    final commentController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Anonymous Review'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your name will not be shown with this review.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 4,
                  children: List.generate(5, (index) {
                    final value = index + 1;
                    return IconButton(
                      onPressed: () => setDialogState(() => rating = value),
                      icon: Icon(
                        value <= rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: Colors.amber.shade700,
                      ),
                    );
                  }),
                ),
                TextField(
                  controller: commentController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Comment',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
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
                onPressed: () async {
                  final revieweeId = user.uid == tx.buyerId
                      ? tx.sellerId
                      : tx.buyerId;
                  try {
                    await ReviewService.submitReview(
                      transactionId: tx.id,
                      reviewerId: user.uid,
                      revieweeId: revieweeId,
                      rating: rating,
                      comment: commentController.text.trim(),
                    );
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to submit review: $e')),
                      );
                    }
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
    commentController.dispose();

    if (submitted == true) {
      _reviewStatusCache['${tx.id}_${user.uid}'] = Future.value(true);
      if (!mounted) return;
      setState(() {});
      _showSuccess('Review submitted anonymously.');
    }
  }

  void _viewReceipt(TransactionModel tx) {
    final url = tx.receiptUrl;
    if (url == null || url.trim().isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Unable to load receipt image.'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMaps(TransactionModel tx) async {
    if (tx.meetupLatitude == 0 || tx.meetupLongitude == 0) {
      _showError('Meetup coordinates are not available yet.');
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination='
      '${tx.meetupLatitude},${tx.meetupLongitude}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showError('Unable to open Google Maps.');
  }

  Future<String> _resolveRoomId(TransactionModel tx) async {
    final user = AuthService.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    final offerDoc = await FirebaseFirestore.instance
        .collection('offers')
        .doc(tx.id)
        .get()
        .timeout(const Duration(seconds: 5));
    final offerRoomId = offerDoc.data()?['roomId']?.toString() ?? '';
    if (offerRoomId.isNotEmpty) return offerRoomId;

    final roomByTransaction = await FirebaseFirestore.instance
        .collection('chatRooms')
        .where('transactionId', isEqualTo: tx.id)
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 5));
    if (roomByTransaction.docs.isNotEmpty) {
      return roomByTransaction.docs.first.id;
    }

    return ChatService.getOrCreateRoom(
      itemId: tx.itemId,
      itemTitle: tx.itemTitle.isEmpty ? 'Item' : tx.itemTitle,
      itemThumbnail: tx.itemThumbnail,
      buyerId: tx.buyerId,
      sellerId: tx.sellerId,
    );
  }

  Future<void> _runTransactionAction(
    TransactionModel tx,
    Future<void> Function() action,
  ) async {
    if (_busyTransactionId != null) return;
    setState(() => _busyTransactionId = tx.id);
    try {
      await action();
    } catch (e) {
      MediaFeedbackService.instance.playError();
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busyTransactionId = null);
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tab});

  final _TransactionTab tab;

  @override
  Widget build(BuildContext context) {
    final message = switch (tab) {
      _TransactionTab.buying => 'No buying transactions found.',
      _TransactionTab.selling => 'No selling transactions found.',
      _TransactionTab.completed => 'No completed transactions yet.',
      _TransactionTab.cancelled => 'No cancelled transactions.',
    };
    final helper = switch (tab) {
      _TransactionTab.buying =>
        'Accepted offers where you are the buyer will appear here.',
      _TransactionTab.selling =>
        'Accepted offers where you are the seller will appear here.',
      _TransactionTab.completed =>
        'Finished deals and review actions will appear here.',
      _TransactionTab.cancelled =>
        'Cancelled deals are kept here for reference.',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 52,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              helper,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 52, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
