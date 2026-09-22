import 'package:flutter/material.dart';

import '../../../../core/formatters/currency_formatter.dart';
import '../../../../core/state/haven_link_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/property.dart';
import 'property_photo.dart';

class PropertyCard extends StatelessWidget {
  const PropertyCard({
    required this.property,
    required this.store,
    required this.onTap,
    super.key,
  });

  final Property property;
  final HavenLinkStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final saved = store.savedPropertyIds.contains(property.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                PropertyPhoto(imageUrl: property.imageUrl, height: 190),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _StatusBadge(
                    icon:
                        property.businessModel == PropertyBusinessModel.bookable
                        ? Icons.event_available_outlined
                        : Icons.key_outlined,
                    label:
                        property.businessModel == PropertyBusinessModel.bookable
                        ? 'Book directly'
                        : 'Contact unlock',
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.94),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: saved
                          ? 'Remove saved property'
                          : 'Save property',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        try {
                          await store.toggleSaved(property.id);
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      },
                      icon: Icon(
                        saved ? Icons.favorite : Icons.favorite_border,
                        color: saved ? Colors.red.shade700 : HavenTheme.ink,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          property.name,
                          style: Theme.of(context).textTheme.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.star_rounded,
                        size: 17,
                        color: HavenTheme.teal,
                      ),
                      Text(property.rating.toStringAsFixed(1)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    property.generalLocation,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: HavenTheme.muted),
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      _Stat(
                        icon: Icons.bed_outlined,
                        label: '${property.bedrooms} bed',
                      ),
                      const SizedBox(width: 14),
                      _Stat(
                        icon: Icons.bathtub_outlined,
                        label: '${property.bathrooms} bath',
                      ),
                      const Spacer(),
                      if (property.isVerified)
                        const Icon(
                          Icons.verified,
                          size: 18,
                          color: HavenTheme.forest,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: formatTzs(property.priceTzs),
                            style: const TextStyle(
                              color: HavenTheme.forest,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                            children: [
                              TextSpan(
                                text: property.pricePeriod,
                                style: const TextStyle(
                                  color: HavenTheme.muted,
                                  fontWeight: FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: HavenTheme.forest,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: HavenTheme.forest),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: HavenTheme.muted),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
