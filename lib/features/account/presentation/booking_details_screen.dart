import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/config/env_config.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/widgets/property_photo.dart';
import 'booking_receipt_download.dart';
import 'booking_receipt_sheet.dart';

class BookingDetailsScreen extends StatelessWidget {
  const BookingDetailsScreen({
    required this.booking,
    required this.store,
    super.key,
  });

  final Booking booking;
  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    final nights = booking.checkOut.difference(booking.checkIn).inDays;
    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: PropertyPhoto(
                  imageUrl: booking.property.imageUrl,
                  height: 220,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                booking.property.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${booking.property.generalLocation} · ${booking.roomTypeName ?? 'Stay'}',
                style: const TextStyle(color: HavenTheme.muted),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BookingFact(
                        icon: HavenIcons.confirmationNumberOutlined,
                        label: 'Booking reference',
                        value: booking.id,
                      ),
                      _BookingFact(
                        icon: HavenIcons.meetingRoomOutlined,
                        label: 'Room',
                        value: booking.assignedRoomNumber == null
                            ? 'Room assignment pending'
                            : '${booking.roomTypeName ?? 'Room'} · ${booking.assignedRoomNumber}',
                      ),
                      _BookingFact(
                        icon: HavenIcons.calendarMonthOutlined,
                        label: 'Stay dates',
                        value:
                            '${_date(booking.checkIn)} – ${_date(booking.checkOut)} ($nights ${nights == 1 ? 'night' : 'nights'})',
                      ),
                      _BookingFact(
                        icon: HavenIcons.peopleOutline,
                        label: 'Guests',
                        value:
                            '${booking.guestCount} ${booking.guestCount == 1 ? 'guest' : 'guests'}',
                      ),
                      _BookingFact(
                        icon: HavenIcons.paymentsOutlined,
                        label: 'Amount paid',
                        value: formatTzs(booking.totalTzs),
                      ),
                      _BookingFact(
                        icon: HavenIcons.verifiedOutlined,
                        label: 'Payment status',
                        value: booking.paymentTransactionId == null
                            ? 'Payment pending'
                            : 'Payment verified',
                      ),
                      _BookingFact(
                        icon: HavenIcons.eventAvailableOutlined,
                        label: 'Booking status',
                        value: _statusLabel(booking.status),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (booking.status == BookingStatus.active ||
                  booking.status == BookingStatus.completed) ...[
                FilledButton.icon(
                  onPressed: () => _contactProperty(context),
                  icon: const Icon(HavenIcons.chatBubbleOutline),
                  label: const Text('Contact Property'),
                ),
              ] else
                const Text(
                  'Messaging with the property opens once your booking is confirmed.',
                  style: TextStyle(color: HavenTheme.muted, fontSize: 12),
                ),
              const SizedBox(height: 8),
              if (EnvConfig.backendConfigured &&
                  booking.paymentTransactionId != null) ...[
                OutlinedButton.icon(
                  onPressed: () => showBookingReceipt(
                    context,
                    bookingId: booking.id,
                    tokenProvider: () =>
                        store.authenticationRepository.accessToken,
                  ),
                  icon: const Icon(HavenIcons.receiptLongOutlined),
                  label: const Text('View Receipt'),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: () => _downloadReceipt(context),
                icon: const Icon(HavenIcons.downloadOutlined),
                label: const Text('Download Receipt'),
              ),
              if (booking.status == BookingStatus.active ||
                  booking.status == BookingStatus.pending) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _cancelBooking(context),
                  child: const Text('Cancel booking'),
                ),
                const Text(
                  'Cancellation and any refund follow the property’s stated policy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: HavenTheme.muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadReceipt(BuildContext context) async {
    try {
      await downloadBookingReceipt(booking);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _contactProperty(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _BookingMessagesSheet(store: store, booking: booking),
  );

  Future<void> _cancelBooking(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text(
          'The property cancellation policy applies. The room will be released when Haven Link confirms the cancellation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await store.cancelCustomerBooking(booking);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking cancelled.')));
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _BookingMessagesSheet extends StatefulWidget {
  const _BookingMessagesSheet({required this.store, required this.booking});

  final HavenLinkStore store;
  final Booking booking;

  @override
  State<_BookingMessagesSheet> createState() => _BookingMessagesSheetState();
}

class _BookingMessagesSheetState extends State<_BookingMessagesSheet> {
  final _messageController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _messages;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages = widget.store.loadBookingMessages(widget.booking.id);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      await widget.store.sendBookingMessage(
        bookingId: widget.booking.id,
        body: message,
      );
      _messageController.clear();
      _messages = widget.store.loadBookingMessages(widget.booking.id);
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        8,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Message ${widget.booking.property.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _messages,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Messages could not be loaded: ${snapshot.error}',
                    ),
                  );
                }
                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Start a conversation with the property.'),
                  );
                }
                return ListView(
                  children: [
                    for (final item in messages)
                      ListTile(
                        title: Text(item['body'] as String? ?? ''),
                        subtitle: Text(item['senderRole'] as String? ?? ''),
                      ),
                  ],
                );
              },
            ),
          ),
          TextField(
            controller: _messageController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Your message',
              suffixIcon: IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(HavenIcons.send),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}

class _BookingFact extends StatelessWidget {
  const _BookingFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: HavenTheme.forest),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: HavenTheme.muted)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    ),
  );
}

String _statusLabel(BookingStatus status) => switch (status) {
  BookingStatus.active => 'Confirmed',
  BookingStatus.pending => 'Pending',
  BookingStatus.completed => 'Completed',
  BookingStatus.cancelled => 'Cancelled',
};

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';
