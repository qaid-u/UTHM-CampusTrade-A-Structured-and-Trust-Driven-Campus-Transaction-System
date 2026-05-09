import '../models/item_model.dart';

class RecommendationService {
  List<ItemModel> recommend({
    required List<ItemModel> items,
    required String? viewedCategory,
    required String? meetupLocation,
    required String currentUserId,
  }) {
    final filtered = items
        .where((item) => item.sellerId != currentUserId)
        .where(
          (item) => viewedCategory == null || item.category == viewedCategory,
        )
        .toList();
    filtered.sort((a, b) {
      final locationScoreA = a.meetupLocation == meetupLocation ? 0 : 1;
      final locationScoreB = b.meetupLocation == meetupLocation ? 0 : 1;
      final locationCompare = locationScoreA.compareTo(locationScoreB);
      if (locationCompare != 0) return locationCompare;
      return a.price.compareTo(b.price);
    });
    return filtered.take(5).toList();
  }
}
