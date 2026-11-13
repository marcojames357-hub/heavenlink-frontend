import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/widgets/property_card.dart';

class PropertyBrowseScreen extends StatefulWidget {
  const PropertyBrowseScreen({
    required this.store,
    required this.businessModel,
    required this.onOpenProperty,
    this.onOpenStay,
    this.initialQuery = '',
    this.initialCategory,
    super.key,
  });

  final String initialQuery;
  final String? initialCategory;
  final HavenLinkStore store;
  final PropertyBusinessModel businessModel;
  final ValueChanged<Property> onOpenProperty;
  final void Function(Property property, DateTimeRange? dates, int guests)?
  onOpenStay;

  @override
  State<PropertyBrowseScreen> createState() => _PropertyBrowseScreenState();
}

class _PropertyBrowseScreenState extends State<PropertyBrowseScreen> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';
  String? _city;
  String? _category;
  int? _bedrooms;
  int? _bathrooms;
  bool _verifiedOnly = false;
  bool _availableOnly = true;
  bool? _furnished;
  bool _parking = false;
  bool _water = false;
  bool _electricity = false;
  bool _security = false;
  RangeValues _priceRange = const RangeValues(0, 2500000);
  final Set<String> _selectedAmenities = {};
  bool get _isBookable => businessModelIsBookable(widget.businessModel);

  List<Property> get _results {
    return widget.store.properties.where((property) {
      if (property.businessModel != widget.businessModel) return false;
      final query = _query.trim().toLowerCase();
      final matchesQuery =
          query.isEmpty ||
          '${property.name} ${property.city} ${property.neighborhood} ${property.amenities.join(' ')}'
              .toLowerCase()
              .contains(query);
      return matchesQuery &&
          (_city == null || property.city == _city) &&
          _matchesCategory(property) &&
          (_bedrooms == null || property.bedrooms >= _bedrooms!) &&
          (_bathrooms == null || property.bathrooms >= _bathrooms!) &&
          property.priceTzs >= _priceRange.start &&
          property.priceTzs <= _priceRange.end &&
          _selectedAmenities.every(property.amenities.contains) &&
          (!_verifiedOnly || property.isVerified) &&
          (!_availableOnly || property.available) &&
          (_furnished == null || property.furnished == _furnished) &&
          (!_parking || property.parking) &&
          (!_water || property.water) &&
          (!_electricity || property.electricity) &&
          (!_security || property.security);
    }).toList();
  }

  bool _matchesCategory(Property property) => switch (_category) {
    null => true,
    'apartment' =>
      property.category == PropertyCategory.servicedApartment ||
          property.category == PropertyCategory.shortStayApartment,
    _ => property.category.name == _category,
  };

  bool get _hasStayTypes => _isBookable;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _queryController.text = _query;
    _category = widget.initialCategory;
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = context.tr(_isBookable ? 'Stays to book' : 'Homes to rent');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 5),
        Text(
          context.tr(
            _isBookable
                ? 'Browse places to stay and book directly with Haven Link.'
                : 'Compare homes. Exact address and verified contact unlock after payment.',
          ),
          style: const TextStyle(color: HavenTheme.muted),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _queryController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: context.tr('Location, property or amenity'),
                  prefixIcon: const Icon(HavenIcons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.tr('Clear search'),
                          onPressed: () {
                            _queryController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(HavenIcons.close),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: context.tr('Filters'),
              onPressed: _showFilters,
              icon: const Icon(HavenIcons.tune),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_hasStayTypes) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (label, value) in const [
                  ('All stays', null),
                  ('Hotels', 'hotel'),
                  ('Motels', 'motel'),
                  ('Lodges', 'lodge'),
                  ('Apartments', 'apartment'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _category == value,
                      onSelected: (_) => setState(() => _category = value),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final city in [
                'Mikocheni',
                'Masaki',
                'Mbezi Beach',
                'Sinza',
                'Arusha',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(city),
                    selected: _query.toLowerCase() == city.toLowerCase(),
                    onSelected: (_) {
                      _queryController.text = city;
                      setState(() => _query = city);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_results.length} ${context.tr(_results.length == 1 ? 'property found' : 'properties found')}',
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(_clearFilters),
              icon: const Icon(HavenIcons.restartAlt, size: 17),
              label: Text(context.tr('Reset')),
            ),
          ],
        ),
        if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Column(
              children: [
                const Icon(
                  HavenIcons.searchOff,
                  size: 48,
                  color: HavenTheme.muted,
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('No properties found'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(context.tr('Try a broader location or remove a filter.')),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 860
                  ? 3
                  : constraints.maxWidth > 560
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _results.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 390,
                ),
                itemBuilder: (context, index) => PropertyCard(
                  property: _results[index],
                  store: widget.store,
                  onTap: () {
                    final property = _results[index];
                    if (widget.onOpenStay != null &&
                        const {
                          PropertyCategory.hotel,
                          PropertyCategory.motel,
                          PropertyCategory.lodge,
                        }.contains(property.category)) {
                      widget.onOpenStay!(property, null, 2);
                    } else {
                      widget.onOpenProperty(property);
                    }
                  },
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _showFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.88,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
              children: [
                Text(
                  context.tr('Filter properties'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _city,
                  decoration: InputDecoration(labelText: context.tr('City')),
                  items:
                      const [
                            'Dar es Salaam',
                            'Arusha',
                            'Dodoma',
                            'Mwanza',
                            'Zanzibar',
                          ]
                          .map(
                            (city) => DropdownMenuItem(
                              value: city,
                              child: Text(city),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setSheetState(() => _city = value),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: context.tr('Property type'),
                  ),
                  items: _categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(_label(category)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setSheetState(() => _category = value),
                ),
                const SizedBox(height: 18),
                Text(
                  '${context.tr('Price range')}: ${formatTzs(_priceRange.start.round())} – ${formatTzs(_priceRange.end.round())}',
                ),
                RangeSlider(
                  values: _priceRange,
                  min: 0,
                  max: _isBookable ? 2500000 : 3000000,
                  divisions: 24,
                  labels: RangeLabels(
                    formatTzs(_priceRange.start.round()),
                    formatTzs(_priceRange.end.round()),
                  ),
                  onChanged: (value) =>
                      setSheetState(() => _priceRange = value),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('Minimum bedrooms'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [null, 1, 2, 3, 4]
                      .map(
                        (beds) => ChoiceChip(
                          label: Text(beds?.toString() ?? context.tr('Any')),
                          selected: beds == _bedrooms,
                          onSelected: (_) =>
                              setSheetState(() => _bedrooms = beds),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  context.tr('Minimum bathrooms'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [null, 1, 2, 3]
                      .map(
                        (baths) => ChoiceChip(
                          label: Text(baths?.toString() ?? context.tr('Any')),
                          selected: baths == _bathrooms,
                          onSelected: (_) =>
                              setSheetState(() => _bathrooms = baths),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  context.tr('Amenities'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _amenityOptions
                      .map(
                        (amenity) => FilterChip(
                          label: Text(amenity),
                          selected: _selectedAmenities.contains(amenity),
                          onSelected: (selected) => setSheetState(() {
                            if (selected) {
                              _selectedAmenities.add(amenity);
                            } else {
                              _selectedAmenities.remove(amenity);
                            }
                          }),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Verified property and owner')),
                  value: _verifiedOnly,
                  onChanged: (value) =>
                      setSheetState(() => _verifiedOnly = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Available now')),
                  value: _availableOnly,
                  onChanged: (value) =>
                      setSheetState(() => _availableOnly = value),
                ),
                if (!_isBookable) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('Furnished')),
                    value: _furnished == true,
                    onChanged: (value) =>
                        setSheetState(() => _furnished = value ? true : null),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('Parking')),
                    value: _parking,
                    onChanged: (value) => setSheetState(() => _parking = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('Water available')),
                    value: _water,
                    onChanged: (value) => setSheetState(() => _water = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('Electricity')),
                    value: _electricity,
                    onChanged: (value) =>
                        setSheetState(() => _electricity = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('Security')),
                    value: _security,
                    onChanged: (value) =>
                        setSheetState(() => _security = value),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {});
                  },
                  child: Text(context.tr('Show matching properties')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> get _categories => _isBookable
      ? ['hotel', 'lodge', 'servicedApartment', 'shortStayApartment']
      : ['house', 'room', 'sharedAccommodation'];

  String _label(String value) => switch (value) {
    'servicedApartment' => 'Serviced apartment',
    'shortStayApartment' => 'Short-stay apartment',
    'sharedAccommodation' => 'Shared accommodation',
    _ => value[0].toUpperCase() + value.substring(1),
  };

  void _clearFilters() {
    _queryController.clear();
    _query = '';
    _city = null;
    _category = null;
    _bedrooms = null;
    _verifiedOnly = false;
    _availableOnly = true;
    _furnished = null;
    _parking = false;
    _water = false;
    _electricity = false;
    _security = false;
    _priceRange = RangeValues(0, _isBookable ? 2500000 : 3000000);
    _bathrooms = null;
    _selectedAmenities.clear();
  }

  List<String> get _amenityOptions => _isBookable
      ? ['Wi-Fi', 'Pool', 'Air conditioning', 'Garden', 'Parking']
      : ['Garden', 'Parking', 'Water', 'Electricity', 'Security'];
}

bool businessModelIsBookable(PropertyBusinessModel value) =>
    value == PropertyBusinessModel.bookable;
