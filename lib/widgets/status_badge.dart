import 'package:flutter/material.dart';

import '../models/transaction_model.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final TransactionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TransactionStatus.pending => Colors.orange,
      TransactionStatus.accepted => Colors.blue,
      TransactionStatus.rejected => Colors.red,
      TransactionStatus.completed => Colors.green,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          color: color.shade700,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}
