import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/business_config.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../payments/domain/payment_gateway.dart';
import '../../payments/domain/unlock_record.dart';
import '../../properties/domain/property.dart';

/// Shows the full payable amount and the configured payment methods, then
/// charges through `HavenLinkStore`, which only releases access once the
/// payment service confirms the transaction server-side.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({required this.property, required this.store, super.key});

  final Property property;
  final HavenLinkStore store;

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

  late final List<PaymentMethod> _methods = availablePaymentMethods();

  bool get _isBooking =>
      widget.property.businessModel == PropertyBusinessModel.bookable;

  int get _nights => _stayDates == null
      ? 1
      : DateUtils.dateOnly(_stayDates!.end)
            .difference(DateUtils.dateOnly(_stayDates!.start))
            .inDays;
  int get _subtotal => widget.property.priceTzs * _nights;
  int get _fee => widget.store.feeSettings.bookingFeeFor(_subtotal);
  int get _unlockFee => widget.store.feeSettings.unlockFeeTzs;
  int get _amount =>
      _isBooking ? _subtotal + _fee : (_unlock?.amountTzs ?? _unlockFee);
  bool get _usesPreviewMethod => _method?.isPreview ?? false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.store.customerName ?? '';
    if (_methods.isNotEmpty) _method = _methods.first;
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
        title: Text(_isBooking ? 'Review your booking' : 'Unlock this rental'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
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
                  'Payment method',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<PaymentMethod>(
                  initialValue: _method,
                  decoration: const InputDecoration(
                    labelText: 'Choose a payment method',
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
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        if (_isBooking) ...[
                          _AmountRow(
                            label: 'Property price · $_nights night(s)',
                            amount: _subtotal,
                          ),
                          const SizedBox(height: 8),
                          _AmountRow(
                            label:
                                'Haven Link service fee '
                                '(${(widget.store.feeSettings.bookingFeeRate * 100).toStringAsFixed(1)}%)',
                            amount: _fee,
                          ),
                          const Divider(height: 23),
                        ] else ...[
                          _AmountRow(
                            label: 'Location & contact unlock',
                            amount: _unlockFee,
                          ),
                          const Divider(height: 23),
                        ],
                        _AmountRow(
                          label: 'Total payable (${BusinessConfig.currencyCode})',
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
                      : const Icon(Icons.lock_outline),
                  label: Text(
                    _submitting
                        ? 'Confirming payment'
                        : 'Pay ${formatTzs(_amount)}',
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
        Text('Booking details', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Text(
          widget.property.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          widget.property.generalLocation,
          style: const TextStyle(color: HavenTheme.muted),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _selectDates,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            _stayDates == null
                ? 'Select stay dates'
                : '${_date(_stayDates!.start)} – ${_date(_stayDates!.end)}'
                    '  ·  $_nights nights',
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _nameController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Guest name'),
          validator: (value) => value == null || value.trim().length < 2
              ? 'Enter the guest name'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: const InputDecoration(
            labelText: 'Guest phone',
            hintText: '+255 7xx xxx xxx',
          ),
          validator: (value) => value == null || value.trim().length < 9
              ? 'Enter a valid phone number'
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
          'What you will unlock',
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
          'Contact-unlock fee: ${formatTzs(_unlockFee)} '
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
      setState(() => _error = 'Choose a payment method to continue.');
      return;
    }
    if (_isBooking) {
      if (_stayDates == null) {
        setState(() => _error = 'Select your check-in and check-out dates.');
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

  Widget _noProviderView() {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment unavailable')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.credit_card_off, size: 46, color: HavenTheme.muted),
                const SizedBox(height: 12),
                Text(
                  'No payment method is configured',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Haven Link has not been connected to a mobile-money or card '
                  'provider for this build, so no payment can be taken. See '
                  'docs/BACKEND_SETUP.md to configure HAVEN_PAYMENT_METHODS.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: HavenTheme.muted, height: 1.5),
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to property'),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(isBooking ? 'Booking confirmed' : 'Rental unlocked'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                isBooking ? Icons.verified_outlined : Icons.lock_open_rounded,
                size: 54,
                color: HavenTheme.teal,
              ),
              const SizedBox(height: 14),
              Text(
                isBooking
                    ? 'Your stay is confirmed'
                    : 'Location and contact unlocked',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                isBooking
                    ? 'Booking reference ${_booking!.id}'
                    : 'This property now appears in My Unlocked Properties.',
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
                        Text(
                          'Stay: ${_date(_booking!.checkIn)} – '
                          '${_date(_booking!.checkOut)}',
                        ),
                        const SizedBox(height: 8),
                        _AmountRow(
                          label: 'Property price',
                          amount: _booking!.subtotalTzs,
                        ),
                        _AmountRow(
                          label: 'Haven Link service fee',
                          amount: _booking!.feeTzs,
                        ),
                        const Divider(height: 20),
                        _AmountRow(
                          label: 'Paid (${BusinessConfig.currencyCode})',
                          amount: _booking!.totalTzs,
                          emphasize: true,
                        ),
                        if (_booking!.paymentTransactionId != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Transaction ${_booking!.paymentTransactionId}',
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
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Return to property'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
          return const Text('The contact could not be loaded. Try again.');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.scheme}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => _open(context, Uri(scheme: 'tel', path: contact.phone.replaceAll(RegExp(r'\D'), ''))),
          icon: const Icon(Icons.call, size: 18),
          label: const Text('Call owner'),
        ),
        OutlinedButton.icon(
          onPressed: () => _open(context, Uri.parse('https://wa.me/${contact.whatsApp.replaceAll(RegExp(r'\D'), '')}')),
          icon: const Icon(Icons.chat, size: 18),
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
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: HavenTheme.teal),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Preview mode: no payment provider is connected and no money '
              'will move. Access is still released only after the payment '
              'service reports a verified transaction.',
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
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UnlockRow(icon: Icons.location_on_outlined, text: 'Exact address and street'),
        _UnlockRow(icon: Icons.person_outline, text: 'Owner or authorized agent name'),
        _UnlockRow(icon: Icons.phone_outlined, text: 'Phone and WhatsApp contact'),
        _UnlockRow(icon: Icons.map_outlined, text: 'Exact map location where available'),
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

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';

// __APPEND3__
