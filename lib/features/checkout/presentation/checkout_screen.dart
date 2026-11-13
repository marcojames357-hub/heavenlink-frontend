import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/business_config.dart';
import '../../../core/config/env_config.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/booking_progress.dart';
import '../../account/presentation/booking_details_screen.dart';
import '../../account/presentation/booking_receipt_download.dart';
import '../../payments/domain/payment_gateway.dart';
import '../../payments/domain/unlock_record.dart';
import '../../properties/domain/property.dart';

/// Shows the full payable amount and the configured payment methods, then
/// charges through `HavenLinkStore`, which only releases access once the
/// payment service confirms the transaction server-side.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    required this.property,
    required this.store,
    this.initialRoomTypeId,
    this.initialDates,
    this.initialGuestCount = 1,
    super.key,
  });

  final Property property;
  final HavenLinkStore store;
  final String? initialRoomTypeId;
  final DateTimeRange? initialDates;
  final int initialGuestCount;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  DateTimeRange? _stayDates;
  PaymentMethod? _method;
  String? _error;
  Booking? _booking;
  UnlockRecord? _unlock;
  bool _submitting = false;
  bool _roomTypesLoading = false;
  List<_RoomOption> _roomOptions = const [];
  _RoomOption? _roomOption;
  int _guestCount = 1;

  late final List<PaymentMethod> _methods = availablePaymentMethods();

  bool get _isBooking =>
      widget.property.businessModel == PropertyBusinessModel.bookable;
  bool get _usesRoomCategories => const {
    PropertyCategory.hotel,
    PropertyCategory.motel,
    PropertyCategory.lodge,
  }.contains(widget.property.category);

  int get _nights => _stayDates == null
      ? 1
      : DateUtils.dateOnly(
          _stayDates!.end,
        ).difference(DateUtils.dateOnly(_stayDates!.start)).inDays;
  int get _nightlyPrice =>
      _roomOption?.nightlyPriceTzs ?? widget.property.priceTzs;
  int get _subtotal => _nightlyPrice * _nights;
  int get _fee => widget.store.feeSettings.bookingFeeFor(_subtotal);
  int get _unlockFee => widget.store.feeSettings.unlockFeeTzs;
  int get _amount =>
      _isBooking ? _subtotal + _fee : (_unlock?.amountTzs ?? _unlockFee);
  bool get _usesPreviewMethod => _method?.isPreview ?? false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.store.customerName ?? '';
    _stayDates = widget.initialDates;
    _guestCount = widget.initialGuestCount.clamp(1, 20);
    if (_methods.isNotEmpty) _method = _methods.first;
    if (_usesRoomCategories) _loadRoomOptions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_booking != null || _unlock != null) return _successView();
    if (_methods.isEmpty) return _noProviderView();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(_isBooking ? 'Review your booking' : 'Unlock this rental'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Form(
            key: _formKey,
            child: HavenCheckoutLayout(
              showProgress: _isBooking,
              children: [
                if (_usesPreviewMethod) ...[
                  const _PreviewNotice(),
                  const SizedBox(height: 16),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: _isBooking ? _bookingDetails() : _unlockDetails(),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  context.tr('Payment method'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<PaymentMethod>(
                  isExpanded: true,
                  initialValue: _method,
                  decoration: InputDecoration(
                    labelText: context.tr('Choose a payment method'),
                  ),
                  items: _methods
                      .map(
                        (method) => DropdownMenuItem(
                          value: method,
                          child: Text(method.label),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _method = value),
                ),
                const SizedBox(height: 18),
                Card(
                  key: const Key('checkout-summary'),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        if (_isBooking) ...[
                          _AmountRow(
                            label:
                                '${context.tr('Property price')} · $_nights ${context.tr('night(s)')}',
                            amount: _subtotal,
                          ),
                          const SizedBox(height: 8),
                          _AmountRow(
                            label:
                                '${context.tr('Haven Link service fee')} '
                                '(${(widget.store.feeSettings.bookingFeeRate * 100).toStringAsFixed(1)}%)',
                            amount: _fee,
                          ),
                          const Divider(height: 23),
                        ] else ...[
                          _AmountRow(
                            label: context.tr('Location & contact unlock'),
                            amount: _unlockFee,
                          ),
                          const Divider(height: 23),
                        ],
                        _AmountRow(
                          label:
                              '${context.tr('Total payable')} (${BusinessConfig.currencyCode})',
                          amount: _amount,
                          emphasize: true,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submitPayment,
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(HavenIcons.lockOutline),
                  label: Text(
                    _submitting
                        ? context.tr('Confirming payment')
                        : '${context.tr('Pay')} ${formatTzs(_amount)}',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _usesPreviewMethod
                      ? 'Preview only. No provider is connected and no money will be moved.'
                      : 'Access is released only after ${_method?.label} confirms '
                            'the payment with Haven Link.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: HavenTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bookingDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Booking details'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          widget.property.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          widget.property.generalLocation,
          style: const TextStyle(color: HavenTheme.muted),
        ),
        if (_usesRoomCategories) ...[
          const SizedBox(height: 8),
          const Text(
            'Your room will be automatically assigned from the available rooms in your selected category when your reservation is confirmed.',
            style: TextStyle(color: HavenTheme.muted),
          ),
        ],
        if (_usesRoomCategories) ...[
          const SizedBox(height: 14),
          if (_roomTypesLoading)
            const LinearProgressIndicator()
          else if (_roomOptions.isEmpty)
            const Text(
              'Room categories are not available for this property yet.',
            )
          else if (widget.initialRoomTypeId != null && _roomOption != null)
            _BookingSummaryRow(
              icon: HavenIcons.bedOutlined,
              label: _roomOption!.name,
              detail:
                  '${formatTzs(_roomOption!.nightlyPriceTzs)} / night · $_guestCount ${_guestCount == 1 ? 'guest' : 'guests'}',
            )
          else
            DropdownButtonFormField<_RoomOption>(
              isExpanded: true,
              initialValue: _roomOption,
              decoration: const InputDecoration(
                labelText: 'Choose a room category',
              ),
              items: _roomOptions
                  .map(
                    (room) => DropdownMenuItem(
                      value: room,
                      child: Text(
                        '${room.name} · ${formatTzs(room.nightlyPriceTzs)} / night',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (room) => setState(() {
                      _roomOption = room;
                      if (room != null && _guestCount > room.capacity) {
                        _guestCount = room.capacity;
                      }
                    }),
            ),
          if (_roomOption case final room?) ...[
            const SizedBox(height: 8),
            Text(
              [
                'Up to ${room.capacity} guests',
                if (room.bedType != null && room.bedType!.isNotEmpty)
                  room.bedType!,
                if (room.bathroomType != null && room.bathroomType!.isNotEmpty)
                  room.bathroomType!,
              ].join(' · '),
              style: const TextStyle(color: HavenTheme.muted),
            ),
            if (room.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 128,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: room.imageUrls.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      room.imageUrls[index],
                      width: 176,
                      height: 128,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(
                            width: 176,
                            child: Icon(HavenIcons.imageNotSupportedOutlined),
                          ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
        const SizedBox(height: 14),
        if (widget.initialDates != null)
          _BookingSummaryRow(
            icon: HavenIcons.calendarMonthOutlined,
            label: '${_date(_stayDates!.start)} – ${_date(_stayDates!.end)}',
            detail: '$_nights ${_nights == 1 ? 'night' : 'nights'}',
          )
        else
          OutlinedButton.icon(
            onPressed: _submitting ? null : _selectDates,
            icon: const Icon(HavenIcons.calendarMonthOutlined),
            label: Text(
              _stayDates == null
                  ? context.tr('Select stay dates')
                  : '${_date(_stayDates!.start)} – ${_date(_stayDates!.end)}'
                        '  ·  $_nights ${context.tr('nights')}',
            ),
          ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _nameController,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: context.tr('Guest name')),
          validator: (value) => value == null || value.trim().length < 2
              ? context.tr('Enter the guest name')
              : null,
        ),
        const SizedBox(height: 12),
        if (_usesRoomCategories &&
            _roomOption != null &&
            widget.initialDates == null) ...[
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _guestCount,
            decoration: const InputDecoration(labelText: 'Guests'),
            items: List.generate(
              _roomOption!.capacity,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text('${index + 1} ${index == 0 ? 'guest' : 'guests'}'),
              ),
            ),
            onChanged: _submitting
                ? null
                : (value) => setState(() => _guestCount = value ?? 1),
          ),
          const SizedBox(height: 12),
        ],
        if (_usesRoomCategories && widget.initialDates != null)
          _BookingSummaryRow(
            icon: HavenIcons.peopleOutline,
            label: '$_guestCount ${_guestCount == 1 ? 'Guest' : 'Guests'}',
            detail: 'Room capacity: ${_roomOption?.capacity ?? 1}',
          ),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            labelText: context.tr('Guest phone'),
            hintText: '+255 7xx xxx xxx',
          ),
          validator: (value) => value == null || value.trim().length < 9
              ? context.tr('Enter a valid phone number')
              : null,
        ),
      ],
    );
  }

  Widget _unlockDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('What you will unlock'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          widget.property.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          widget.property.generalLocation,
          style: const TextStyle(color: HavenTheme.muted),
        ),
        const SizedBox(height: 12),
        const _UnlockItems(),
        const SizedBox(height: 6),
        Text(
          '${context.tr('Contact-unlock fee')}: ${formatTzs(_unlockFee)} '
          '${BusinessConfig.currencyCode}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Future<void> _selectDates() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange:
          _stayDates ??
          DateTimeRange(
            start: today.add(const Duration(days: 1)),
            end: today.add(const Duration(days: 2)),
          ),
    );
    if (selected != null) setState(() => _stayDates = selected);
  }

  Future<void> _submitPayment() async {
    final method = _method;
    if (method == null) {
      setState(
        () => _error = context.tr('Choose a payment method to continue.'),
      );
      return;
    }
    if (_isBooking) {
      if (_stayDates == null) {
        setState(
          () =>
              _error = context.tr('Select your check-in and check-out dates.'),
        );
        return;
      }
      if (_usesRoomCategories &&
          (_roomOption == null || _roomTypesLoading || _roomOptions.isEmpty)) {
        setState(
          () => _error = 'Choose an available room category before continuing.',
        );
        return;
      }
      if (!_formKey.currentState!.validate()) return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      if (_isBooking) {
        _booking = await widget.store.purchaseBooking(
          property: widget.property,
          checkIn: _stayDates!.start,
          checkOut: _stayDates!.end,
          guestName: _nameController.text.trim(),
          method: method,
          roomTypeId: _roomOption?.id,
          roomTypeName: _roomOption?.name,
          nightlyPriceTzs: _roomOption?.nightlyPriceTzs,
          guestCount: _guestCount,
        );
      } else {
        _unlock = await widget.store.purchaseUnlock(
          property: widget.property,
          method: method,
        );
      }

      if (!mounted) return;
      setState(() => _submitting = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _submitting = false;
      });
    }
  }

  Future<void> _loadRoomOptions() async {
    setState(() => _roomTypesLoading = true);
    try {
      final response = await http
          .get(
            EnvConfig.endpoint(
              '/api/v1/properties/${Uri.encodeComponent(widget.property.id)}/stay-info',
            ),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          decoded is! Map<String, dynamic> ||
          decoded['roomTypes'] is! List<dynamic>) {
        throw StateError('Room categories could not be loaded.');
      }
      final options = (decoded['roomTypes'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(_RoomOption.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _roomOptions = options;
        if (widget.initialRoomTypeId != null) {
          final selected = options
              .where((room) => room.id == widget.initialRoomTypeId)
              .toList(growable: false);
          _roomOption = selected.isEmpty ? null : selected.first;
          if (_roomOption == null) {
            _error = 'The selected room category is no longer available.';
          }
        } else {
          _roomOption = options.isEmpty ? null : options.first;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _roomTypesLoading = false);
    }
  }

  Widget _noProviderView() {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Payment unavailable'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  HavenIcons.creditCardOff,
                  size: 46,
                  color: HavenTheme.muted,
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('No payment method is configured'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Haven Link has not been connected to a mobile-money or card provider for this build, so no payment can be taken. See docs/BACKEND_SETUP.md to configure HAVEN_PAYMENT_METHODS.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: HavenTheme.muted, height: 1.5),
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.tr('Back to property')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _successView() {
    final isBooking = _booking != null;
    final booking = _booking;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(isBooking ? 'Booking confirmed' : 'Rental unlocked'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                isBooking
                    ? HavenIcons.verifiedOutlined
                    : HavenIcons.lockOpenRounded,
                size: 66,
                color: HavenTheme.forest,
              ),
              const SizedBox(height: 14),
              Text(
                isBooking
                    ? context.tr('Booking Confirmed!')
                    : context.tr('Location and contact unlocked'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                isBooking
                    ? '${context.tr('Booking reference')} ${_booking!.id}'
                    : context.tr(
                        'This property now appears in My Unlocked Properties.',
                      ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.property.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      if (isBooking) ...[
                        if (_booking!.roomTypeName != null)
                          Text('Room category: ${_booking!.roomTypeName}'),
                        if (_booking!.assignedRoomNumber != null)
                          Text('Assigned room: ${_booking!.assignedRoomNumber}')
                        else if (_booking!.roomTypeName != null)
                          const Text('Room assignment pending.'),
                        if (_booking!.roomTypeName != null)
                          const SizedBox(height: 8),
                        Text(
                          '${context.tr('Stay')}: ${_date(_booking!.checkIn)} – '
                          '${_date(_booking!.checkOut)}',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_booking!.guestCount} ${_booking!.guestCount == 1 ? 'guest' : 'guests'}',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Booking status: ${_booking!.status == BookingStatus.active ? 'Confirmed' : _booking!.status.name}',
                        ),
                        Text(
                          'Payment status: ${_booking!.paymentTransactionId == null ? 'Pending' : 'Verified'}',
                        ),
                        const SizedBox(height: 8),
                        _AmountRow(
                          label: context.tr('Property price'),
                          amount: _booking!.subtotalTzs,
                        ),
                        _AmountRow(
                          label: context.tr('Haven Link service fee'),
                          amount: _booking!.feeTzs,
                        ),
                        const Divider(height: 20),
                        _AmountRow(
                          label:
                              '${context.tr('Paid')} (${BusinessConfig.currencyCode})',
                          amount: _booking!.totalTzs,
                          emphasize: true,
                        ),
                        if (_booking!.paymentTransactionId != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${context.tr('Transaction')} ${_booking!.paymentTransactionId}',
                            style: const TextStyle(
                              color: HavenTheme.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ] else
                        _UnlockedContact(
                          store: widget.store,
                          propertyId: widget.property.id,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (booking != null) ...[
                FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (context) => BookingDetailsScreen(
                        booking: booking,
                        store: widget.store,
                      ),
                    ),
                  ),
                  child: const Text('View Booking'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await downloadBookingReceipt(booking);
                    } catch (error) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  },
                  icon: const Icon(HavenIcons.downloadOutlined),
                  label: const Text('Download Receipt'),
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(HavenIcons.arrowBack),
                  label: Text(context.tr('Return to property')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomOption {
  const _RoomOption({
    required this.id,
    required this.name,
    required this.nightlyPriceTzs,
    required this.capacity,
    this.bedType,
    this.bathroomType,
    this.imageUrls = const [],
  });

  final String id;
  final String name;
  final int nightlyPriceTzs;
  final int capacity;
  final String? bedType;
  final String? bathroomType;
  final List<String> imageUrls;

  factory _RoomOption.fromJson(Map<String, dynamic> json) => _RoomOption(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Room',
    nightlyPriceTzs: (json['nightlyPriceTzs'] as num?)?.toInt() ?? 0,
    capacity: (json['capacity'] as num?)?.toInt() ?? 1,
    bedType: json['bedType'] as String?,
    bathroomType: json['bathroomType'] as String?,
    imageUrls: (json['imageUrls'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false),
  );
}

class _UnlockedContact extends StatelessWidget {
  const _UnlockedContact({required this.store, required this.propertyId});

  final HavenLinkStore store;
  final String propertyId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OwnerContact?>(
      future: store.contactFor(propertyId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final contact = snapshot.data;
        if (contact == null) {
          return Text(
            context.tr('The contact could not be loaded. Try again.'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(contact.exactAddress),
            const SizedBox(height: 8),
            Text('${contact.contactName} · ${contact.role}'),
            const SizedBox(height: 10),
            ContactActions(contact: contact),
          ],
        );
      },
    );
  }
}

/// Dials or messages an unlocked contact using the device's own apps.
class ContactActions extends StatelessWidget {
  const ContactActions({required this.contact, super.key});

  final OwnerContact contact;

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open ${uri.scheme}.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => _open(
            context,
            Uri(
              scheme: 'tel',
              path: contact.phone.replaceAll(RegExp(r'\D'), ''),
            ),
          ),
          icon: const Icon(HavenIcons.call, size: 18),
          label: Text(context.tr('Call owner')),
        ),
        OutlinedButton.icon(
          onPressed: () => _open(
            context,
            Uri.parse(
              'https://wa.me/${contact.whatsApp.replaceAll(RegExp(r'\D'), '')}',
            ),
          ),
          icon: const Icon(HavenIcons.chat, size: 18),
          label: const Text('WhatsApp'),
        ),
      ],
    );
  }
}

class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: HavenTheme.lightMint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HavenTheme.mint),
      ),
      child: Row(
        children: [
          Icon(HavenIcons.infoOutline, color: HavenTheme.teal),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(
                'Preview mode: no payment provider is connected and no money will move. Access is still released only after the payment service reports a verified transaction.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockItems extends StatelessWidget {
  const _UnlockItems();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UnlockRow(
          icon: HavenIcons.locationOnOutlined,
          text: context.tr('Exact address and street'),
        ),
        _UnlockRow(
          icon: HavenIcons.personOutline,
          text: context.tr('Owner or authorized agent name'),
        ),
        _UnlockRow(
          icon: HavenIcons.phoneOutlined,
          text: context.tr('Phone and WhatsApp contact'),
        ),
        _UnlockRow(
          icon: HavenIcons.mapOutlined,
          text: context.tr('Exact map location where available'),
        ),
      ],
    );
  }
}

class _UnlockRow extends StatelessWidget {
  const _UnlockRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: HavenTheme.teal),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  final String label;
  final int amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            formatTzs(amount),
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingSummaryRow extends StatelessWidget {
  const _BookingSummaryRow({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, size: 19, color: HavenTheme.forest),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                detail,
                style: const TextStyle(color: HavenTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';

// __APPEND3__
