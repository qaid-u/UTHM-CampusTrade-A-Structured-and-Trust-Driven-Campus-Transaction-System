import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/chat_room_tile.dart';
import 'chat_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  int _unreadCount = 0;
  bool _initialLoadDone = false;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _chatRoomsStream;
  StreamSubscription<int>? _unreadSub;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _chatRoomsStream = _getChatRoomsStream(user.uid);
    }

    if (user != null) {
      _unreadSub = NotificationService.instance
          .unreadCountStream(user.uid)
          .listen((count) {
            if (mounted) setState(() => _unreadCount = count);
          });
    }

    // Mark initial load done quickly
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _initialLoadDone = true);
      }
    });
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Please log in to view chats")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chats"),
        actions: [
          // Unread messages badge
          if (_unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _unreadCount > 99 ? '99+' : '$_unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Try query with index first, fallback to client-side filtering
        stream: _chatRoomsStream,
        builder: (context, snapshot) {
          // Show brief loading indicator initially (200ms max)
          if (!_initialLoadDone && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Handle errors
          if (snapshot.hasError) {
            debugPrint('Chat rooms query error: ${snapshot.error}');

            // If it's an index error, try fallback approach
            final errorStr = snapshot.error.toString();
            if (errorStr.contains('index') || errorStr.contains('composite')) {
              debugPrint('Index not found, using fallback query');
              return _buildFallbackChatList(user.uid);
            }

            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text("Unable to load chats"),
                  const SizedBox(height: 8),
                  Text(
                    errorStr,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
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
            return const Center(child: CircularProgressIndicator());
          }

          final rooms = snapshot.data!.docs;
          debugPrint('Found ${rooms.length} chat rooms for user ${user.uid}');

          // Sort by updatedAt client-side (avoids composite index requirement)
          rooms.sort((a, b) {
            final aVal = a.data()['updatedAt'];
            final bVal = b.data()['updatedAt'];

            DateTime? aTime;
            if (aVal is Timestamp) {
              aTime = aVal.toDate();
            } else if (aVal is DateTime) {
              aTime = aVal;
            }

            DateTime? bTime;
            if (bVal is Timestamp) {
              bTime = bVal.toDate();
            } else if (bVal is DateTime) {
              bTime = bVal;
            }

            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          if (rooms.isEmpty) {
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
                    "No chats yet",
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Start a conversation by messaging a seller!",
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          return _buildChatList(rooms, user.uid);
        },
      ),
    );
  }

  // Fallback method that doesn't require composite index
  Widget _buildFallbackChatList(String userId) {
    // Use two separate queries (buyerId OR sellerId) - these are indexed!
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _getUserChatRoomsFast(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final userRooms = snapshot.data!;
        debugPrint('Fallback fast: Found ${userRooms.length} chat rooms');

        if (userRooms.isEmpty) {
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
                const Text("No chats yet"),
              ],
            ),
          );
        }

        return _buildChatList(userRooms, userId);
      },
    );
  }

  // Fast fallback: Query by buyerId or sellerId (single field indexes)
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _getUserChatRoomsFast(String userId) async {
    try {
      // Run both queries in parallel
      final buyerQuery = FirebaseFirestore.instance
          .collection('chatRooms')
          .where('buyerId', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 2));

      final sellerQuery = FirebaseFirestore.instance
          .collection('chatRooms')
          .where('sellerId', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 2));

      // Wait for both queries
      final results = await Future.wait([buyerQuery, sellerQuery]);

      // Combine and deduplicate
      final allRooms = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

      for (final doc in results[0].docs) {
        allRooms[doc.id] = doc;
      }
      for (final doc in results[1].docs) {
        allRooms[doc.id] = doc;
      }

      // Sort by updatedAt
      final sortedRooms = allRooms.values.toList();
      sortedRooms.sort((a, b) {
        final aVal = a.data()['updatedAt'];
        final bVal = b.data()['updatedAt'];

        DateTime? aTime;
        if (aVal is Timestamp) {
          aTime = aVal.toDate();
        } else if (aVal is DateTime) {
          aTime = aVal;
        }

        DateTime? bTime;
        if (bVal is Timestamp) {
          bTime = bVal.toDate();
        } else if (bVal is DateTime) {
          bTime = bVal;
        }

        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return sortedRooms;
    } catch (e) {
      return [];
    }
  }

  Widget _buildChatList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> rooms,
    String currentUserId,
  ) {
    return ListView.builder(
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index].data();
        final roomId = rooms[index].id;

        debugPrint(
          'Chat room: $roomId - ${room['itemTitle']} - Last msg: ${room['lastMessage']}',
        );

        return Dismissible(
          key: ValueKey(roomId),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDeleteChat(roomId),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red.shade600,
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          child: ChatRoomTile(
            room: room,
            roomId: roomId,
            currentUserId: currentUserId,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatScreen(roomId: roomId)),
              );
            },
          ),
        );
      },
    );
  }

  Future<bool> _confirmDeleteChat(String roomId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chat?'),
        content: const Text(
          'This will delete the chat room and its messages from Firebase. '
          'Only use this when you no longer need the conversation history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await ChatService.deleteChatRoomForUser(roomId: roomId, userId: user.uid);
      await StorageService.instance.deleteChatAssets(roomId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chat deleted')));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete chat: $e')));
      }
      return false;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getChatRoomsStream(
    String userId,
  ) {
    // No orderBy to avoid requiring a composite index.
    // Sorting is done client-side in the StreamBuilder builder.
    return FirebaseFirestore.instance
        .collection('chatRooms')
        .where('participantIds', arrayContains: userId)
        .limit(30)
        .snapshots();
  }
}
