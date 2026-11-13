import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../properties/domain/property.dart';
import '../../reviews/presentation/widgets/attachment_picker.dart';
import '../domain/agent_models.dart';
import '../state/agent_portal_store.dart';
import 'pin_map.dart';
import 'room_inventory_tab.dart' show RoomCategoryDialog;

Future<void> showListingEditorDialog({
  required BuildContext context,
  required HavenLinkStore store,
  required PropertyBusinessModel businessModel,
  Property? initial,
  List<PropertyCategory>? categories,
  UploadPicker picker = pickUploads,
  AgentPortalStore? agentStore,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => ShadTheme(
      data: HavenTheme.shadcn,
      child: _ListingEditorDialog(
        store: store,
        businessModel: businessModel,
        initial: initial,
        categories: categories,
        picker: picker,
        agentStore: agentStore,
      ),
    ),
  );
}

class _ListingEditorDialog extends StatefulWidget {
  const _ListingEditorDialog({
    required this.store,
    required this.businessModel,
    required this.picker,
    this.initial,
    this.categories,
    this.agentStore,
  });

  final UploadPicker picker;
  final HavenLinkStore store;
  final PropertyBusinessModel businessModel;
  final Property? initial;

  /// Lets a new hotel create its room categories and rooms inside the wizard.
  final AgentPortalStore? agentStore;

  /// Restricts the category choices to one workspace (apartments or hotels).
  final List<PropertyCategory>? categories;

  @override
  State<_ListingEditorDialog> createState() => _ListingEditorDialogState();
}

class _ListingEditorDialogState extends State<_ListingEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _city = TextEditingController(text: widget.initial?.city ?? '');
  late final _neighborhood = TextEditingController(
    text: widget.initial?.neighborhood ?? '',
  );
  late final _latitude = TextEditingController(
    text: widget.initial?.latitude?.toString() ?? '',
  );
  late final _longitude = TextEditingController(
    text: widget.initial?.longitude?.toString() ?? '',
  );
  late final _formattedAddress = TextEditingController(
    text: widget.initial?.formattedAddress ?? '',
  );
  late final _price = TextEditingController(
    text: widget.initial?.priceTzs.toString() ?? '',
  );
  late final _imageUrl = TextEditingController(
    text: widget.initial?.imageUrl ?? '',
  );
  late final _moreImages = TextEditingController(
    text: widget.initial?.imageUrls.join('\n') ?? '',
  );
  late final _description = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late final _amenities = TextEditingController(
    text: widget.initial?.amenities.join(', ') ?? '',
  );
  late final _amenityDetails = TextEditingController(
    text:
        widget.initial?.amenityDetails
            .map(
              (item) => item.description.trim().isEmpty
                  ? item.name
                  : '${item.name} | ${item.description}',
            )
            .join('\n') ??
        '',
  );
  late final _bedrooms = TextEditingController(
    text: widget.initial?.bedrooms.toString() ?? '1',
  );
  late final _bathrooms = TextEditingController(
    text: widget.initial?.bathrooms.toString() ?? '1',
  );
  late final _maxGuests = TextEditingController(
    text: widget.initial?.maxGuests?.toString() ?? '',
  );
  late final _minNights = TextEditingController(
    text: widget.initial?.stayRules?.minNights?.toString() ?? '',
  );
  late final _maxNights = TextEditingController(
    text: widget.initial?.stayRules?.maxNights?.toString() ?? '',
  );
  late final _checkInTime = TextEditingController(
    text: widget.initial?.stayRules?.checkInTime ?? '',
  );
  late final _checkOutTime = TextEditingController(
    text: widget.initial?.stayRules?.checkOutTime ?? '',
  );
  late final _cancellationPolicy = TextEditingController(
    text: widget.initial?.stayRules?.cancellationPolicy ?? '',
  );
  late final _houseRules = TextEditingController(
    text: widget.initial?.stayRules?.houseRules ?? '',
  );
  late final _weekendPrice = TextEditingController(
    text: widget.initial?.stayRules?.weekendPriceTzs?.toString() ?? '',
  );
  late final _cleaningFee = TextEditingController(
    text: widget.initial?.stayRules?.cleaningFeeTzs?.toString() ?? '',
  );
  late final _beds = TextEditingController(
    text: widget.initial?.stayRules?.beds?.toString() ?? '',
  );
  late final _country = TextEditingController(
    text: widget.initial?.stayRules?.country.isNotEmpty == true
        ? widget.initial!.stayRules!.country
        : 'Tanzania',
  );
  late final _region = TextEditingController(
    text: widget.initial?.stayRules?.region ?? '',
  );
  late PropertyCategory _category =
      widget.initial?.category ??
      widget.categories?.first ??
      (widget.businessModel == PropertyBusinessModel.contactUnlock
          ? PropertyCategory.house
          : PropertyCategory.hotel);
  late String _rentalPeriod = widget.initial?.rentalPeriod ?? 'month';
  late bool _available = widget.initial?.available ?? true;
  late LocationVisibility _locationVisibility =
      widget.initial?.locationVisibility ?? LocationVisibility.approximate;
  bool _saving = false;
  bool _locating = false;
  int _currentStep = 0;
  String? _locationError;
  double? _locationAccuracy;

  static const _features = [
    (key: 'furnished', label: 'Furnished'),
    (key: 'parking', label: 'Parking'),
    (key: 'water', label: 'Water supply'),
    (key: 'electricity', label: 'Electricity'),
    (key: 'security', label: 'Security'),
  ];
  late final Map<String, bool> _flags = {
    'furnished': widget.initial?.furnished ?? false,
    'parking': widget.initial?.parking ?? false,
    'water': widget.initial?.water ?? false,
    'electricity': widget.initial?.electricity ?? false,
    'security': widget.initial?.security ?? false,
  };
  static const _predefinedAmenities = [
    'Restaurant',
    'Bar',
    'Swimming pool',
    'Parking',
    'Wi-Fi',
    'Reception',
    '24-hour reception',
    'Security',
    'Conference facilities',
    'Breakfast',
    'Airport transfer',
    'Laundry service',
    'Garden',
  ];
  static const _apartmentAmenities = [
    'Wi-Fi',
    'Kitchen',
    'Air conditioning',
    'Television',
    'Refrigerator',
    'Parking',
    'Hot water',
    'Balcony',
    'Washing machine',
    'Security',
  ];
  List<String> get _amenityOptions =>
      _isApartment ? _apartmentAmenities : _predefinedAmenities;
  late final Set<String> _selectedAmenities = {
    ...?widget.initial?.amenities,
    ...?widget.initial?.amenityDetails.map((item) => item.name),
  };

  List<PropertyCategory> get _categories =>
      widget.categories ??
      (widget.businessModel == PropertyBusinessModel.contactUnlock
          ? const [
              PropertyCategory.house,
              PropertyCategory.room,
              PropertyCategory.sharedAccommodation,
            ]
          : const [
              PropertyCategory.hotel,
              PropertyCategory.motel,
              PropertyCategory.lodge,
              PropertyCategory.servicedApartment,
              PropertyCategory.shortStayApartment,
            ]);

  bool get _isApartment =>
      widget.businessModel == PropertyBusinessModel.bookable &&
      _category.isApartmentStay;

  String? _optionalNights(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    return parsed == null || parsed < 1 || parsed > 365
        ? 'Enter 1â€“365'
        : null;
  }

  String? _optionalAmount(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    return parsed == null || parsed < 0 ? 'Enter a valid amount' : null;
  }

  String? _optionalTime(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty || RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(text)
        ? null
        : 'Use HH:MM';
  }

  List<Widget> _apartmentGuestFields() => [
    const SizedBox(height: 10),
    TextFormField(
      controller: _beds,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Beds (optional)'),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return null;
        final parsed = int.tryParse(text);
        return parsed == null || parsed < 1 || parsed > 50
            ? 'Enter 1â€“50'
            : null;
      },
    ),
    const SizedBox(height: 10),
    TextFormField(
      controller: _maxGuests,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Maximum guests',
        helperText: 'The whole apartment is one bookable unit.',
      ),
      validator: (value) {
        final parsed = int.tryParse(value?.trim() ?? '');
        return parsed == null || parsed < 1 || parsed > 50
            ? 'Enter 1â€“50'
            : null;
      },
    ),
  ];

  List<Widget> _apartmentStayLimitFields() => [
    const SizedBox(height: 10),
    Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _weekendPrice,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Weekend price (TZS)',
              helperText: 'Optional, Fri & Sat nights',
            ),
            validator: _optionalAmount,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _cleaningFee,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cleaning fee (TZS)',
              helperText: 'Optional, once per stay',
            ),
            validator: _optionalAmount,
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _minNights,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Minimum nights'),
            validator: _optionalNights,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _maxNights,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Maximum nights'),
            validator: (value) {
              final basic = _optionalNights(value);
              if (basic != null) return basic;
              final max = int.tryParse(value?.trim() ?? '');
              final min = int.tryParse(_minNights.text.trim());
              return max != null && min != null && max < min
                  ? 'Below minimum'
                  : null;
            },
          ),
        ),
      ],
    ),
  ];

  List<Widget> _apartmentRuleFields() => [
    const SizedBox(height: 10),
    Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _checkInTime,
            decoration: const InputDecoration(
              labelText: 'Check-in time',
              hintText: '14:00',
            ),
            validator: _optionalTime,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _checkOutTime,
            decoration: const InputDecoration(
              labelText: 'Check-out time',
              hintText: '10:00',
            ),
            validator: _optionalTime,
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    TextFormField(
      controller: _cancellationPolicy,
      maxLines: 2,
      maxLength: 1000,
      decoration: const InputDecoration(labelText: 'Cancellation policy'),
    ),
    TextFormField(
      controller: _houseRules,
      maxLines: 3,
      maxLength: 2000,
      decoration: const InputDecoration(labelText: 'House rules'),
    ),
  ];

  StayRules? _buildStayRules() {
    if (!_isApartment) return null;
    return StayRules(
      minNights: int.tryParse(_minNights.text.trim()),
      maxNights: int.tryParse(_maxNights.text.trim()),
      checkInTime: _checkInTime.text.trim(),
      checkOutTime: _checkOutTime.text.trim(),
      cancellationPolicy: _cancellationPolicy.text.trim(),
      houseRules: _houseRules.text.trim(),
      weekendPriceTzs: int.tryParse(_weekendPrice.text.trim()),
      cleaningFeeTzs: int.tryParse(_cleaningFee.text.trim()),
      beds: int.tryParse(_beds.text.trim()),
      country: _country.text.trim(),
      region: _region.text.trim(),
      photoLabels: {
        for (final url in {
          _imageUrl.text.trim(),
          ..._moreImages.text.split('\n').map((line) => line.trim()),
        })
          if (_photoLabels[url] != null) url: _photoLabels[url]!,
      },
    );
  }

  bool get _isHotelFlow =>
      widget.businessModel == PropertyBusinessModel.bookable &&
      const {
        PropertyCategory.hotel,
        PropertyCategory.motel,
        PropertyCategory.lodge,
      }.contains(_category);

  final List<_CategoryDraft> _drafts = [];
  bool _showPinMap = false;
  String? _categoryError;

  bool get _draftCategoriesEnabled =>
      _isHotelFlow && widget.initial == null && widget.agentStore != null;

  List<String> get _stepTitles => _isHotelFlow
      ? const [
          'Property information',
          'Overall amenities',
          'Room categories',
          'Pricing and availability',
          'Review and publish',
        ]
      : _isApartment
      ? const [
          'Apartment details',
          'Location',
          'Amenities',
          'Photos',
          'Pricing',
          'Rules',
          'Preview and publish',
        ]
      : const [
          'Property information',
          'Pricing and details',
          'Review and publish',
        ];

  int get _locationStep => _isApartment ? 1 : 0;
  int get _amenitiesStep => _isApartment ? 2 : 1;
  int get _photosStep => _isApartment ? 3 : _pricingStep;
  int get _pricingStep => _isHotelFlow ? 3 : (_isApartment ? 4 : 1);
  int get _rulesStep => _isApartment ? 5 : -1;
  int get _bedroomsStep => _isApartment ? 0 : _pricingStep;
  int get _reviewStep => _stepTitles.length - 1;

  bool _uploading = false;
  String? _photoMessage;
  static const _photoGroups = [
    'Cover',
    'Living room',
    'Bedroom',
    'Bathroom',
    'Kitchen',
    'Exterior',
  ];
  String _photoGroup = _photoGroups.first;
  late final Map<String, String> _photoLabels = Map.of(
    widget.initial?.stayRules?.photoLabels ?? const {},
  );

  Future<void> _uploadPhotos() async {
    setState(() {
      _uploading = true;
      _photoMessage = null;
    });
    try {
      final picked = await widget.picker(pdf: false);
      if (picked.isEmpty) return;
      if (picked.length > maxUploads) {
        throw StateError('Choose up to $maxUploads photos at a time.');
      }
      if (picked.any((file) => file.bytes.length > maxUploadBytes)) {
        throw StateError('Each photo must be 5 MB or smaller.');
      }
      final urls = await widget.store.uploadListingPhotos(picked);
      if (!mounted || urls.isEmpty) return;
      setState(() {
        for (final url in urls) {
          _photoLabels[url] = _photoGroup;
        }
        var rest = urls;
        if (_imageUrl.text.trim().isEmpty) {
          _imageUrl.text = urls.first;
          rest = urls.skip(1).toList();
        }
        final existing = _moreImages.text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty);
        _moreImages.text = [...existing, ...rest].join('\n');
      });
    } on StateError catch (error) {
      if (mounted) setState(() => _photoMessage = error.message);
    } catch (_) {
      if (mounted) setState(() => _photoMessage = 'Photos could not be added.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) {
      _captureLocation();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _neighborhood.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _formattedAddress.dispose();
    _price.dispose();
    _imageUrl.dispose();
    _moreImages.dispose();
    _description.dispose();
    _amenities.dispose();
    _amenityDetails.dispose();
    _bedrooms.dispose();
    _bathrooms.dispose();
    _maxGuests.dispose();
    _minNights.dispose();
    _maxNights.dispose();
    _checkInTime.dispose();
    _checkOutTime.dispose();
    _cancellationPolicy.dispose();
    _houseRules.dispose();
    _weekendPrice.dispose();
    _cleaningFee.dispose();
    _country.dispose();
    _region.dispose();
    _beds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRental =
        widget.businessModel == PropertyBusinessModel.contactUnlock;
    final steps = _stepTitles;
    if (_currentStep >= steps.length) _currentStep = steps.length - 1;
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? isRental
                  ? 'New rental listing'
                  : 'New stay listing'
            : 'Edit listing',
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WizardHeader(
                  title: steps[_currentStep],
                  subtitle: 'Step ${_currentStep + 1} of ${steps.length}',
                  progress: (_currentStep + 1) / steps.length,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      ChoiceChip(
                        label: Text('${i + 1}. ${steps[i]}'),
                        selected: i == _currentStep,
                        onSelected: _saving ? null : (_) => _selectStep(i),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_currentStep == 0) ...[
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Listing title',
                    ),
                    validator: (value) => _required(value, 3, 'Enter a title.'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<PropertyCategory>(
                    isExpanded: true,
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Property type',
                    ),
                    items: _categories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(_categoryLabel(category)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() {
                      if (value != null) _category = value;
                    }),
                  ),
                ],
                if (_currentStep == _locationStep) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Property location',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _formattedAddress,
                    decoration: const InputDecoration(
                      labelText: 'Formatted address (private for rentals)',
                    ),
                    validator: (value) => value != null && value.length > 500
                        ? 'Keep the address under 500 characters.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Location tip: You must be at the property you are adding '
                      'or updating when capturing its location. Allow precise '
                      'device location access when prompted.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _locating || _saving ? null : _captureLocation,
                      icon: _locating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(HavenIcons.myLocation),
                      label: Text(
                        _locating
                            ? 'Getting location...'
                            : 'Use current location',
                      ),
                    ),
                  ),
                  if (_locationAccuracy != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Reported accuracy: approximately ${_locationAccuracy!.ceil()} m. '
                        'Move to an open area and try again if this is inaccurate.',
                      ),
                    ),
                  if (_locationError != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _locationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latitude,
                          readOnly: !_isApartment,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                          validator: _isApartment
                              ? (value) => _coordinate(value, 90, 'latitude')
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _longitude,
                          readOnly: !_isApartment,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                          validator: _isApartment
                              ? (value) => _coordinate(value, 180, 'longitude')
                              : null,
                        ),
                      ),
                    ],
                  ),
                  if (_isApartment) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _previewPin,
                        icon: const Icon(HavenIcons.mapOutlined),
                        label: Text(
                          _showPinMap ? 'Hide map' : 'Check pin on map',
                        ),
                      ),
                    ),
                    if (_showPinMap &&
                        double.tryParse(_latitude.text.trim()) != null &&
                        double.tryParse(_longitude.text.trim()) != null)
                      PinMap(
                        latitude: double.parse(_latitude.text.trim()),
                        longitude: double.parse(_longitude.text.trim()),
                        onMoved: _movePin,
                      ),
                    const Text(
                      'Tap the map or adjust the coordinates if the pin is not on the building entrance.',
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (!isRental) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<LocationVisibility>(
                      isExpanded: true,
                      initialValue: _locationVisibility,
                      decoration: const InputDecoration(
                        labelText: 'Customer map visibility',
                      ),
                      items: LocationVisibility.values
                          .map(
                            (visibility) => DropdownMenuItem(
                              value: visibility,
                              child: Text(switch (visibility) {
                                LocationVisibility.exact => 'Exact location',
                                LocationVisibility.approximate =>
                                  'Approximate location',
                                LocationVisibility.hidden => 'Hidden',
                              }),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() {
                        if (value != null) _locationVisibility = value;
                      }),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (_isApartment) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _country,
                            decoration: const InputDecoration(
                              labelText: 'Country',
                            ),
                            validator: (value) =>
                                _required(value, 2, 'Enter a country.'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _region,
                            decoration: const InputDecoration(
                              labelText: 'Region / state',
                            ),
                            validator: (value) =>
                                _required(value, 2, 'Enter a region.'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _city,
                          decoration: const InputDecoration(labelText: 'City'),
                          validator: (value) =>
                              _required(value, 2, 'Enter a city.'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _neighborhood,
                          decoration: const InputDecoration(
                            labelText: 'Area / neighbourhood',
                          ),
                          validator: (value) =>
                              _required(value, 2, 'Enter an area.'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_currentStep == _pricingStep) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _price,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: isRental
                                ? 'Rent (TZS)'
                                : 'Price per night (TZS)',
                          ),
                          validator: (value) =>
                              int.tryParse(value ?? '') == null ||
                                  int.parse(value!) < 0
                              ? 'Enter a valid amount.'
                              : null,
                        ),
                      ),
                      if (isRental) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _rentalPeriod,
                            decoration: const InputDecoration(
                              labelText: 'Period',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'week',
                                child: Text('Weekly'),
                              ),
                              DropdownMenuItem(
                                value: 'month',
                                child: Text('Monthly'),
                              ),
                              DropdownMenuItem(
                                value: 'year',
                                child: Text('Yearly'),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              if (value != null) _rentalPeriod = value;
                            }),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_isApartment) ..._apartmentStayLimitFields(),
                ],
                if (_currentStep == _photosStep) ...[
                  const SizedBox(height: 10),
                  if (_isApartment) ...[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _photoGroup,
                      decoration: const InputDecoration(
                        labelText: 'Photo area for the next upload',
                      ),
                      items: [
                        for (final group in _photoGroups)
                          DropdownMenuItem(value: group, child: Text(group)),
                      ],
                      onChanged: (value) => setState(() {
                        if (value != null) _photoGroup = value;
                      }),
                    ),
                    const SizedBox(height: 10),
                  ],
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _uploadPhotos,
                    icon: _uploading
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(HavenIcons.uploadOutlined),
                    label: Text(
                      _uploading ? 'Uploading...' : 'Upload photos from device',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _photoMessage ??
                          'JPG, PNG or WebP, up to 5 MB each. The first photo becomes the cover.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _photoMessage == null
                            ? Theme.of(context).hintColor
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _imageUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Cover photograph URL',
                    ),
                    validator: (value) =>
                        Uri.tryParse(value ?? '')?.hasAbsolutePath == true &&
                            (value?.startsWith('https://') ?? false)
                        ? null
                        : 'Enter a secure image URL.',
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _moreImages,
                    maxLines: 2,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      labelText: 'More photograph URLs',
                      helperText:
                          'Separate each secure image URL with a new line.',
                    ),
                  ),
                ],
                if (_currentStep == _bedroomsStep) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _bedrooms,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Bedrooms',
                          ),
                          validator: _wholeNumber,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _bathrooms,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Bathrooms',
                          ),
                          validator: _wholeNumber,
                        ),
                      ),
                    ],
                  ),
                  if (_isApartment) ..._apartmentGuestFields(),
                ],
                if (_currentStep == _rulesStep) ..._apartmentRuleFields(),
                if (_currentStep == _amenitiesStep) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _amenities,
                    decoration: const InputDecoration(
                      labelText: 'Additional amenities',
                      helperText:
                          'Legacy/simple amenity names, comma separated.',
                    ),
                  ),
                  if (_isHotelFlow || _isApartment) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _isApartment
                            ? 'Apartment amenities'
                            : 'Property facilities',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final amenity in _amenityOptions)
                          FilterChip(
                            label: Text(amenity),
                            selected: _selectedAmenities.contains(amenity),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _selectedAmenities.add(amenity);
                              } else {
                                _selectedAmenities.remove(amenity);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _amenityDetails,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Amenity descriptions',
                      helperText:
                          'One per line: Amenity name | optional guest guidance. Edit or remove lines as needed.',
                    ),
                  ),
                ],
                if (_currentStep == 0) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Description'),
                    validator: (value) =>
                        _required(value, 10, 'Add more detail.'),
                  ),
                ],
                if (_currentStep == _pricingStep) ...[
                  for (final feature in _features)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(feature.label),
                      value: _flags[feature.key]!,
                      onChanged: (value) =>
                          setState(() => _flags[feature.key] = value),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Available'),
                    value: _available,
                    onChanged: (value) => setState(() => _available = value),
                  ),
                ],
                if (_isHotelFlow && _currentStep == 2) _roomInventoryStep(),
                if (_currentStep == _reviewStep) _reviewStepContent(isRental),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (widget.initial == null)
          TextButton.icon(
            onPressed: _saving || _locating ? null : () => _save(asDraft: true),
            icon: const Icon(HavenIcons.saveAsOutlined),
            label: const Text('Save draft'),
          ),
        TextButton(
          onPressed: _saving || _currentStep == 0
              ? null
              : () => setState(() => _currentStep--),
          child: const Text('Back'),
        ),
        if (_currentStep < _reviewStep)
          FilledButton(
            onPressed: _saving || _locating ? null : _continue,
            child: const Text('Continue'),
          ),
        if (_currentStep == _reviewStep)
          ShadButton(
            onPressed: _saving || _locating ? null : () => _save(),
            enabled: !_saving && !_locating,
            leading: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.save, size: 16),
            child: Text(_saving ? 'Saving' : 'Save listing'),
          ),
      ],
    );
  }

  void _selectStep(int target) {
    if (target <= _currentStep) {
      setState(() => _currentStep = target);
      return;
    }
    if (target == _currentStep + 1) _continue();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    if (_draftCategoriesEnabled && _currentStep == 2 && _drafts.isEmpty) {
      setState(
        () => _categoryError = 'Add at least one room category to continue.',
      );
      return;
    }
    if (_currentStep == _locationStep &&
        widget.initial == null &&
        (_latitude.text.trim().isEmpty || _longitude.text.trim().isEmpty)) {
      setState(
        () => _locationError =
            'Capture your current location at the property before continuing.',
      );
      return;
    }
    setState(() => _currentStep++);
  }

  Widget _roomInventoryStep() {
    if (!_draftCategoriesEnabled) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Room categories and physical rooms for an existing property are managed from Room Categories and Physical Rooms in the sidebar.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Room categories and physical rooms',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Add each category with its own price, amenities and photos, then optionally list the real room identifiers (such as A01 or 101). Rooms entered here are assigned to the category automatically.',
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _drafts.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(HavenIcons.bedOutlined),
                title: Text(_drafts[i].type.name),
                subtitle: Text(
                  '${_drafts[i].type.nightlyPriceTzs} TZS / night Â· up to ${_drafts[i].type.capacity} guests Â· ${_drafts[i].roomNumbers.length} of ${_drafts[i].type.totalRooms} rooms named',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Edit category',
                      icon: const Icon(HavenIcons.editOutlined),
                      onPressed: () => _editCategory(i),
                    ),
                    IconButton(
                      tooltip: 'Room identifiers',
                      icon: const Icon(HavenIcons.meetingRoomOutlined),
                      onPressed: () => _editRoomNumbers(i),
                    ),
                    IconButton(
                      tooltip: 'Remove category',
                      icon: const Icon(HavenIcons.deleteOutline),
                      onPressed: () => setState(() => _drafts.removeAt(i)),
                    ),
                  ],
                ),
              ),
            if (_categoryError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _categoryError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => _editCategory(null),
              icon: const Icon(HavenIcons.add),
              label: const Text('Add room category'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCategory(int? index) async {
    final existing = index == null ? null : _drafts[index];
    final type = await showDialog<RoomType>(
      context: context,
      builder: (context) => RoomCategoryDialog(
        listingId: 'draft',
        defaultRooms: 1,
        initial: existing?.type,
      ),
    );
    if (type == null || !mounted) return;
    setState(() {
      _categoryError = null;
      if (index == null) {
        _drafts.add(_CategoryDraft(type));
      } else {
        _drafts[index].type = type;
      }
    });
  }

  Future<void> _editRoomNumbers(int index) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _RoomNumbersDialog(
        title: 'Rooms in ${_drafts[index].type.name}',
        initial: _drafts[index].roomNumbers.join('\n'),
      ),
    );
    if (value == null || !mounted) return;
    final numbers = value
        .split(RegExp(r'[\r\n,]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final taken = {
      for (var i = 0; i < _drafts.length; i++)
        if (i != index) ..._drafts[i].roomNumbers.map((n) => n.toLowerCase()),
    };
    final seen = <String>{};
    final duplicate = numbers.any(
      (n) => taken.contains(n.toLowerCase()) || !seen.add(n.toLowerCase()),
    );
    setState(() {
      if (duplicate) {
        _categoryError = 'Room identifiers must be unique in the property.';
      } else {
        _categoryError = null;
        _drafts[index].roomNumbers = numbers;
      }
    });
  }

  /// Creates the wizard's categories and rooms after the hotel exists.
  Future<String?> _createDraftInventory(String listingId) async {
    final agentStore = widget.agentStore!;
    try {
      final created = <_CategoryDraft, RoomType>{};
      for (final draft in _drafts) {
        final type = draft.type;
        created[draft] = await agentStore.saveRoomType(
          RoomType(
            id: type.id,
            listingId: listingId,
            name: type.name,
            nightlyPriceTzs: type.nightlyPriceTzs,
            capacity: type.capacity,
            totalRooms: type.totalRooms,
            amenities: type.amenities,
            amenityDetails: type.amenityDetails,
            description: type.description,
            imageUrls: type.imageUrls,
            primaryImageUrl: type.primaryImageUrl,
            bedType: type.bedType,
            numberOfBeds: type.numberOfBeds,
            bathroomType: type.bathroomType,
            sizeSqm: type.sizeSqm,
          ),
        );
      }
      final allNumbers = [for (final d in _drafts) ...d.roomNumbers];
      if (allNumbers.isEmpty) return null;
      await agentStore.addPhysicalRooms(listingId, allNumbers);
      final rooms = await agentStore.loadPhysicalRooms(listingId);
      final idByNumber = {
        for (final room in rooms) room.roomNumber.toLowerCase(): room.id,
      };
      for (final entry in created.entries) {
        final ids = [
          for (final number in entry.key.roomNumbers)
            if (idByNumber[number.toLowerCase()] != null)
              idByNumber[number.toLowerCase()]!,
        ];
        if (ids.isEmpty) continue;
        await agentStore.assignRooms(
          listingId: listingId,
          roomIds: ids,
          roomTypeId: entry.value.id,
        );
      }
      return null;
    } catch (error) {
      return 'The hotel was saved, but its room setup was not completed: $error. Finish it from Room Categories and Physical Rooms.';
    }
  }

  Widget _reviewStepContent(bool isRental) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review listing',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('${_categoryLabel(_category)} Â· ${_name.text.trim()}'),
          Text(
            '${_neighborhood.text.trim()}, ${_city.text.trim()}'
            '${_isApartment ? ', ${_region.text.trim()}, ${_country.text.trim()}' : ''}',
          ),
          Text(
            '${isRental ? 'Rent' : 'Rate'}: ${_price.text.trim()} TZS / ${isRental ? _rentalPeriod : 'night'}',
          ),
          Text(
            'Facilities: ${{..._selectedAmenities, ..._parseAmenityDetails(_amenityDetails.text).map((item) => item.name)}.join(', ')}',
          ),
          const SizedBox(height: 8),
          if (_isApartment) ...[
            Text(
              '${_bedrooms.text.trim()} bedrooms Â· ${_bathrooms.text.trim()} bathrooms Â· up to ${_maxGuests.text.trim()} guests',
            ),
            Text(
              'Check-in ${_checkInTime.text.trim().isEmpty ? 'not set' : _checkInTime.text.trim()} Â· Check-out ${_checkOutTime.text.trim().isEmpty ? 'not set' : _checkOutTime.text.trim()}',
            ),
            const SizedBox(height: 8),
            const Text(
              'The whole apartment is one bookable unit. After saving, open Availability Calendar to open or block dates.',
            ),
          ] else if (_draftCategoriesEnabled) ...[
            for (final draft in _drafts)
              Text(
                '${draft.type.name}: ${draft.type.nightlyPriceTzs} TZS / night Â· ${draft.type.totalRooms} planned Â· ${draft.roomNumbers.length} named',
              ),
            const SizedBox(height: 8),
            const Text(
              'Saving creates the hotel, its room categories and the rooms you named, and submits it for review.',
            ),
          ] else
            const Text(
              'Saving submits the listing for review. Hotel room categories and physical inventory are managed after the accommodation record is created.',
            ),
        ],
      ),
    ),
  );

  String? _required(String? value, int minLength, String message) =>
      value == null || value.trim().length < minLength ? message : null;

  String? _wholeNumber(String? value) =>
      int.tryParse(value ?? '') == null || int.parse(value!) < 0
      ? 'Enter a whole number.'
      : null;

  String? _coordinate(String? value, double limit, String label) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed == null || parsed.abs() > limit
        ? 'Enter a valid $label.'
        : null;
  }

  void _previewPin() {
    final lat = double.tryParse(_latitude.text.trim());
    final lng = double.tryParse(_longitude.text.trim());
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      setState(() => _locationError = 'Enter valid coordinates first.');
      return;
    }
    setState(() {
      _locationError = null;
      _showPinMap = !_showPinMap;
    });
  }

  void _movePin(double latitude, double longitude) => setState(() {
    _latitude.text = latitude.toStringAsFixed(6);
    _longitude.text = longitude.toStringAsFixed(6);
  });

  Future<void> _captureLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      if (!kIsWeb) {
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw const _LocationCaptureException(
            'Turn on device location services and try again.',
          );
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw const _LocationCaptureException(
            'Location permission is denied. Allow precise location in your device settings and try again.',
          );
        }
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 30),
        ),
      ).timeout(const Duration(seconds: 35));
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180 ||
          !position.accuracy.isFinite ||
          position.accuracy < 0) {
        throw const _LocationCaptureException(
          'The device returned an invalid location. Please try again.',
        );
      }
      if (!mounted) return;
      setState(() {
        _latitude.text = position.latitude.toStringAsFixed(6);
        _longitude.text = position.longitude.toStringAsFixed(6);
        _locationAccuracy = position.accuracy > 0 ? position.accuracy : null;
      });
    } on _LocationCaptureException catch (error) {
      if (mounted) setState(() => _locationError = error.message);
    } on PermissionDeniedException {
      if (mounted) {
        setState(
          () => _locationError =
              'Location permission is denied. Allow location access in your browser or device settings and try again.',
        );
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _locationError =
              'Location request timed out. Check location services and try again.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _locationError = 'Could not get device location: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String _categoryLabel(PropertyCategory value) => switch (value) {
    PropertyCategory.hotel => 'Hotel',
    PropertyCategory.motel => 'Motel',
    PropertyCategory.lodge => 'Lodge',
    PropertyCategory.servicedApartment => 'Serviced apartment',
    PropertyCategory.shortStayApartment => 'Short-stay apartment',
    PropertyCategory.house => 'House',
    PropertyCategory.room => 'Room',
    PropertyCategory.sharedAccommodation => 'Shared accommodation',
  };

  (int, String)? _firstListingValidationError() {
    if (_name.text.trim().length < 3) return (0, 'Enter a listing title.');
    if (_city.text.trim().length < 2) return (0, 'Enter a city.');
    if (_neighborhood.text.trim().length < 2) return (0, 'Enter an area.');
    if (_isApartment &&
        (_country.text.trim().length < 2 || _region.text.trim().length < 2)) {
      return (_locationStep, 'Enter the country and region.');
    }
    if (_description.text.trim().length < 10) {
      return (0, 'Add a description of at least 10 characters.');
    }
    if (widget.initial == null &&
        (_latitude.text.trim().isEmpty || _longitude.text.trim().isEmpty)) {
      return (0, 'Capture the property location before saving.');
    }
    final price = int.tryParse(_price.text.trim());
    if (price == null || price < 0) {
      return (_pricingStep, 'Enter a valid price.');
    }
    final imageUri = Uri.tryParse(_imageUrl.text.trim());
    if (imageUri?.scheme != 'https' || !imageUri!.hasAuthority) {
      return (_pricingStep, 'Enter a secure HTTPS cover photo URL.');
    }
    if (int.tryParse(_bedrooms.text.trim()) == null ||
        int.parse(_bedrooms.text.trim()) < 0 ||
        int.tryParse(_bathrooms.text.trim()) == null ||
        int.parse(_bathrooms.text.trim()) < 0) {
      return (_pricingStep, 'Enter valid bedroom and bathroom counts.');
    }
    final details = _parseAmenityDetails(_amenityDetails.text);
    if (details.length > 100 ||
        details.any(
          (item) => item.name.length > 100 || item.description.length > 1000,
        )) {
      return (
        _amenitiesStep,
        'Amenity names must be at most 100 characters and descriptions at most 1,000.',
      );
    }
    return null;
  }

  Future<void> _save({bool asDraft = false}) async {
    final validationError = _firstListingValidationError();
    if (validationError != null) {
      setState(() => _currentStep = validationError.$1);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError.$2)));
      return;
    }
    if (widget.initial == null &&
        (_latitude.text.isEmpty || _longitude.text.isEmpty)) {
      setState(
        () => _locationError =
            'Capture your current location at the property before saving.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Capture your current location at the property before saving.',
          ),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final hotelTypes = {
      PropertyCategory.hotel,
      PropertyCategory.motel,
      PropertyCategory.lodge,
    };
    final old = widget.initial;
    final inventoryChanged =
        old != null &&
        widget.businessModel == PropertyBusinessModel.bookable &&
        hotelTypes.contains(old.category) != hotelTypes.contains(_category);
    if (inventoryChanged) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change inventory model?'),
          content: const Text(
            'This changes how the property is reserved. The change is only allowed when there are no existing bookings, room categories or physical rooms. Existing records are never removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm change'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _saving = true);
    final user = widget.store.currentUser;
    final amenityDetails = _parseAmenityDetails(_amenityDetails.text);
    final amenityNames = <String>{
      ..._amenities.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
      ..._selectedAmenities,
      ...amenityDetails.map((amenity) => amenity.name),
    };
    if (amenityDetails.length > 100 ||
        amenityDetails.any(
          (amenity) =>
              amenity.name.length > 100 || amenity.description.length > 1000,
        )) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Amenity names must be at most 100 characters and descriptions at most 1,000.',
          ),
        ),
      );
      return;
    }
    final property = Property(
      id: old?.id ?? 'new-${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text.trim(),
      city: _city.text.trim(),
      neighborhood: _neighborhood.text.trim(),
      latitude: double.tryParse(_latitude.text.trim()),
      longitude: double.tryParse(_longitude.text.trim()),
      formattedAddress: _formattedAddress.text.trim().isEmpty
          ? null
          : _formattedAddress.text.trim(),
      locationVerification:
          old?.locationVerification ?? VerificationStatus.unverified,
      locationVisibility: _locationVisibility,
      priceTzs: int.parse(_price.text),
      businessModel: widget.businessModel,
      category: _category,
      imageUrl: _imageUrl.text.trim(),
      imageUrls: _moreImages.text
          .split('\n')
          .map((value) => value.trim())
          .where((value) => value.startsWith('https://'))
          .toList(growable: false),
      rating: old?.rating ?? 0,
      reviewCount: old?.reviewCount ?? 0,
      bedrooms: int.parse(_bedrooms.text),
      bathrooms: int.parse(_bathrooms.text),
      maxGuests: _isApartment ? int.tryParse(_maxGuests.text.trim()) : null,
      stayRules: _buildStayRules(),
      amenities: amenityNames.toList(growable: false),
      amenityDetails: amenityDetails,
      description: _description.text.trim(),
      available: _available,
      furnished: _flags['furnished']!,
      parking: _flags['parking']!,
      water: _flags['water']!,
      electricity: _flags['electricity']!,
      security: _flags['security']!,
      propertyVerification:
          old?.propertyVerification ?? VerificationStatus.unverified,
      ownerVerification:
          old?.ownerVerification ?? VerificationStatus.unverified,
      managerName: old?.managerName ?? user?.fullName ?? 'Property manager',
      listingStatus: asDraft
          ? ListingStatus.draft
          : old?.listingStatus ?? ListingStatus.pendingReview,
      agentId: old?.agentId ?? user?.id ?? '',
      rentalPeriod: widget.businessModel == PropertyBusinessModel.contactUnlock
          ? _rentalPeriod
          : 'day',
      reportedCount: old?.reportedCount ?? 0,
    );

    try {
      final saved = await widget.store.saveListing(
        property,
        confirmInventoryModelChange: inventoryChanged,
        saveAsDraft: asDraft,
      );
      final setupError = _draftCategoriesEnabled && _drafts.isNotEmpty
          ? await _createDraftInventory(saved.id)
          : null;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      if (setupError != null) {
        messenger.showSnackBar(SnackBar(content: Text(setupError)));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

List<AmenityDetail> _parseAmenityDetails(String input) {
  final byName = <String, AmenityDetail>{};
  for (final line in input.split('\n')) {
    final parts = line.split('|');
    final name = parts.first.trim();
    if (name.isEmpty) continue;
    final description = parts.length > 1 ? parts.skip(1).join('|').trim() : '';
    byName[name.toLowerCase()] = AmenityDetail(
      name: name,
      description: description,
    );
  }
  return byName.values.toList(growable: false);
}

class _CategoryDraft {
  _CategoryDraft(this.type);

  RoomType type;
  List<String> roomNumbers = const [];
}

class _RoomNumbersDialog extends StatefulWidget {
  const _RoomNumbersDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_RoomNumbersDialog> createState() => _RoomNumbersDialogState();
}

class _RoomNumbersDialogState extends State<_RoomNumbersDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      minLines: 3,
      maxLines: 8,
      decoration: const InputDecoration(
        labelText: 'Room identifiers',
        helperText: 'One per line, such as A01 or VIP-B.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}

class _LocationCaptureException implements Exception {
  const _LocationCaptureException(this.message);

  final String message;
}

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({
    required this.title,
    required this.subtitle,
    required this.progress,
  });

  final String title;
  final String subtitle;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress),
      ],
    );
  }
}
