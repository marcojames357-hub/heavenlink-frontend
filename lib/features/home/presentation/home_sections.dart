import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/haven_icons.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/widgets/property_card.dart';
import '../../properties/presentation/widgets/property_map.dart';

typedef HomeSearchCallback =
    void Function(PropertyBusinessModel model, String query, String? category);

typedef HomeDateSearchCallback =
    void Function(
      PropertyBusinessModel model,
      String query,
      String? category,
      DateTimeRange? dates,
    );

const _categories =
    <(String, String, IconData, String?, PropertyBusinessModel)>[
      (
        'Rental homes',
        'Long-term spaces',
        HavenIcons.homeOutlined,
        null,
        PropertyBusinessModel.contactUnlock,
      ),
      (
        'Apartments',
        'Flexible stays',
        HavenIcons.apartmentOutlined,
        'apartment',
        PropertyBusinessModel.bookable,
      ),
      (
        'Hotels',
        'Full-service comfort',
        HavenIcons.hotelOutlined,
        'hotel',
        PropertyBusinessModel.bookable,
      ),
      (
        'Lodges',
        'Nature & retreats',
        HavenIcons.homeWorkOutlined,
        'lodge',
        PropertyBusinessModel.bookable,
      ),
      (
        'Motels',
        'Easy road stays',
        HavenIcons.bedOutlined,
        'motel',
        PropertyBusinessModel.bookable,
      ),
    ];

class HomeSearchPanel extends StatefulWidget {
  const HomeSearchPanel({
    required this.onSearch,
    this.onSearchWithDates,
    super.key,
  });
  final HomeSearchCallback onSearch;
  final HomeDateSearchCallback? onSearchWithDates;
  @override
  State<HomeSearchPanel> createState() => _HomeSearchPanelState();
}

class _HomeSearchPanelState extends State<HomeSearchPanel> {
  final _query = TextEditingController();
  DateTimeRange? _dates;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    if (widget.onSearchWithDates case final search?) {
      search(PropertyBusinessModel.bookable, _query.text.trim(), null, _dates);
    } else {
      widget.onSearch(PropertyBusinessModel.bookable, _query.text.trim(), null);
    }
  }

  Future<void> _chooseDates() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final dates = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _dates,
    );
    if (dates != null && mounted) setState(() => _dates = dates);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: HavenTheme.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: HavenTheme.darkTeal.withValues(alpha: .14),
          blurRadius: 40,
          offset: const Offset(0, 16),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final location = TextField(
          key: const Key('home-search-location'),
          controller: _query,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: context.tr('Where'),
            hintText: context.tr('City, area or property'),
            prefixIcon: const Icon(HavenIcons.locationOnOutlined, size: 19),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        );
        final localizations = MaterialLocalizations.of(context);
        final datesLabel = _dates == null
            ? context.tr('Add dates')
            : '${localizations.formatShortDate(_dates!.start)} \u2013 ${localizations.formatShortDate(_dates!.end)}';
        final dates = Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: const Key('home-search-dates'),
            borderRadius: BorderRadius.circular(12),
            onTap: _chooseDates,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  const Icon(
                    HavenIcons.calendarMonthOutlined,
                    color: HavenTheme.forest,
                    size: 19,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('Dates'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: HavenTheme.muted),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          datesLabel,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final button = FilledButton.icon(
          key: const Key('home-search-submit'),
          onPressed: _search,
          icon: const Icon(HavenIcons.search, size: 18),
          label: Text(context.tr('Search properties')),
        );
        if (constraints.maxWidth < 540) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [location, dates, const SizedBox(height: 8), button],
          );
        }
        return Row(
          children: [
            Expanded(flex: 6, child: location),
            Expanded(flex: 4, child: dates),
            const SizedBox(width: 8),
            button,
          ],
        );
      },
    ),
  );
}

class HomeSectionHeading extends StatelessWidget {
  const HomeSectionHeading({
    required this.kicker,
    required this.title,
    this.action,
    super.key,
  });
  final String kicker, title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(kicker).toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: HavenTheme.forest,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(title),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: constraints.maxWidth >= 640 ? 34 : 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
            ),
          ),
        ],
      );
      if (constraints.maxWidth < 640 || action == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: heading),
          const SizedBox(width: 24),
          action!,
        ],
      );
    },
  );
}

class HomeDiscoverySection extends StatefulWidget {
  const HomeDiscoverySection({
    required this.store,
    required this.onOpenProperty,
    required this.onSearch,
    super.key,
  });
  final HavenLinkStore store;
  final ValueChanged<Property> onOpenProperty;
  final HomeSearchCallback onSearch;
  @override
  State<HomeDiscoverySection> createState() => _HomeDiscoverySectionState();
}

class _HomeDiscoverySectionState extends State<HomeDiscoverySection> {
  int? _selected;
  bool _matches(Property p) {
    if (_selected == null) return true;
    final c = _categories[_selected!];
    return p.businessModel == c.$5 &&
        (c.$4 == null ||
            (c.$4 == 'apartment'
                ? p.category.isApartmentStay
                : p.category.name == c.$4));
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.store.properties.where(_matches).take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeSectionHeading(
            kicker: 'Explore your way',
            title: 'Every kind of space, one trusted platform',
            action: TextButton.icon(
              onPressed: () =>
                  widget.onSearch(PropertyBusinessModel.bookable, '', null),
              iconAlignment: IconAlignment.end,
              icon: const Icon(HavenIcons.arrowForward, size: 16),
              label: Text(context.tr('View all properties')),
            ),
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 5
                  : constraints.maxWidth >= 600
                  ? 3
                  : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (i, c) in _categories.indexed)
                    SizedBox(
                      width: width,
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: Key('home-category-$i'),
                          onTap: () {
                            setState(() => _selected = i);
                            widget.onSearch(c.$5, '', c.$4);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: HavenTheme.lightMint,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    c.$3,
                                    color: HavenTheme.forest,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  context.tr(c.$1),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.tr(c.$2),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(context.tr('All properties')),
                selected: _selected == null,
                onSelected: (_) => setState(() => _selected = null),
              ),
              for (final (i, c) in _categories.indexed)
                ChoiceChip(
                  label: Text(context.tr(c.$1)),
                  selected: _selected == i,
                  onSelected: (_) => setState(() => _selected = i),
                ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = results.isEmpty
                  ? Container(
                      constraints: const BoxConstraints(minHeight: 320),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: HavenTheme.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: HavenTheme.border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            HavenIcons.homeWorkOutlined,
                            size: 36,
                            color: HavenTheme.forest,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.tr('New places are coming'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr(
                              'Published properties will appear here.',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, inner) {
                        final columns = inner.maxWidth >= 540 ? 2 : 1;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final p in results)
                              SizedBox(
                                width:
                                    (inner.maxWidth - (columns - 1) * 16) /
                                    columns,
                                child: PropertyCard(
                                  property: p,
                                  store: widget.store,
                                  onTap: () => widget.onOpenProperty(p),
                                ),
                              ),
                          ],
                        );
                      },
                    );
              final map = ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (constraints.maxWidth >= 1024)
                      Expanded(
                        child: PropertyMapFrame(
                          locationQuery: results.isEmpty
                              ? 'Tanzania'
                              : results.first.city,
                          zoom: results.isEmpty ? 6 : 12,
                        ),
                      )
                    else
                      SizedBox(
                        height: 420,
                        child: PropertyMapFrame(
                          locationQuery: results.isEmpty
                              ? 'Tanzania'
                              : results.first.city,
                          zoom: results.isEmpty ? 6 : 12,
                        ),
                      ),
                    Container(
                      color: HavenTheme.lightMint,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            HavenIcons.lockOutline,
                            size: 16,
                            color: HavenTheme.forest,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr(
                                'Explore the area. Rental locations stay private until unlock.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              if (constraints.maxWidth < 1024) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [cards, const SizedBox(height: 20), map],
                );
              }
              final rows = (results.length / 2).ceil();
              final mapHeight = results.isEmpty
                  ? 420.0
                  : rows * 390.0 + (rows - 1) * 16;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 11, child: cards),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 9,
                    child: SizedBox(height: mapHeight, child: map),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class HomeTrustSection extends StatelessWidget {
  const HomeTrustSection({required this.onBrowse, super.key});
  final ValueChanged<PropertyBusinessModel> onBrowse;
  @override
  Widget build(BuildContext context) => Container(
    color: HavenTheme.darkTeal,
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 56),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final intro = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Built for trust').toUpperCase(),
              style: const TextStyle(
                color: HavenTheme.mintAccent,
                fontSize: 11,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('Different properties.\nClear journeys.'),
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(color: HavenTheme.white),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr(
                'Stay details remain transparent while rental privacy is protected until a verified unlock.',
              ),
              style: const TextStyle(color: HavenTheme.white, height: 1.7),
            ),
          ],
        );
        final tiles = [
          for (final (title, body, icon, model) in [
            (
              'Hotels, lodges & motels',
              'Choose a stay, check availability and follow the existing booking and payment process.',
              HavenIcons.hotelOutlined,
              PropertyBusinessModel.bookable,
            ),
            (
              'Rental properties',
              'See photos, approximate area and highlights. Exact location and contact require an authorized unlock.',
              HavenIcons.keyOutlined,
              PropertyBusinessModel.contactUnlock,
            ),
          ])
            Material(
              color: HavenTheme.white.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onBrowse(model),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: HavenTheme.mintAccent),
                      const SizedBox(height: 24),
                      Text(
                        context.tr(title),
                        style: const TextStyle(
                          color: HavenTheme.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr(body),
                        style: const TextStyle(
                          color: HavenTheme.white,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Text(
                            context.tr('Explore'),
                            style: const TextStyle(
                              color: HavenTheme.mintAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            HavenIcons.arrowForward,
                            color: HavenTheme.mintAccent,
                            size: 16,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ];
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              intro,
              const SizedBox(height: 24),
              ...tiles.expand((t) => [t, const SizedBox(height: 16)]),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: intro),
            const SizedBox(width: 32),
            for (final tile in tiles) ...[
              Expanded(child: tile),
              const SizedBox(width: 16),
            ],
          ],
        );
      },
    ),
  );
}

class HomeWorkspaceSection extends StatelessWidget {
  const HomeWorkspaceSection({this.onAccount, super.key});
  final VoidCallback? onAccount;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeSectionHeading(
          kicker: 'One connected platform',
          title: 'A dedicated workspace for every user',
        ),
        const SizedBox(height: 16),
        Text(
          context.tr(
            'Sign in once and open the workspace approved for your account.',
          ),
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 5
                : constraints.maxWidth >= 600
                ? 3
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final (title, body, icon) in [
                  (
                    'Customer portal',
                    'Search, book, unlock, save and manage your stays.',
                    HavenIcons.personOutline,
                  ),
                  (
                    'Rental Agent',
                    'Properties, tenancies, rent, utilities and maintenance.',
                    HavenIcons.homeOutlined,
                  ),
                  (
                    'Apartment Stays Agent',
                    'Apartment availability, reservations and finances.',
                    HavenIcons.apartmentOutlined,
                  ),
                  (
                    'Hotel, Lodge & Motel Agent',
                    'Rooms, calendar, reservations and front desk.',
                    HavenIcons.hotelOutlined,
                  ),
                  (
                    'System Admin',
                    'Approvals, users, reports and audit history.',
                    HavenIcons.adminPanelSettingsOutlined,
                  ),
                ])
                  SizedBox(
                    width: width,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icon, color: HavenTheme.forest, size: 28),
                            const SizedBox(height: 22),
                            Text(
                              context.tr(title),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              context.tr(body),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 18),
                            TextButton.icon(
                              onPressed: onAccount,
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(
                                HavenIcons.arrowForward,
                                size: 16,
                              ),
                              label: Text(context.tr('Open workspace')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 48),
        HomeInvitation(onAccount: onAccount),
      ],
    ),
  );
}

class HomeFooter extends StatelessWidget {
  const HomeFooter({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
    decoration: const BoxDecoration(
      color: HavenTheme.white,
      border: Border(top: BorderSide(color: HavenTheme.border)),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 32,
      runSpacing: 16,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(HavenIcons.homeRounded, color: HavenTheme.forest),
            const SizedBox(width: 10),
            Text('Haven Link', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        Text(
          '© ${DateTime.now().year} Haven Link · English / Kiswahili · Tanzania',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class HomeInvitation extends StatelessWidget {
  const HomeInvitation({this.onAccount, super.key});
  final VoidCallback? onAccount;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: ColoredBox(
      color: HavenTheme.lightMint,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copy = Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HomeSectionHeading(
                  kicker: 'Ready to begin?',
                  title: 'Your space on Haven Link starts here.',
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr(
                    'Find your next stay or home, or manage your approved partner workspace.',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onAccount,
                  icon: const Icon(HavenIcons.arrowForward, size: 18),
                  label: Text(context.tr('Continue to your account')),
                ),
              ],
            ),
          );
          final photo = Image.asset(
            'assets/images/home-invitation.jpg',
            height: 320,
            width: double.infinity,
            fit: BoxFit.cover,
            semanticLabel: 'A place to stay in Tanzania',
          );
          if (constraints.maxWidth < 900) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, photo],
            );
          }
          return Row(
            children: [
              Expanded(flex: 5, child: copy),
              Expanded(flex: 4, child: photo),
            ],
          );
        },
      ),
    ),
  );
}
