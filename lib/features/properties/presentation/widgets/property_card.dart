import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

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
    final multiRoomStay =
        property.businessModel == PropertyBusinessModel.bookable &&
        const {
          PropertyCategory.hotel,
          PropertyCategory.motel,
          PropertyCategory.lodge,
        }.contains(property.category);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: HavenTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                PropertyPhoto(imageUrl: property.imageUrl, height: 176),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _StatusBadge(
                    icon: multiRoomStay && property.isVerified
                        ? HavenIcons.verified
                        : property.businessModel ==
                              PropertyBusinessModel.bookable
                        ? HavenIcons.eventAvailableOutlined
                        : HavenIcons.keyOutlined,
                    label: multiRoomStay && property.isVerified
                        ? 'Verified ${_stayType(property.category)}'
                        : property.businessModel ==
                              PropertyBusinessModel.bookable
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
                        saved ? HavenIcons.favorite : HavenIcons.favoriteBorder,
                        color: saved ? Colors.red.shade700 : HavenTheme.ink,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          property.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (property.businessModel ==
                              PropertyBusinessModel.bookable &&
                          property.reviewCount > 0) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          HavenIcons.starRounded,
                          size: 15,
                          color: HavenTheme.gold,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          property.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
                  if (multiRoomStay)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: property.amenities
                          .take(4)
                          .map(
                            (amenity) => Chip(
                              label: Text(amenity),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                          )
                          .toList(growable: false),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _Stat(
                          icon: HavenIcons.bedOutlined,
                          label: '${property.bedrooms} bed',
                        ),
                        const SizedBox(width: 14),
                        if (property.maxGuests != null) ...[
                          _Stat(
                            icon: HavenIcons.peopleOutline,
                            label: '${property.maxGuests} guests',
                          ),
                          const SizedBox(width: 14),
                        ],
                        _Stat(
                          icon: HavenIcons.bathtubOutlined,
                          label: '${property.bathrooms} bath',
                        ),
                        if (property.isVerified)
                          const Icon(
                            HavenIcons.verified,
                            size: 18,
                            color: HavenTheme.forest,
                          ),
                      ],
                    ),
                  const Divider(height: 28, color: HavenTheme.border),
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
                      if (multiRoomStay)
                        TextButton.icon(
                          onPressed: onTap,
                          iconAlignment: IconAlignment.end,
                          icon: const Icon(HavenIcons.arrowForward, size: 17),
                          label: Text('View', maxLines: 1),
                        )
                      else
                        const Icon(
                          HavenIcons.arrowForward,
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

String _stayType(PropertyCategory category) => switch (category) {
  PropertyCategory.hotel => 'Hotel',
  PropertyCategory.motel => 'Motel',
  PropertyCategory.lodge => 'Lodge',
  _ => 'Stay',
};

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
