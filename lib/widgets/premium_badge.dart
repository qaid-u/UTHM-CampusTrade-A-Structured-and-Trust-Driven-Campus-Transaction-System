import 'package:flutter/material.dart';

/// Displays a "Premium Seller" badge with a verified/crown icon.
///
/// Use [compact] for small spaces (ItemCard, ChatRoomTile).
/// Default (non-compact) for profile screens and detail views.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.amber.shade300, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_rounded,
              size: 10,
              color: Colors.amber.shade700,
            ),
            const SizedBox(width: 2),
            Text(
              'Premium',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.amber.shade800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_rounded,
            size: 16,
            color: Colors.amber.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            'Premium Seller',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.amber.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
