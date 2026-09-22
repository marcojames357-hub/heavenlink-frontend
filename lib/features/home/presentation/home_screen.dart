import 'package:flutter/material.dart';

import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/properties/domain/property.dart';
import '../../../features/properties/presentation/widgets/property_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.store,
    required this.onBrowse,
    required this.onOpenProperty,
    super.key,
  });

  final HavenLinkStore store;
  final ValueChanged<PropertyBusinessModel> onBrowse;
  final ValueChanged<Property> onOpenProperty;

  @override
  Widget build(BuildContext context) {
    if (store.isLoadingProperties) {
      return const Center(child: CircularProgressIndicator());
    }
    if (store.loadError case final error?) {
      return _LoadingError(message: error, onRetry: store.loadProperties);
    }

    final properties = store.properties;
    final stays = properties
        .where(
          (property) =>
              property.businessModel == PropertyBusinessModel.bookable,
        )
        .toList();
    final rentals = properties
        .where(
          (property) =>
              property.businessModel == PropertyBusinessModel.contactUnlock,
        )
        .toList();
    final verified = properties
        .where((property) => property.isVerified)
        .take(3)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
      children: [
        _HeroPanel(onSearch: () => onBrowse(PropertyBusinessModel.bookable)),
        const SizedBox(height: 30),
        Text(
          'Find your kind of stay',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Two clear ways to find your next place in Tanzania.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: HavenTheme.muted),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 700;
            final tiles = [
              _SectionTile(
                imageUrl: stays.first.imageUrl,
                icon: Icons.hotel_outlined,
                title: 'Hotels, lodges & apartments',
                subtitle: 'Book directly with Haven Link',
                actionLabel: 'Explore stays',
                onTap: () => onBrowse(PropertyBusinessModel.bookable),
              ),
              _SectionTile(
                imageUrl: rentals.first.imageUrl,
                icon: Icons.key_outlined,
                title: 'Houses & rooms for rent',
                subtitle: 'Find your space and connect with the property owner',
                actionLabel: 'Explore rentals',
                onTap: () => onBrowse(PropertyBusinessModel.contactUnlock),
              ),
            ];
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: 16),
                  Expanded(child: tiles[1]),
                ],
              );
            }
            return Column(
              children: [
                _CompactSectionTile(
                  imageUrl: stays.first.imageUrl,
                  icon: Icons.hotel_outlined,
                  title: 'Hotels, lodges & apartments',
                  subtitle: 'Book directly with Haven Link',
                  actionLabel: 'Explore stays',
                  onTap: () => onBrowse(PropertyBusinessModel.bookable),
                ),
                const SizedBox(height: 10),
                _CompactSectionTile(
                  imageUrl: rentals.first.imageUrl,
                  icon: Icons.key_outlined,
                  title: 'Houses & rooms for rent',
                  subtitle:
                      'Find your space and connect with the property owner',
                  actionLabel: 'Explore rentals',
                  onTap: () => onBrowse(PropertyBusinessModel.contactUnlock),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 34),
        _SectionHeading(
          title: 'Popular locations',
          subtitle: 'Start with a place you know',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children:
              [
                    'Mikocheni',
                    'Masaki',
                    'Mbezi Beach',
                    'Kinondoni',
                    'Sinza',
                    'Arusha',
                    'Zanzibar',
                  ]
                  .map(
                    (place) => ActionChip(
                      avatar: const Icon(Icons.location_on_outlined, size: 16),
                      label: Text(place),
                      onPressed: () =>
                          onBrowse(PropertyBusinessModel.contactUnlock),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 36),
        _SectionHeading(
          title: 'Stays people love',
          subtitle: 'Bookable properties with verified details',
          action: TextButton.icon(
            onPressed: () => onBrowse(PropertyBusinessModel.bookable),
            icon: const Icon(Icons.arrow_forward, size: 17),
            label: const Text('See stays'),
          ),
        ),
        const SizedBox(height: 14),
        _PropertyGrid(
          properties: stays.take(2).toList(),
          store: store,
          onOpenProperty: onOpenProperty,
        ),
        const SizedBox(height: 34),
        _SectionHeading(
          title: 'Verified properties',
          subtitle: 'Listings with current verification status',
        ),
        const SizedBox(height: 14),
        _PropertyGrid(
          properties: verified,
          store: store,
          onOpenProperty: onOpenProperty,
        ),
        const SizedBox(height: 34),
        _SectionHeading(
          title: 'Recently added rentals',
          subtitle: 'Your next home could be closer than you think',
          action: TextButton.icon(
            onPressed: () => onBrowse(PropertyBusinessModel.contactUnlock),
            icon: const Icon(Icons.arrow_forward, size: 17),
            label: const Text('See rentals'),
          ),
        ),
        const SizedBox(height: 14),
        _PropertyGrid(
          properties: rentals.take(2).toList(),
          store: store,
          onOpenProperty: onOpenProperty,
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFE9E4D8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, color: HavenTheme.forest),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your next move, with more confidence',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Verification labels reflect the status supplied by Haven Link. Rental contacts stay private until an authorized unlock is recorded.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return Container(
          height: compact ? 250 : 320,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: HavenTheme.ink,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                'https://images.unsplash.com/photo-1600210492486-724fe5c67fb0?w=1600&auto=format&fit=crop',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      HavenTheme.ink.withValues(alpha: 0.92),
                      Colors.transparent,
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(compact ? 16 : 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'HAVEN LINK  /  TANZANIA',
                        style: TextStyle(
                          color: HavenTheme.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      SizedBox(height: compact ? 7 : 12),
                      Text(
                        'Find Your Perfect Space with Confidence.',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: Colors.white,
                              fontSize: compact ? 25 : 32,
                            ),
                      ),
                      SizedBox(height: compact ? 6 : 10),
                      const Text(
                        'Discover verified places to stay and homes to rent across Tanzania.',
                        style: TextStyle(color: Colors.white70, height: 1.5),
                      ),
                      SizedBox(height: compact ? 10 : 19),
                      FilledButton.icon(
                        onPressed: onSearch,
                        icon: const Icon(Icons.search),
                        label: const Text('Search properties'),
                        style: FilledButton.styleFrom(
                          backgroundColor: HavenTheme.gold,
                          foregroundColor: HavenTheme.ink,
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 14 : 20,
                            vertical: compact ? 10 : 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CompactSectionTile extends StatelessWidget {
  const _CompactSectionTile({
    required this.imageUrl,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final String imageUrl;
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox.square(
                  dimension: 66,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(color: Color(0xFFE5E9DE)),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: HavenTheme.forest),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: HavenTheme.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: actionLabel,
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward, color: HavenTheme.forest),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.imageUrl,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final String imageUrl;
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 134,
              width: double.infinity,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const ColoredBox(color: Color(0xFFE5E9DE)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: HavenTheme.forest),
                  const SizedBox(height: 9),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(color: HavenTheme.muted),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: onTap,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward, size: 17),
                    label: Text(actionLabel),
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: HavenTheme.muted)),
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class _PropertyGrid extends StatelessWidget {
  const _PropertyGrid({
    required this.properties,
    required this.store,
    required this.onOpenProperty,
  });

  final List<Property> properties;
  final HavenLinkStore store;
  final ValueChanged<Property> onOpenProperty;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 740 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: properties.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 390,
          ),
          itemBuilder: (context, index) => PropertyCard(
            property: properties[index],
            store: store,
            onTap: () => onOpenProperty(properties[index]),
          ),
        );
      },
    );
  }
}

class _LoadingError extends StatelessWidget {
  const _LoadingError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_outlined, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
