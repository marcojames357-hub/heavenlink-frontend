import 'package:flutter/material.dart';

import '../../../core/state/haven_link_store.dart';
import '../../properties/domain/property.dart';

Future<void> showListingEditorDialog({
  required BuildContext context,
  required HavenLinkStore store,
  required PropertyBusinessModel businessModel,
  Property? initial,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ListingEditorDialog(
      store: store,
      businessModel: businessModel,
      initial: initial,
    ),
  );
}

class _ListingEditorDialog extends StatefulWidget {
  const _ListingEditorDialog({
    required this.store,
    required this.businessModel,
    this.initial,
  });

  final HavenLinkStore store;
  final PropertyBusinessModel businessModel;
  final Property? initial;

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
  late final _bedrooms = TextEditingController(
    text: widget.initial?.bedrooms.toString() ?? '1',
  );
  late final _bathrooms = TextEditingController(
    text: widget.initial?.bathrooms.toString() ?? '1',
  );
  late PropertyCategory _category =
      widget.initial?.category ??
      (widget.businessModel == PropertyBusinessModel.contactUnlock
          ? PropertyCategory.house
          : PropertyCategory.hotel);
  late String _rentalPeriod = widget.initial?.rentalPeriod ?? 'month';
  late bool _available = widget.initial?.available ?? true;
  bool _saving = false;

  List<PropertyCategory> get _categories =>
      widget.businessModel == PropertyBusinessModel.contactUnlock
      ? const [
          PropertyCategory.house,
          PropertyCategory.room,
          PropertyCategory.sharedAccommodation,
        ]
      : const [
          PropertyCategory.hotel,
          PropertyCategory.lodge,
          PropertyCategory.servicedApartment,
          PropertyCategory.shortStayApartment,
        ];

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _neighborhood.dispose();
    _price.dispose();
    _imageUrl.dispose();
    _moreImages.dispose();
    _description.dispose();
    _amenities.dispose();
    _bedrooms.dispose();
    _bathrooms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRental =
        widget.businessModel == PropertyBusinessModel.contactUnlock;
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
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Listing title'),
                  validator: (value) => _required(value, 3, 'Enter a title.'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PropertyCategory>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Property type'),
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
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amenities,
                  decoration: const InputDecoration(
                    labelText: 'Amenities',
                    helperText: 'Separate amenities with commas.',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Description'),
                  validator: (value) =>
                      _required(value, 10, 'Add more detail.'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available'),
                  value: _available,
                  onChanged: (value) => setState(() => _available = value),
                ),
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
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving' : 'Save listing'),
        ),
      ],
    );
  }

  String? _required(String? value, int minLength, String message) =>
      value == null || value.trim().length < minLength ? message : null;

  String? _wholeNumber(String? value) =>
      int.tryParse(value ?? '') == null || int.parse(value!) < 0
      ? 'Enter a whole number.'
      : null;

  String _categoryLabel(PropertyCategory value) => switch (value) {
    PropertyCategory.hotel => 'Hotel',
    PropertyCategory.lodge => 'Lodge',
    PropertyCategory.servicedApartment => 'Serviced apartment',
    PropertyCategory.shortStayApartment => 'Short-stay apartment',
    PropertyCategory.house => 'House',
    PropertyCategory.room => 'Room',
    PropertyCategory.sharedAccommodation => 'Shared accommodation',
  };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final old = widget.initial;
    final user = widget.store.currentUser;
    final property = Property(
      id: old?.id ?? 'new-${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text.trim(),
      city: _city.text.trim(),
      neighborhood: _neighborhood.text.trim(),
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
      amenities: _amenities.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      description: _description.text.trim(),
      available: _available,
      furnished: old?.furnished ?? false,
      parking: old?.parking ?? false,
      water: old?.water ?? false,
      electricity: old?.electricity ?? false,
      security: old?.security ?? false,
      propertyVerification:
          old?.propertyVerification ?? VerificationStatus.unverified,
      ownerVerification:
          old?.ownerVerification ?? VerificationStatus.unverified,
      managerName: old?.managerName ?? user?.fullName ?? 'Property manager',
      listingStatus: old?.listingStatus ?? ListingStatus.pendingReview,
      agentId: old?.agentId ?? user?.id ?? '',
      rentalPeriod: widget.businessModel == PropertyBusinessModel.contactUnlock
          ? _rentalPeriod
          : 'day',
      reportedCount: old?.reportedCount ?? 0,
    );

    try {
      await widget.store.saveListing(property);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
