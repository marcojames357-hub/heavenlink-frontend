const {
  Booking, Property, User, RoomType, Room, PaymentTransaction, BookingReceipt
} = require('../models');
const { isVerifiedBookingPayment } = require('./bookingPayment');
const { notify } = require('./notify');

const bookingReference = (booking) => `HL-${booking.id.slice(0, 8).toUpperCase()}`;
const dateOnly = (value) => new Date(value).toISOString().slice(0, 10);

async function buildSnapshot(booking, payment, receiptNumber) {
  const property = await Property.findByPk(booking.propertyId);
  const customer = await User.findByPk(booking.customerId, { attributes: ['fullName', 'email'] });
  const roomType = booking.roomTypeId ? await RoomType.findByPk(booking.roomTypeId) : null;
  const nights = Math.max(1, booking.calculateNights());
  return {
    brand: 'Haven Link',
    receiptNumber,
    bookingReference: bookingReference(booking),
    transactionReference: payment.reference,
    customer: { name: booking.guestName, accountName: customer?.fullName, email: customer?.email },
    property: { id: property.id, name: property.name, city: property.city, neighborhood: property.neighborhood },
    accommodation: roomType ? roomType.name : 'Entire apartment',
    checkIn: dateOnly(booking.checkIn),
    checkOut: dateOnly(booking.checkOut),
    nights,
    guests: booking.guestCount,
    charges: {
      subtotalTzs: booking.subtotalTzs,
      feesTzs: booking.feeTzs,
      totalTzs: booking.totalTzs
    },
    totalPaidTzs: payment.amountTzs,
    currency: payment.currency,
    paymentMethod: payment.methodId,
    paymentVerifiedAt: payment.verifiedAt,
    notice: 'Haven Link platform payment receipt. This is not an official statutory fiscal receipt.'
  };
}

// Idempotent: safe to call from repeated payment verifications or callbacks.
async function onBookingConfirmed(bookingId) {
  const booking = await Booking.findByPk(bookingId);
  if (!booking || booking.status !== 'confirmed') return null;
  const payment = await PaymentTransaction.findByPk(booking.paymentTransactionId);
  if (!isVerifiedBookingPayment(booking, payment)) return null;

  let receipt = await BookingReceipt.findOne({ where: { bookingId: booking.id } });
  if (!receipt) {
    const receiptNumber = `HLR-${dateOnly(payment.verifiedAt).replace(/-/g, '')}-${booking.id.slice(0, 8).toUpperCase()}`;
    try {
      receipt = await BookingReceipt.create({
        receiptNumber, bookingId: booking.id, paymentTransactionId: payment.id,
        customerId: booking.customerId, snapshot: await buildSnapshot(booking, payment, receiptNumber),
        issuedAt: new Date()
      });
    } catch (error) {
      if (error.name !== 'SequelizeUniqueConstraintError') throw error;
      receipt = await BookingReceipt.findOne({ where: { bookingId: booking.id } });
    }
  }

  const property = await Property.findByPk(booking.propertyId, { attributes: ['id', 'name', 'agentId'] });
  const reference = bookingReference(booking);
  const dates = `${dateOnly(booking.checkIn)} to ${dateOnly(booking.checkOut)}`;
  await notify(booking.customerId, 'CUSTOMER', 'Booking confirmed',
    `Your stay at ${property.name} (${dates}) is confirmed. Booking reference ${reference}. Your receipt ${receipt.receiptNumber} is available in My Bookings.`,
    `/bookings/${booking.id}`, 'View booking', {
      type: 'BOOKING_CONFIRMED', category: 'booking', propertyId: property.id, bookingId: booking.id,
      dedupeKey: `booking-confirmed:${booking.id}`
    });
  await notify(booking.customerId, 'CUSTOMER', 'Payment received',
    `Payment for booking ${reference} was verified. Receipt ${receipt.receiptNumber} is ready.`,
    `/bookings/${booking.id}/receipt`, 'View receipt', {
      type: 'PAYMENT_RECEIVED', category: 'payment', propertyId: property.id, bookingId: booking.id,
      dedupeKey: `payment-received:${booking.id}`, sms: false
    });
  await notify(property.agentId, 'STAY_AGENT', 'New confirmed booking',
    `${property.name}: booking ${reference} for ${dates} is confirmed and payment is verified.`,
    `/agent/reservations/${booking.id}`, 'Open reservation', {
      type: 'BOOKING_CONFIRMED_AGENT', category: 'booking', propertyId: property.id, bookingId: booking.id,
      dedupeKey: `booking-confirmed-agent:${booking.id}`, priority: 'high'
    });
  return receipt;
}

module.exports = { onBookingConfirmed, bookingReference };
