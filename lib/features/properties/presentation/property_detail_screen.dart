import 'package:flutter/material.dart';

import '../../../core/config/business_config.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../checkout/presentation/checkout_screen.dart';
import '../domain/property.dart';
import 'widgets/property_photo.dart';

class PropertyDetailScreen extends StatelessWidget {
  const PropertyDetailScreen({
    required this.property,
    required this.store,
    super.key,
  });

  final Property property;
  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final bookable =
            property.businessModel == PropertyBusinessModel.bookable;
        final unlocked = store.isUnlocked(property.id);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Property details'),
            actions: [
              IconButton(
                tooltip: store.savedPropertyIds.contains(property.id)
                    ? 'Remove saved property'
                    : 'Save property',
                onPressed: () async {
                  try {
                    await store.toggleSaved(property.id);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                },
                icon: Icon(
                  store.savedPropertyIds.contains(property.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          PropertyPhoto(
                            imageUrl: property.imageUrl,
                            height: 300,
                          ),
                          Positioned(
                            top: 14,
                            left: 14,
                            child: _BusinessBadge(
                              bookable: bookable,
                              label: bookable ? 'BOOKABLE' : 'CONTACT UNLOCK',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                property.name,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                property.generalLocation,
                                style: const TextStyle(color: HavenTheme.muted),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.star_rounded, color: HavenTheme.teal),
                        const SizedBox(width: 4),
                        Text('${property.rating} (${property.reviewCount})'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _VerificationChip(
                          label: 'Property',
                          status: property.propertyVerification,
                        ),
                        _VerificationChip(
                          label: 'Owner / agent',
                          status: property.ownerVerification,
                        ),
                        Chip(
                          avatar: Icon(
                            property.available
                                ? Icons.check_circle_outline
                                : Icons.event_busy,
                            size: 17,
                            color: property.available
                                ? HavenTheme.forest
                                : Colors.red,
                          ),
                          label: Text(
                            property.available ? 'Available' : 'Unavailable',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _DetailSection(
                      title: bookable ? 'About this stay' : 'About this rental',
                      child: Text(
                        property.description,
                        style: const TextStyle(height: 1.55),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DetailSection(
                      title: 'Property details',
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 14,
                        children: [
                          _Fact(
                            icon: Icons.bed_outlined,
                            label: '${property.bedrooms} bedrooms',
                          ),
                          _Fact(
                            icon: Icons.bathtub_outlined,
                            label: '${property.bathrooms} bathrooms',
                          ),
                          _Fact(
                            icon: Icons.chair_outlined,
                            label: property.furnished
                                ? 'Furnished'
                                : 'Unfurnished',
                          ),
                          if (property.parking)
                            const _Fact(
                              icon: Icons.local_parking,
                              label: 'Parking',
                            ),
                          if (property.water)
                            const _Fact(
                              icon: Icons.water_drop_outlined,
                              label: 'Water',
                            ),
                          if (property.electricity)
                            const _Fact(
                              icon: Icons.bolt_outlined,
                              label: 'Electricity',
                            ),
                          if (property.security)
                            const _Fact(
                              icon: Icons.shield_outlined,
                              label: 'Security',
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DetailSection(
                      title: 'Amenities',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: property.amenities
                            .map((item) => Chip(label: Text(item)))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (bookable)
                      _DetailSection(
                        title: 'Hosted by ${property.managerName}',
                        child: const Text(
                          'Your property manager can help with your stay. Contact details are shared after a confirmed booking.',
                        ),
                      )
                    else
                      _RentalContactPanel(
                        property: property,
                        store: store,
                        unlocked: unlocked,
                      ),
                    const SizedBox(height: 22),
                    _DetailSection(
                      title: 'Guest reviews',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: HavenTheme.teal,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${property.rating} out of 5 · ${property.reviewCount} reviews',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatTzs(property.priceTzs),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            property.pricePeriod,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: property.available
                          ? () => _continue(context, bookable, unlocked)
                          : null,
                      icon: Icon(
                        bookable
                            ? Icons.calendar_month_outlined
                            : Icons.lock_open_outlined,
                      ),
                      label: Text(
                        bookable
                            ? 'Book now'
                            : unlocked
                            ? 'View contact'
                            : 'Unlock location & contact',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _continue(BuildContext context, bool bookable, bool unlocked) {
    if (bookable || !unlocked) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              CheckoutScreen(property: property, store: store),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FutureBuilder<OwnerContact?>(
          future: store.contactFor(property.id),
          builder: (context, snapshot) {
            final contact = snapshot.data;
            if (contact == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unlocked owner contact',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(contact.exactAddress),
                  Text('${contact.contactName} · ${contact.role}'),
                  Text(contact.phone),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RentalContactPanel extends StatelessWidget {
  const _RentalContactPanel({
    required this.property,
    required this.store,
    required this.unlocked,
  });

  final Property property;
  final HavenLinkStore store;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    if (!unlocked) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline, color: HavenTheme.forest),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exact location & contact locked',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The verified property owner or authorized agent’s contact stays private until you unlock this listing.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Unlock fee: ${formatTzs(BusinessConfig.defaultUnlockFeeTzs)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<OwnerContact?>(
      future: store.contactFor(property.id),
      builder: (context, snapshot) {
        final contact = snapshot.data;
        if (contact == null) return const LinearProgressIndicator();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Exact location and authorized contact unlocked'),
                const SizedBox(height: 10),
                Text(contact.exactAddress),
                Text('${contact.contactName} · ${contact.role}'),
                Text(contact.phone),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BusinessBadge extends StatelessWidget {
  const _BusinessBadge({required this.bookable, required this.label});

  final bool bookable;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            bookable ? Icons.event_available : Icons.key,
            size: 16,
            color: HavenTheme.forest,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _VerificationChip extends StatelessWidget {
  const _VerificationChip({required this.label, required this.status});

  final String label;
  final VerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final verified = status == VerificationStatus.verified;
    final pending = status == VerificationStatus.pending;
    return Chip(
      avatar: Icon(
        verified
            ? Icons.verified
            : pending
            ? Icons.pending_outlined
            : Icons.info_outline,
        size: 17,
        color: verified ? HavenTheme.forest : HavenTheme.muted,
      ),
      label: Text(
        '$label · ${verified
            ? 'Verified'
            : pending
            ? 'Pending'
            : 'Not verified'}',
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: HavenTheme.forest),
        const SizedBox(width: 7),
        Text(label),
      ],
    );
  }
}
