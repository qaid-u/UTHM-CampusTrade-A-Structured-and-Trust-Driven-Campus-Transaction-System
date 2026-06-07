import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/item_model.dart';
import '../theme/app_theme.dart';
import 'premium_badge.dart';

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, required this.onTap});

  final ItemModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.thumbnail;
    final hasImage = imageUrl.isNotEmpty;
    final showPremiumTreatment = item.isBoosted || item.sellerIsPremium;

    // Interactive media element: item cards fade/slide in lightly on build.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: showPremiumTreatment
              ? [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.22),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ]
              : AppShadows.softBlue,
        ),
        child: Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
            side: BorderSide(
              color: showPremiumTreatment
                  ? Colors.amber.shade300
                  : AppColors.border,
              width: showPremiumTreatment ? 1.4 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: 116,
                      width: double.infinity,
                      child: !hasImage
                          ? const _ImageLabel(label: 'NO IMAGE')
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.electricBlue,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) =>
                                  const _ImageLabel(label: 'ERROR'),
                              fadeInDuration: const Duration(milliseconds: 300),
                              fadeOutDuration: const Duration(
                                milliseconds: 200,
                              ),
                            ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33E3223A),
                              blurRadius: 14,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Text(
                          'RM ${item.price.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: AppColors.electricBlue,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              [
                                item.condition,
                                item.sellerName,
                              ].where((e) => e.isNotEmpty).join(' | '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      if (showPremiumTreatment)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              const PremiumBadge(compact: true),
                              if (item.isBoosted) ...[
                                const SizedBox(width: 6),
                                Text(
                                  'Boosted',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 15,
                            color: AppColors.red,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.meetupLocation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageLabel extends StatelessWidget {
  const _ImageLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.blueSurface),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
