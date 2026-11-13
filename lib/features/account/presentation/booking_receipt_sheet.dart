import 'package:flutter/material.dart';

import '../../../core/data/api_client.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/theme/app_theme.dart';

/// Loads the server-issued receipt for a booking and shows it in a sheet.
Future<void> showBookingReceipt(
  BuildContext context, {
  required String bookingId,
  required String? Function() tokenProvider,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  Map<String, dynamic> receipt;
  try {
    final result = await ApiClient(
      tokenProvider: tokenProvider,
    ).get('/api/v1/bookings/$bookingId/receipt');
    receipt = (result['receipt'] as Map<String, dynamic>?) ?? const {};
  } on StateError catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReceiptSheet(receipt: receipt),
  );
}

class _ReceiptSheet extends StatelessWidget {
  const _ReceiptSheet({required this.receipt});

  final Map<String, dynamic> receipt;

  Map<String, dynamic> _map(String key) =>
      (receipt[key] as Map<String, dynamic>?) ?? const {};

  @override
  Widget build(BuildContext context) {
    final property = _map('property');
    final charges = _map('charges');
    final customer = _map('customer');
    Widget row(String label, Object? value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: HavenTheme.muted)),
          Flexible(
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    String money(Object? v) => formatTzs((v as num?) ?? 0);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Receipt ${receipt['receiptNumber'] ?? ''}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            row('Booking reference', receipt['bookingReference']),
            row('Transaction', receipt['transactionReference']),
            row('Guest', customer['name']),
            row('Property', property['name']),
            row('Accommodation', receipt['accommodation']),
            row('Check-in', receipt['checkIn']),
            row('Check-out', receipt['checkOut']),
            row('Guests', receipt['guests']),
            const Divider(height: 24),
            row('Subtotal', money(charges['subtotalTzs'])),
            row('Fees', money(charges['feesTzs'])),
            row('Total paid', money(receipt['totalPaidTzs']), bold: true),
            row('Payment method', receipt['paymentMethod']),
            const SizedBox(height: 12),
            Text(
              '${receipt['notice'] ?? ''}',
              style: const TextStyle(color: HavenTheme.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
