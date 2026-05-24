import 'package:flutter/material.dart';
import '../models/review_model.dart';

/// Displays a single anonymous review.
///
/// Shows only: star rating, "Verified Transaction" badge, and date.
/// No reviewer identity (name, image, ID) is ever shown.
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review});

  final ReviewModel review;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Star rating
            Row(
              children: List.generate(5, (i) {
                return Icon(
                  i < review.rating ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 22,
                  color: Colors.amber,
                );
              }),
            ),
            const SizedBox(height: 8),

            // Verified Transaction badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green.shade200, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: Colors.green.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Verified Transaction',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),

            if (review.comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                review.comment,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ],

            const SizedBox(height: 6),

            // Date
            Text(
              _formatDate(review.createdAt),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}
