import 'package:flutter/material.dart';

/// Reusable visual distinction for Premium sellers across cards, profiles,
/// chat, and item detail surfaces.
class PremiumBadge extends StatefulWidget {
  const PremiumBadge({super.key, this.compact = false});

  final bool compact;

  @override
  State<PremiumBadge> createState() => _PremiumBadgeState();
}

class _PremiumBadgeState extends State<PremiumBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    // Interactive media element: subtle premium badge pulse animation.
    _pulseAnim = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.compact ? 'Premium' : 'Premium Seller';
    final iconSize = widget.compact ? 11.0 : 16.0;
    final fontSize = widget.compact ? 9.5 : 12.0;
    final padding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 11, vertical: 5);

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        return Transform.scale(scale: _pulseAnim.value, child: child);
      },
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.amber.shade300, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_rounded,
              size: iconSize,
              color: Colors.amber.shade800,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: Colors.amber.shade900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
