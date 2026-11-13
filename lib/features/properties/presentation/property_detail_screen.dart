import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/customer_data_repository.dart';
import '../../account/presentation/rental_messages_screen.dart';
import '../../checkout/presentation/checkout_screen.dart';
import '../domain/property.dart';
import '../../reviews/presentation/property_reviews_section.dart';
import 'widgets/property_extras.dart';

class PropertyDetailScreen extends StatelessWidget {
  const PropertyDetailScreen({
    required this.property,
    required this.store,
    this.initialDates,
    super.key,
  });

  final Property property;
  final HavenLinkStore store;
  final DateTimeRange? initialDates;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final bookable =
            property.businessModel == PropertyBusinessModel.bookable;
        final unlocked = store.isUnlocked(property.id);
        final wide = MediaQuery.sizeOf(context).width >= 1024;

        return Scaffold(
          appBar: AppBar(
            title: Text(context.tr('Property details')),
            actions: [
              IconButton(
                tooltip: store.savedPropertyIds.contains(property.id)
                    ? context.tr('Remove saved property')
                    : context.tr('Save property'),
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
                      ? HavenIcons.favorite
                      : HavenIcons.favoriteBorder,
                ),
              ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1216),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PropertyGallery(
                              photos: property.allPhotos,
                              mosaic: !bookable,
                              height: wide ? (bookable ? 390 : 420) : 300,
                              labels:
                                  property.stayRules?.photoLabels ?? const {},
                              badge: _BusinessBadge(
                                bookable: bookable,
                                label: bookable
                                    ? context.tr('BOOKABLE')
                                    : context.tr('CONTACT UNLOCK'),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        style: const TextStyle(
                                          color: HavenTheme.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (bookable) ...[
                                  const Icon(
                                    HavenIcons.starRounded,
                                    color: HavenTheme.teal,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    property.reviewCount > 0
                                        ? '${property.rating.toStringAsFixed(1)} (${property.reviewCount})'
                                        : context.tr('No reviews yet'),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _VerificationChip(
                                  label: context.tr('Property'),
                                  status: property.propertyVerification,
                                ),
                                _VerificationChip(
                                  label: context.tr('Owner / agent'),
                                  status: property.ownerVerification,
                                ),
                                Chip(
                                  avatar: Icon(
                                    property.available
                                        ? HavenIcons.checkCircleOutline
                                        : HavenIcons.eventBusy,
                                    size: 17,
                                    color: property.available
                                        ? HavenTheme.forest
                                        : Colors.red,
                                  ),
                                  label: Text(
                                    context.tr(
                                      property.available
                                          ? 'Available'
                                          : 'Unavailable',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _DetailSection(
                              title: context.tr(
                                bookable
                                    ? 'About this stay'
                                    : 'About this rental',
                              ),
                              child: Text(
                                property.description,
                                style: const TextStyle(height: 1.55),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _DetailSection(
                              title: context.tr('Property details'),
                              child: Wrap(
                                spacing: 20,
                                runSpacing: 14,
                                children: [
                                  _Fact(
                                    icon: HavenIcons.bedOutlined,
                                    label:
                                        '${property.bedrooms} ${context.tr('bedrooms')}',
                                  ),
                                  _Fact(
                                    icon: HavenIcons.bathtubOutlined,
                                    label:
                                        '${property.bathrooms} ${context.tr('bathrooms')}',
                                  ),
                                  _Fact(
                                    icon: HavenIcons.chairOutlined,
                                    label: property.furnished
                                        ? context.tr('Furnished')
                                        : context.tr('Unfurnished'),
                                  ),
                                  if (property.parking)
                                    _Fact(
                                      icon: HavenIcons.localParking,
                                      label: context.tr('Parking'),
                                    ),
                                  if (property.water)
                                    _Fact(
                                      icon: HavenIcons.waterDropOutlined,
                                      label: context.tr('Water'),
                                    ),
                                  if (property.electricity)
                                    _Fact(
                                      icon: HavenIcons.boltOutlined,
                                      label: context.tr('Electricity'),
                                    ),
                                  if (property.security)
                                    _Fact(
                                      icon: HavenIcons.shieldOutlined,
                                      label: context.tr('Security'),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            _DetailSection(
                              title: context.tr('Amenities'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children:
                                        {
                                              ...property.amenities,
                                              ...property.amenityDetails.map(
                                                (amenity) => amenity.name,
                                              ),
                                            }
                                            .map(
                                              (item) => Chip(label: Text(item)),
                                            )
                                            .toList(),
                                  ),
                                  for (final amenity
                                      in property.amenityDetails.where(
                                        (item) =>
                                            item.description.trim().isNotEmpty,
                                      ))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        '${amenity.name}: ${amenity.description}',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (property.category.isApartmentStay &&
                                (property.maxGuests != null ||
                                    !(property.stayRules?.isEmpty ??
                                        true))) ...[
                              _DetailSection(
                                title: context.tr('Guests and house rules'),
                                child: _ApartmentRules(property: property),
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (bookable) ...[
                              _DetailSection(
                                title: context.tr('Stay information'),
                                child: StayInfoSection(propertyId: property.id),
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (bookable)
                              _DetailSection(
                                title:
                                    '${context.tr('Hosted by')} ${property.managerName}',
                                child: Text(
                                  context.tr(
                                    'Your property manager can help with your stay. Contact details are shared after a confirmed booking.',
                                  ),
                                ),
                              )
                            else ...[
                              if (property.managerName.isNotEmpty) ...[
                                _DetailSection(
                                  title:
                                      '${context.tr('Listed by')} ${property.managerName}',
                                  child: Text(
                                    context.tr(
                                      'Check the verification badges above before you pay to unlock contact details.',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                              ],
                              _RentalContactPanel(
                                property: property,
                                store: store,
                                unlocked: unlocked,
                              ),
                            ],
                            const SizedBox(height: 22),
                            if (bookable) ...[
                              _DetailSection(
                                title: context.tr('Guest reviews'),
                                child: PropertyReviewsSection(
                                  propertyId: property.id,
                                  tokenProvider: () => store
                                      .authenticationRepository
                                      .accessToken,
                                  canReport: store.isSignedIn,
                                ),
                              ),
                              const SizedBox(height: 22),
                            ],
                            _DetailSection(
                              title: context.tr('Location'),
                              child: _locationMap(bookable, unlocked),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (wide) ...[
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 380,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(top: 4, bottom: 28),
                          child: _PropertyActionCard(
                            property: property,
                            unlockFeeTzs: store.feeSettings.unlockFeeTzs,
                            bookable: bookable,
                            unlocked: unlocked,
                            action: _actionButton(context, bookable, unlocked),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                  child: Align(
                    alignment: Alignment.center,
                    heightFactor: 1,
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
                          const SizedBox(width: 12),
                          Flexible(
                            child: _actionButton(context, bookable, unlocked),
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

  Widget _actionButton(BuildContext context, bool bookable, bool unlocked) {
    return FilledButton.icon(
      onPressed: property.available
          ? () => _continue(context, bookable, unlocked)
          : null,
      icon: Icon(
        bookable
            ? HavenIcons.calendarMonthOutlined
            : HavenIcons.lockOpenOutlined,
      ),
      label: Text(
        bookable
            ? context.tr('Book now')
            : unlocked
            ? context.tr('View Unlocked Contact')
            : context.tr('Unlock Contact & Messaging'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _locationMap(bool bookable, bool unlocked) {
    if (bookable) {
      final exactLocation =
          property.locationVisibility == LocationVisibility.exact &&
          property.latitude != null &&
          property.longitude != null;
      final query = exactLocation
          ? '${property.latitude},${property.longitude}'
          : property.locationVisibility == LocationVisibility.hidden
          ? property.city
          : property.generalLocation;
      return NearbyMap(
        locationQuery: query,
        zoom: exactLocation ? 16 : 13,
        areaLabel: property.generalLocation,
      );
    }

    if (!unlocked) {
      return NearbyMap(
        locationQuery: property.generalLocation,
        zoom: 13,
        areaLabel: property.generalLocation,
      );
    }

    return FutureBuilder<OwnerContact?>(
      future: store.contactFor(property.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final contact = snapshot.data;
        if (contact == null) {
          return const SizedBox(
            height: 120,
            child: Center(child: Text('Exact location is unavailable.')),
          );
        }
        return NearbyMap(
          locationQuery: '${contact.latitude},${contact.longitude}',
          zoom: 16,
          areaLabel: property.generalLocation,
        );
      },
    );
  }

  Future<void> _continue(
    BuildContext context,
    bool bookable,
    bool unlocked,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (bookable) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => CheckoutScreen(
            property: property,
            store: store,
            initialDates: bookable ? initialDates : null,
          ),
        ),
      );
      return;
    }

    if (!unlocked) {
      if (!store.isSignedIn) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Sign in to unlock this rental property.'),
            ),
          ),
        );
        return;
      }
      try {
        await store.openRentalDetails(property);
      } catch (error) {
        if (error.toString().contains('Payment is required')) {
          navigator.push(
            MaterialPageRoute<void>(
              builder: (context) =>
                  CheckoutScreen(property: property, store: store),
            ),
          );
        } else {
          messenger.showSnackBar(SnackBar(content: Text(error.toString())));
        }
        return;
      }
      if (!context.mounted) return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        child: FutureBuilder<OwnerContact?>(
          future: store.contactFor(property.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final contact = snapshot.data;
            if (contact == null) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.tr('The property details are unavailable right now.'),
                ),
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.name,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 14),
                  _ContactRow(
                    icon: HavenIcons.placeOutlined,
                    text: contact.exactAddress,
                  ),
                  _ContactRow(
                    icon: HavenIcons.personOutline,
                    text: '${contact.contactName} · ${contact.role}',
                  ),
                  _ContactRow(
                    icon: HavenIcons.phoneOutlined,
                    text: contact.phone,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PropertyActionCard extends StatelessWidget {
  const _PropertyActionCard({
    required this.unlockFeeTzs,
    required this.property,
    required this.bookable,
    required this.unlocked,
    required this.action,
  });

  final Property property;
  final bool bookable;
  final bool unlocked;
  final Widget action;
  final int unlockFeeTzs;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(bookable ? 'Price' : 'Monthly rent'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${formatTzs(property.priceTzs)} ${property.pricePeriod}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(height: 36),
            if (!bookable) ...[
              Icon(
                unlocked
                    ? HavenIcons.checkCircleOutline
                    : HavenIcons.lockOutline,
                color: HavenTheme.forest,
                size: 28,
              ),
              const SizedBox(height: 12),
              Text(
                context.tr(
                  unlocked ? 'Access verified' : 'Unlock contact & location',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  unlocked
                      ? 'Your authorized contact and exact location are available below.'
                      : 'Contact details and the exact location remain private until access is verified.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
            ],
            if (!bookable && !unlocked) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: HavenTheme.veryLightMint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(context.tr('Unlock fee'))),
                    Text(
                      formatTzs(unlockFeeTzs),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            action,
            if (!bookable && !unlocked) ...[
              const SizedBox(height: 12),
              Text(
                context.tr(
                  'Information appears only after payment verification.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: HavenTheme.forest),
        const SizedBox(width: 10),
        Expanded(child: SelectableText(text)),
      ],
    ),
  );
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
              const Icon(HavenIcons.lockOutline, color: HavenTheme.forest),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exact location & contact',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                        'Pay the contact-unlock fee to access the exact location, authorized contact details, and a secure message channel with the Rental Agent.',
                      ),
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
                Text(
                  context.tr('Exact location and authorized contact unlocked'),
                ),
                const SizedBox(height: 10),
                Text(contact.exactAddress),
                Text('${contact.contactName} · ${contact.role}'),
                Text(contact.phone),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    final userId = store.currentUser?.id;
                    if (userId == null) return;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) => RentalMessagesScreen(
                          repository: CustomerDataRepository(
                            tokenProvider: () =>
                                store.authenticationRepository.accessToken,
                          ),
                          currentUserId: userId,
                          isAgent: false,
                          listingId: property.id,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(HavenIcons.chatBubbleOutline),
                  label: const Text('Message Rental Agent'),
                ),
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
            bookable ? HavenIcons.eventAvailable : HavenIcons.key,
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
            ? HavenIcons.verified
            : pending
            ? HavenIcons.pendingOutlined
            : HavenIcons.infoOutline,
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

class _ApartmentRules extends StatelessWidget {
  const _ApartmentRules({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final rules = property.stayRules;
    final lines = <(IconData, String)>[
      if (rules != null && rules.region.isNotEmpty)
        (
          HavenIcons.placeOutlined,
          [
            property.city,
            rules.region,
            if (rules.country.isNotEmpty) rules.country,
          ].join(', '),
        ),
      if (property.maxGuests != null)
        (
          HavenIcons.peopleOutline,
          '${context.tr('Sleeps up to')} ${property.maxGuests}',
        ),
      if (rules?.beds != null)
        (HavenIcons.bedOutlined, '${context.tr('Beds')}: ${rules!.beds}'),
      if (rules?.weekendPriceTzs != null)
        (
          HavenIcons.weekendOutlined,
          '${context.tr('Weekend rate (Fri & Sat nights)')}: ${formatTzs(rules!.weekendPriceTzs!)}',
        ),
      if (rules?.cleaningFeeTzs != null)
        (
          HavenIcons.cleaningServicesOutlined,
          '${context.tr('Cleaning fee per stay')}: ${formatTzs(rules!.cleaningFeeTzs!)}',
        ),
      if (rules?.minNights != null)
        (
          HavenIcons.nightsStayOutlined,
          '${context.tr('Minimum stay')}: ${rules!.minNights} ${context.tr('nights')}',
        ),
      if (rules?.maxNights != null)
        (
          HavenIcons.eventBusyOutlined,
          '${context.tr('Maximum stay')}: ${rules!.maxNights} ${context.tr('nights')}',
        ),
      if (rules != null && rules.checkInTime.isNotEmpty)
        (
          HavenIcons.login,
          '${context.tr('Check-in from')} ${rules.checkInTime}',
        ),
      if (rules != null && rules.checkOutTime.isNotEmpty)
        (
          HavenIcons.logout,
          '${context.tr('Check-out by')} ${rules.checkOutTime}',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(line.$1, size: 18, color: HavenTheme.forest),
                const SizedBox(width: 8),
                Expanded(child: Text(line.$2)),
              ],
            ),
          ),
        if (rules != null && rules.cancellationPolicy.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            context.tr('Cancellation policy'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(rules.cancellationPolicy),
        ],
        if (rules != null && rules.houseRules.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            context.tr('House rules'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(rules.houseRules),
        ],
      ],
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
