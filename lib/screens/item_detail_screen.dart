import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/offer_service.dart';
import '../models/user_model.dart';
import 'chat_screen.dart';

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  Future<UserModel?> _getSeller(String sellerId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(sellerId)
          .get();

      if (!doc.exists || doc.data() == null) return null;

      return UserModel.fromJson(doc.data()!);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('items')
          .doc(itemId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.data!.exists) {
          return const Scaffold(body: Center(child: Text("Item not found")));
        }

        final data = snapshot.data!.data()!;

        final title = data['title'] ?? 'Untitled';
        final description = data['description'] ?? '';
        final price = (data['price'] ?? 0).toDouble();
        final sellerId = data['sellerId'] ?? '';
        final meetupLocation = data['meetupLocation'] ?? '';

        /// 🔥 FIX: ALWAYS USE images[]
        final List images = data['images'] ?? [];

        final isOwner = currentUser.uid == sellerId;

        return Scaffold(
          appBar: AppBar(title: Text(title)),

          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---------------- IMAGE CAROUSEL ----------------
                Container(
                  height: 260,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.grey.shade200,
                  ),
                  clipBehavior: Clip.antiAlias,

                  child: images.isEmpty
                      ? const Center(child: Icon(Icons.image_not_supported))
                      : PageView.builder(
                          itemCount: images.length,
                          itemBuilder: (context, index) {
                            final url = images[index];

                            return Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image),
                            );
                          },
                        ),
                ),

                const SizedBox(height: 16),

                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  "RM ${price.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                if (description.isNotEmpty) ...[
                  const Text(
                    "Description",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(description),
                  const SizedBox(height: 16),
                ],

                if (meetupLocation.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.location_on),
                      const SizedBox(width: 6),
                      Expanded(child: Text(meetupLocation)),
                    ],
                  ),

                const SizedBox(height: 20),

                // ---------------- SELLER ----------------
                FutureBuilder<UserModel?>(
                  future: _getSeller(sellerId),
                  builder: (context, snap) {
                    final seller = snap.data;

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Seller",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(seller?.name ?? "Unknown"),
                          Text(seller?.studentId ?? ""),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

                // ---------------- ACTIONS ----------------
                if (isOwner)
                  const Center(child: Text("This is your listing"))
                else
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _makeOffer(context, data),
                          child: const Text("Make Offer"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final roomId = await ChatService.getOrCreateRoom(
                              itemId: itemId,
                              itemTitle: title,
                              itemThumbnail: images.isNotEmpty
                                  ? images.first.toString()
                                  : '',
                              buyerId: currentUser.uid,
                              sellerId: sellerId,
                            );

                            if (!context.mounted) return;

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(roomId: roomId),
                              ),
                            );
                          },
                          child: const Text("Chat"),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _makeOffer(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final controller = TextEditingController();

    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Make Offer"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, double.tryParse(controller.text));
            },
            child: const Text("Submit"),
          ),
        ],
      ),
    );

    if (result == null) return;

    final currentUser = AuthService.instance.currentUser!;
    final title = item['title'] ?? 'Untitled';
    final sellerId = item['sellerId'];

    // 🔥 Extract first image for thumbnail safely
    final List images = item['images'] ?? [];
    final itemThumbnail = images.isNotEmpty ? images.first.toString() : '';

    final roomId = await ChatService.getOrCreateRoom(
      itemId: itemId,
      itemTitle: title,
      itemThumbnail: itemThumbnail,
      buyerId: currentUser.uid,
      sellerId: sellerId,
    );

    await OfferService.createOffer(
      roomId: roomId,
      itemId: itemId,
      itemTitle: title,
      buyerId: currentUser.uid,
      sellerId: sellerId,
      price: result,
    );

    await NotificationService.instance.notifyUser(
      userId: sellerId,
      title: "New Offer",
      body: "RM ${result.toStringAsFixed(2)}",
    );

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(roomId: roomId)),
    );
  }
}
