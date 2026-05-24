import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/item_model.dart';

class ItemService {
  ItemService._();
  static final ItemService instance = ItemService._();

  final _itemsRef = FirebaseFirestore.instance.collection('items');

  /// Get paginated items for home feed — DETERMINISTIC sort.
  ///
  /// Sort order (enforced by service layer, NOT in UI):
  /// 1. Boosted items first (by boostedAt DESC, then createdAt DESC)
  /// 2. Non-boosted items (by createdAt DESC)
  Future<Map<String, dynamic>> getHomeFeed({
    String? category,
    String? meetupLocation,
    int limit = 15,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _itemsRef;
      query = query.where('status', isEqualTo: 'available');
      query = query.orderBy('createdAt', descending: true);
      query = query.limit(limit);

      if (category != null && category.isNotEmpty) {
        query = query.where('category', isEqualTo: category);
      }
      if (meetupLocation != null && meetupLocation.isNotEmpty) {
        query = query.where('meetupLocation', isEqualTo: meetupLocation);
      }
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snapshot = await query.get();

      var items = snapshot.docs
          .map((doc) {
            try {
              return ItemModel.fromFirestore(doc);
            } catch (e) {
              debugPrint('Error parsing item: $e');
              return null;
            }
          })
          .whereType<ItemModel>()
          .toList();

      // DETERMINISTIC sort: boosted first, then by date
      items.sort((a, b) {
        if (a.isBoosted != b.isBoosted) {
          return a.isBoosted ? -1 : 1;
        }
        // Both boosted: sort by boostedAt DESC (fallback to createdAt)
        if (a.isBoosted && b.isBoosted) {
          final aTime = a.boostedAt ?? a.createdAt;
          final bTime = b.boostedAt ?? b.createdAt;
          return bTime.compareTo(aTime);
        }
        // Both non-boosted: sort by createdAt DESC
        return b.createdAt.compareTo(a.createdAt);
      });

      return {
        'items': items,
        'lastDocument': items.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      debugPrint('Error in getHomeFeed: $e');
      return {'items': [], 'lastDocument': null};
    }
  }

  /// Get paginated items for home feed (ONE read operation)
  /// Uses .get() instead of .snapshots() to reduce reads
  Future<Map<String, dynamic>> getItems({
    String? category,
    String? meetupLocation,
    int limit = 15,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      // OPTIMIZED: Build query with minimal filters for faster response
      Query<Map<String, dynamic>> query = _itemsRef;

      // Only filter by status (indexed field)
      query = query.where('status', isEqualTo: 'available');

      // Order by creation time (needs composite index with status)
      query = query.orderBy('createdAt', descending: true);

      // Apply pagination
      query = query.limit(limit);

      // Apply category filter if specified (client-side filtering is faster for initial load)
      if (category != null && category.isNotEmpty) {
        query = query.where('category', isEqualTo: category);
      }

      // Apply meetup location filter if specified
      if (meetupLocation != null && meetupLocation.isNotEmpty) {
        query = query.where('meetupLocation', isEqualTo: meetupLocation);
      }

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final stopwatch = Stopwatch()..start();
      final snapshot = await query.get();
      stopwatch.stop();

      debugPrint(
        'Firestore query took ${stopwatch.elapsedMilliseconds}ms, returned ${snapshot.docs.length} items',
      );

      final items = snapshot.docs
          .map((doc) {
            try {
              return ItemModel.fromFirestore(doc);
            } catch (e) {
              debugPrint('Error parsing item: $e');
              return null;
            }
          })
          .whereType<ItemModel>()
          .toList();

      // Return items and last document for pagination
      return {
        'items': items,
        'lastDocument': items.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      debugPrint('Error in getItems: $e');
      return {'items': [], 'lastDocument': null};
    }
  }

  /// Stream a seller's available listings (for SellerProfileScreen).
  /// Requires composite index: sellerId ASC, status ASC, createdAt DESC.
  Stream<List<ItemModel>> watchSellerListings(String sellerId) {
    return _itemsRef
        .where('sellerId', isEqualTo: sellerId)
        .where('status', isEqualTo: 'available')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            try {
              return ItemModel.fromFirestore(doc);
            } catch (_) {
              return null;
            }
          })
          .whereType<ItemModel>()
          .toList();
    });
  }

  /// Get real-time items only when needed (chat, inbox updates)
  Stream<List<ItemModel>> watchItems({String? sellerId, int limit = 20}) {
    try {
      Query<Map<String, dynamic>> query = _itemsRef
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (sellerId != null) {
        query = query.where('sellerId', isEqualTo: sellerId);
      }

      return query.snapshots().map((snapshot) {
        return snapshot.docs
            .map((doc) {
              try {
                return ItemModel.fromFirestore(doc);
              } catch (_) {
                return null;
              }
            })
            .whereType<ItemModel>()
            .toList();
      });
    } catch (e) {
      return const Stream.empty();
    }
  }

  /// Get single item details (ONE read)
  Future<ItemModel?> getItem(String itemId) async {
    try {
      final doc = await _itemsRef.doc(itemId).get();
      if (!doc.exists) return null;
      return ItemModel.fromFirestore(doc);
    } catch (e) {
      return null;
    }
  }

  /// Watch single item (only for item detail screen with offers)
  Stream<ItemModel?> watchItem(String itemId) {
    return _itemsRef.doc(itemId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ItemModel.fromFirestore(doc);
    });
  }

  /// Create item with seller snapshot embedded (avoids future joins)
  Future<String> createItem({
    required String itemId,
    required String sellerId,
    required String sellerName,
    required String sellerImage,
    required String sellerStudentId,
    required String title,
    required String description,
    required double price,
    required String category,
    required String condition,
    required String meetupLocation,
    double meetupLatitude = 0.0,
    double meetupLongitude = 0.0,
    required List<String> images,
    bool isBoosted = false,
  }) async {
    final thumbnail = images.isNotEmpty ? images.first : '';

    final itemData = ItemModel(
      id: itemId,
      sellerId: sellerId,
      sellerName: sellerName,
      sellerImage: sellerImage,
      sellerStudentId: sellerStudentId,
      title: title,
      description: description,
      price: price,
      category: category,
      condition: condition,
      meetupLocation: meetupLocation,
      meetupLatitude: meetupLatitude,
      meetupLongitude: meetupLongitude,
      thumbnail: thumbnail,
      images: images,
      createdAt: DateTime.now(),
      isBoosted: isBoosted,
    );

    await _itemsRef.doc(itemId).set(itemData.toFirestore());
    return itemId;
  }

  /// Update item status (sold, reserved, etc)
  Future<void> updateItemStatus(String itemId, String status) async {
    await _itemsRef.doc(itemId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete item
  Future<void> deleteItem(String itemId) async {
    await _itemsRef.doc(itemId).delete();
  }
}
