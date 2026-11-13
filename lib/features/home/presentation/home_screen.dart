import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/properties/domain/property.dart';
import 'home_sections.dart';
import '../../../features/properties/presentation/widgets/property_photo.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.store,
    required this.onBrowse,
    required this.onOpenProperty,
    this.onSearch,
    this.onAccount,
    this.onSearchWithDates,
    this.scrollController,
    this.sectionKeys = const {},
    super.key,
  });

  final HavenLinkStore store;
  final ValueChanged<PropertyBusinessModel> onBrowse;
  final ValueChanged<Property> onOpenProperty;
  final HomeSearchCallback? onSearch;
  final VoidCallback? onAccount;
  final HomeDateSearchCallback? onSearchWithDates;
  final ScrollController? scrollController;
  final Map<String, GlobalKey> sectionKeys;

  @override
  Widget build(BuildContext context) {
    if (store.isLoadingProperties) {
      return const Center(child: CircularProgressIndicator());
    }
    if (store.loadError case final error?) {
      return _LoadingError(message: error, onRetry: store.loadProperties);
    }

    final properties = store.properties;
    final featured =
        properties.where((p) => p.isVerified).firstOrNull ??
        properties.firstOrNull;
    return SingleChildScrollView(
      key: const Key('home-scroll'),
      controller: scrollController,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HomeBand(
            color: const Color(0xFFE8F6F0),
            child: _HeroPanel(
              featured: featured,
              onSearch: () => onBrowse(PropertyBusinessModel.bookable),
              onExploreRentals: () =>
                  onBrowse(PropertyBusinessModel.contactUnlock),
              onOpenFeatured: featured == null
                  ? null
                  : () => onOpenProperty(featured),
              search: HomeSearchPanel(
                onSearchWithDates: onSearchWithDates,
                onSearch:
                    onSearch ?? (model, query, category) => onBrowse(model),
              ),
            ),
          ),
          _HomeBand(
            key: sectionKeys['discover'],
            child: HomeDiscoverySection(
              store: store,
              onOpenProperty: onOpenProperty,
              onSearch: onSearch ?? (model, query, category) => onBrowse(model),
            ),
          ),
          _HomeBand(
            key: sectionKeys['how'],
            color: HavenTheme.darkTeal,
            child: HomeTrustSection(onBrowse: onBrowse),
          ),
          _HomeBand(
            key: sectionKeys['portals'],
            child: HomeWorkspaceSection(onAccount: onAccount),
          ),
          const _HomeBand(color: HavenTheme.white, child: HomeFooter()),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.featured,
    required this.onSearch,
    required this.onExploreRentals,
    required this.onOpenFeatured,
    required this.search,
  });

  final Property? featured;
  final VoidCallback onSearch;
  final VoidCallback onExploreRentals;
  final VoidCallback? onOpenFeatured;
  final Widget search;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1024;
        final copy = _HeroCopy(
          compact: compact,
          headingSize: constraints.maxWidth < 640
              ? 42
              : compact
              ? 58
              : 68,
          onSearch: onSearch,
          onExploreRentals: onExploreRentals,
          search: search,
        );
        final propertyCard = _FeaturedPropertyCard(
          property: featured,
          onTap: onOpenFeatured,
          compact: compact,
        );
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 20 : 32,
            vertical: compact ? 56 : 80,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F6F0),
            gradient: RadialGradient(
              center: const Alignment(1.1, -1.2),
              radius: 1.3,
              colors: [
                HavenTheme.mintAccent.withValues(alpha: .2),
                const Color(0xFFE8F6F0),
              ],
            ),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [copy, const SizedBox(height: 18), propertyCard],
                )
              : Row(
                  children: [
                    Expanded(flex: 21, child: copy),
                    const SizedBox(width: 40),
                    Expanded(flex: 19, child: propertyCard),
                  ],
                ),
        );
      },
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.headingSize,
    required this.compact,
    required this.onSearch,
    required this.onExploreRentals,
    required this.search,
  });

  final Widget search;
  final double headingSize;
  final bool compact;
  final VoidCallback onSearch;
  final VoidCallback onExploreRentals;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: HavenTheme.white,
            border: Border.all(
              color: HavenTheme.forest.withValues(alpha: 0.18),
            ),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                HavenIcons.verifiedUserOutlined,
                color: HavenTheme.forest,
                size: 16,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  context.tr('Tanzania property network'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: HavenTheme.forest,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text.rich(
          TextSpan(
            children: context.languageCode == 'en'
                ? [
                    const TextSpan(text: 'Find Your Perfect Space '),
                    const TextSpan(
                      text: 'with Confidence.',
                      style: TextStyle(
                        fontFamily: 'HavenSerif',
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        color: HavenTheme.forest,
                      ),
                    ),
                  ]
                : [
                    TextSpan(
                      text: context.tr(
                        'Find Your Perfect Space with Confidence.',
                      ),
                    ),
                  ],
          ),
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            color: HavenTheme.ink,
            fontSize: headingSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -2.6,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.tr(
            'Discover verified places to stay and homes to rent across Tanzania.',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: HavenTheme.muted),
        ),
        const SizedBox(height: 32),
        search,
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _TrustLabel(
              icon: HavenIcons.verifiedOutlined,
              label: context.tr('Verification status shown'),
            ),
            _TrustLabel(
              icon: HavenIcons.lockOutline,
              label: context.tr('Rental contacts kept private'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrustLabel extends StatelessWidget {
  const _TrustLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: HavenTheme.forest),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: HavenTheme.ink),
        ),
      ),
    ],
  );
}

class _FeaturedPropertyCard extends StatelessWidget {
  const _FeaturedPropertyCard({
    required this.property,
    required this.onTap,
    required this.compact,
  });

  final Property? property;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 260.0 : 440.0;
    return Material(
      color: HavenTheme.white,
      borderRadius: BorderRadius.circular(32),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('featured-property-card'),
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (property != null && property!.imageUrl.isNotEmpty)
                PropertyPhoto(imageUrl: property!.imageUrl, height: height)
              else
                property != null
                    ? const ColoredBox(
                        color: HavenTheme.lightMint,
                        child: Icon(
                          HavenIcons.homeWorkOutlined,
                          size: 56,
                          color: HavenTheme.forest,
                        ),
                      )
                    : Image.asset(
                        'assets/images/stay-hero.jpg',
                        fit: BoxFit.cover,
                        semanticLabel:
                            'Accommodation inspiration from the Haven Link design',
                      ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: HavenTheme.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr(
                                property?.isVerified == true
                                    ? 'Verified property'
                                    : 'Featured property',
                              ),
                              style: const TextStyle(
                                color: HavenTheme.forest,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              property?.name ??
                                  context.tr('New places are coming'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: HavenTheme.ink),
                            ),
                            if (property != null)
                              Text(
                                '${property!.neighborhood}, ${property!.city}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: HavenTheme.muted,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if ((property?.rating ?? 0) > 0) ...[
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            const Icon(
                              HavenIcons.starRounded,
                              size: 17,
                              color: HavenTheme.gold,
                            ),
                            Text(
                              property!.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: HavenTheme.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
          const Icon(HavenIcons.wifiOffOutlined, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(HavenIcons.refresh),
            label: Text(context.tr('Try again')),
          ),
        ],
      ),
    );
  }
}

class _HomeBand extends StatelessWidget {
  const _HomeBand({required this.child, this.color, super.key});
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color ?? HavenTheme.veryLightMint,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: child,
      ),
    ),
  );
}
