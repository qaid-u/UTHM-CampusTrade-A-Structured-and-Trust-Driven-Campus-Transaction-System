import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
      avatar: Icon(
        _iconFor(label),
        size: 17,
        color: selected ? Colors.white : AppColors.electricBlue,
      ),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: selected ? Colors.white : AppColors.navy,
        fontWeight: FontWeight.w800,
      ),
      backgroundColor: Colors.white,
      selectedColor: AppColors.red,
      side: BorderSide(color: selected ? AppColors.red : AppColors.border),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      shape: const StadiumBorder(),
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
