import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/offer_message_card.dart';
import 'package:image_picker/image_picker.dart';
import '../services/storage_service.dart';
import '../services/review_service.dart';
import 'meetup_location_screen.dart';
import '../models/transaction_model.dart';
import '../services/transaction_service.dart';

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
  String? _otherUserName;
  String? _itemStatus;
  String? _transactionId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _transactionStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSubscription;

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
      _listenChatRoomInfo();
    });
  }

  void _listenChatRoomInfo() {
    debugPrint('[ChatScreen] _listenChatRoomInfo registering listener');
    _roomSubscription = FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(widget.roomId)
        .snapshots()
        .listen((roomDoc) {
      debugPrint('[ChatScreen] _listenChatRoomInfo snapshot received. exists: ${roomDoc.exists}');
      if (roomDoc.exists && mounted) {
        final data = roomDoc.data();
        final sellerId = data?['sellerId'];
        final buyerId = data?['buyerId'];
        final itemId = data?['itemId'];
        final itemTitle = data?['itemTitle'] ?? 'Item';
        final transactionId = data?['transactionId'];
        debugPrint('[ChatScreen] _listenChatRoomInfo data: sellerId=$sellerId, buyerId=$buyerId, itemId=$itemId, transactionId=$transactionId');

        setState(() {
          _sellerId = sellerId;
          _buyerId = buyerId;
          _itemTitle = itemTitle;
          if (transactionId != _transactionId) {
            debugPrint('[ChatScreen] _listenChatRoomInfo: transactionId changed from $_transactionId to $transactionId');
            _transactionId = transactionId;
            if (transactionId != null && transactionId.toString().isNotEmpty) {
              debugPrint('[ChatScreen] _listenChatRoomInfo: creating transaction stream for $transactionId');
              _transactionStream = FirebaseFirestore.instance
                  .collection('transactions')
                  .doc(transactionId.toString())
                  .snapshots();
            } else {
              _transactionStream = null;
            }
          }
        });

        _loadCounterpartNameAndItemStatus(sellerId, buyerId, itemId);
      }
    }, onError: (e) {
      debugPrint('Error listening to chat room info: $e');
    });
  }

  Future<void> _loadCounterpartNameAndItemStatus(
    String? sellerId,
    String? buyerId,
    String? itemId,
  ) async {
    debugPrint('[ChatScreen] _loadCounterpartNameAndItemStatus start. sellerId=$sellerId, buyerId=$buyerId, itemId=$itemId');
    try {
      String? otherUserName;
      String? itemStatus;

      if (user != null && sellerId != null && buyerId != null) {
        final otherUserId = user!.uid == sellerId ? buyerId : sellerId;
        debugPrint('[ChatScreen] Fetching counterpart user document for $otherUserId');
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(otherUserId)
            .get()
            .timeout(const Duration(seconds: 2));
        otherUserName = userDoc.data()?['name'];
        debugPrint('[ChatScreen] Fetching counterpart user finished. Name: $otherUserName');
      }

      if (itemId != null) {
        debugPrint('[ChatScreen] Fetching item document for $itemId');
        final itemDoc = await FirebaseFirestore.instance
            .collection('items')
            .doc(itemId)
            .get()
            .timeout(const Duration(seconds: 2));
        itemStatus = itemDoc.data()?['status'];
        debugPrint('[ChatScreen] Fetching item finished. Status: $itemStatus');
      }

      if (mounted) {
        debugPrint('[ChatScreen] Updating details state: otherUserName=$otherUserName, itemStatus=$itemStatus');
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
    _roomSubscription?.cancel();
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

  Future<void> _showCancelDialog() async {
    final controller = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Transaction?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please provide a reason for cancelling this deal:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'e.g., Changed mind, unresponsive partner...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, Keep Deal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please enter a cancellation reason.')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Yes, Cancel Deal'),
          ),
        ],
      ),
    );

    if (confirm == true && controller.text.trim().isNotEmpty && _transactionId != null) {
      try {
        await TransactionService.instance.cancelTransaction(
          transactionId: _transactionId!,
          actionUserId: user!.uid,
          roomId: widget.roomId,
          reason: controller.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaction successfully cancelled.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel: $e')),
          );
        }
      }
    }
  }

  Future<void> _pickAndUploadReceipt() async {
    if (user == null || _transactionId == null) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (picked == null) return;

      setState(() => _sending = true);
      final bytes = await picked.readAsBytes();

      // Compress and upload to storage: path: chat/{roomId}/receipts/
      final imageUrl = await StorageService.instance.uploadReceiptImage(
        roomId: widget.roomId,
        bytes: bytes,
      );

      // Save to transaction and send message card
      await TransactionService.instance.uploadPaymentReceipt(
        transactionId: _transactionId!,
        roomId: widget.roomId,
        actionUserId: user!.uid,
        receiptUrl: imageUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment receipt uploaded successfully!')),
        );
      }
    } catch (e) {
      debugPrint('Error uploading payment receipt: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload receipt: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _buildTransactionBanner() {
    debugPrint('[ChatScreen] _buildTransactionBanner logic check: _transactionId=$_transactionId, hasStream=${_transactionStream != null}');
    if (_transactionId == null || _transactionId!.isEmpty || _transactionStream == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _transactionStream,
      builder: (context, snapshot) {
        debugPrint('[ChatScreen] _buildTransactionBanner StreamBuilder builder. connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}, exists=${snapshot.data?.exists}, hasError=${snapshot.hasError}');
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.red.shade50,
            child: Text(
              'Error loading transaction info: ${snapshot.error}',
              style: TextStyle(color: Colors.red.shade900, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final tx = TransactionModel.fromFirestore(snapshot.data!);
        final status = tx.status;
        final meetupLocation = tx.meetupLocation;
        final meetupLat = tx.meetupLatitude;
        final meetupLng = tx.meetupLongitude;
        
        final buyerMeetupConfirmed = tx.buyerMeetupConfirmed;
        final sellerMeetupConfirmed = tx.sellerMeetupConfirmed;
        final receiptUploaded = tx.receiptUploaded;
        final paymentVerified = tx.paymentVerified;
        final receiptUrl = tx.receiptUrl;
        final finalPrice = tx.finalPrice;

        final isSeller = user!.uid == _sellerId;

        Color bannerColor = Colors.white;
        Color textColor = Colors.black;
        String title = '';
        String subtitle = '';
        List<Widget> actions = [];

        final isSafeZone = TransactionService.isSafeZone(meetupLat, meetupLng);

        switch (status) {
          case TransactionStatus.accepted:
            bannerColor = Colors.blue.shade50;
            textColor = Colors.blue.shade900;
            title = 'Deal Accepted! 🤝';
            
            if (meetupLocation.isEmpty) {
              subtitle = 'A meetup point needs to be selected to coordinate the transaction.';
              if (isSeller) {
                actions = [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.map, size: 16),
                    label: const Text('Suggest Meetup Location'),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MeetupLocationScreen(),
                        ),
                      );
                      if (result != null && result is Map) {
                        await TransactionService.instance.suggestMeetupLocation(
                          transactionId: _transactionId!,
                          locationName: result['location'],
                          latitude: result['latitude'],
                          longitude: result['longitude'],
                          actionUserId: user!.uid,
                          roomId: widget.roomId,
                        );
                      }
                    },
                  ),
                ];
              } else {
                actions = [
                  const Text('Awaiting seller to suggest meetup location...', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Colors.blueGrey)),
                ];
              }
            } else {
              final userConfirmed = isSeller ? sellerMeetupConfirmed : buyerMeetupConfirmed;
              final peerConfirmed = isSeller ? buyerMeetupConfirmed : sellerMeetupConfirmed;
              
              subtitle = 'Suggested Meetup: $meetupLocation\n';
              if (isSafeZone) {
                subtitle += '🛡️ UTHM Safe Zone Verified (Library/HEPA/Cafes)\n';
              }
              subtitle += 'Your confirmation: ${userConfirmed ? "Confirmed ✓" : "Pending"}\n'
                  'Partner confirmation: ${peerConfirmed ? "Confirmed ✓" : "Pending"}';

              actions = [
                if (!userConfirmed)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: const Text('Confirm Location'),
                    onPressed: () async {
                      await TransactionService.instance.confirmMeetupLocation(
                        transactionId: _transactionId!,
                        actionUserId: user!.uid,
                        roomId: widget.roomId,
                      );
                    },
                  ),
                if (!userConfirmed) const SizedBox(width: 8),
                if (isSeller)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.map, size: 16),
                    label: const Text('Suggest Different Location'),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MeetupLocationScreen(selected: meetupLocation),
                        ),
                      );
                      if (result != null && result is Map) {
                        await TransactionService.instance.suggestMeetupLocation(
                          transactionId: _transactionId!,
                          locationName: result['location'],
                          latitude: result['latitude'],
                          longitude: result['longitude'],
                          actionUserId: user!.uid,
                          roomId: widget.roomId,
                        );
                      }
                    },
                  ),
              ];
            }

            actions.add(const SizedBox(width: 8));
            actions.add(
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Cancel Deal'),
                onPressed: _showCancelDialog,
              ),
            );
            break;

          case TransactionStatus.meetup_pending:
            bannerColor = Colors.orange.shade50;
            textColor = Colors.orange.shade900;
            title = 'Meetup Confirmed 📍';
            subtitle = 'Location: $meetupLocation\n';
            if (isSafeZone) {
              subtitle += '🛡️ UTHM Safe Zone Verified\n';
            }

            if (!paymentVerified) {
              if (!receiptUploaded) {
                subtitle += 'Payment Status: Awaiting DuitNow transfer of RM ${finalPrice.toStringAsFixed(2)}.';
                if (!isSeller) {
                  actions = [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.receipt_long, size: 16),
                      label: const Text('Upload DuitNow Receipt'),
                      onPressed: _pickAndUploadReceipt,
                    ),
                  ];
                } else {
                  actions = [
                    const Text('Awaiting buyer to upload payment receipt...', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Colors.blueGrey)),
                  ];
                }
              } else {
                subtitle += 'Payment Status: Receipt uploaded. Seller verification required.';
                if (isSeller) {
                  actions = [
                    if (receiptUrl != null)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('View Receipt'),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              content: Image.network(receiptUrl),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('Verify Payment'),
                      onPressed: () async {
                        await TransactionService.instance.verifyPayment(
                          transactionId: _transactionId!,
                          roomId: widget.roomId,
                          actionUserId: user!.uid,
                        );
                      },
                    ),
                  ];
                } else {
                  actions = [
                    const Text('Awaiting seller verification of your receipt...', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Colors.blueGrey)),
                  ];
                }
              }
            } else {
              subtitle += 'Payment Status: Verified! Meet up now to collect your item.';
              if (!isSeller) {
                actions = [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text('Confirm Item Received'),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Confirm Item Collection?'),
                          content: const Text(
                            'Please only confirm if you have received the item and are satisfied with it. This action cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await TransactionService.instance.completeTransaction(
                          transactionId: _transactionId!,
                          roomId: widget.roomId,
                          actionUserId: user!.uid,
                        );
                      }
                    },
                  ),
                ];
              } else {
                actions = [
                  const Text('Awaiting buyer to confirm receipt of item...', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Colors.blueGrey)),
                ];
              }
            }

            actions.add(const SizedBox(width: 8));
            actions.add(
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Cancel Deal'),
                onPressed: _showCancelDialog,
              ),
            );
            break;

          case TransactionStatus.completed:
            bannerColor = Colors.green.shade50;
            textColor = Colors.green.shade900;
            title = 'Deal Completed 🎉';
            subtitle = 'Item successfully handed over and payment verified.';
            actions = [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.rate_review, size: 16),
                label: const Text('Leave a Review'),
                onPressed: () => _showReviewDialog(),
              ),
            ];
            break;

          case TransactionStatus.cancelled:
            bannerColor = Colors.red.shade50;
            textColor = Colors.red.shade900;
            title = 'Deal Cancelled ❌';
            final cancelledBy = tx.cancelledBy;
            final reason = tx.cancelledReason ?? '';
            subtitle = 'Cancelled by: ${cancelledBy == user!.uid ? "You" : "Partner"}\nReason: $reason';
            actions = [];
            break;

          default:
        }
 
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bannerColor,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.black87, fontSize: 12, height: 1.4),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: actions),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[ChatScreen] build() called. _otherUserName=$_otherUserName, _itemTitle=$_itemTitle');
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
            _buildTransactionBanner(),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _messagesStream,
                builder: (context, snapshot) {
                  debugPrint('[ChatScreen] Messages StreamBuilder builder. connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}, count=${snapshot.data?.docs.length}, hasError=${snapshot.hasError}');
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
                      debugPrint('[ChatScreen] Rendering message index=$i, type=$type, text=${text.length > 30 ? text.substring(0, 30) + "..." : text}');

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
