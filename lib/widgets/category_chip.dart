import 'package:flutter/material.dart';

class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      avatar: Icon(_iconFor(label), size: 17),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'Textbooks':
        return Icons.menu_book_rounded;
      case 'Electronics':
        return Icons.devices_rounded;
      case 'Clothes':
        return Icons.checkroom_rounded;
      case 'Room Items':
        return Icons.weekend_rounded;
      case 'Sports':
        return Icons.sports_soccer_rounded;
      default:
        return Icons.category_rounded;
    }
  }
}
