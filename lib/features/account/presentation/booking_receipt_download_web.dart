import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../properties/domain/property.dart';

Future<void> downloadBookingReceipt(Booking booking) async {
  final content = [
    'HAVEN LINK — BOOKING RECEIPT',
    '',
    'Booking reference: ${booking.id}',
    'Property: ${booking.property.name}',
    'Room category: ${booking.roomTypeName ?? 'Accommodation'}',
    'Assigned room: ${booking.assignedRoomNumber ?? 'Room assignment pending'}',
    'Check-in: ${_date(booking.checkIn)}',
    'Check-out: ${_date(booking.checkOut)}',
    'Guests: ${booking.guestCount}',
    'Payment status: ${booking.paymentTransactionId == null ? 'Pending' : 'Verified'}',
    'Booking status: ${booking.status.name}',
    'Amount paid: TZS ${booking.totalTzs}',
    '',
    'Property location: ${booking.property.generalLocation}',
  ].join('\n');
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = 'Haven-Link-receipt-${booking.id}.txt';
  web.document.body?.append(link);
  link.click();
  link.remove();
  web.URL.revokeObjectURL(url);
}

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';
