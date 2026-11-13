const { PaymentTransaction } = require('../models');

const getBookingPayment = (booking, transaction) => booking.paymentTransactionId
  ? PaymentTransaction.findByPk(booking.paymentTransactionId, { transaction })
  : null;

const matchesBookingPayment = (booking, payment) => Boolean(
  payment &&
  payment.id === booking.paymentTransactionId &&
  payment.purpose === 'accommodationBooking' &&
  payment.bookingId === booking.id &&
  payment.customerId === booking.customerId &&
  payment.amountTzs === booking.totalTzs
);

const isVerifiedBookingPayment = (booking, payment, statuses = ['succeeded']) =>
  matchesBookingPayment(booking, payment) &&
  Boolean(payment.verifiedAt) &&
  statuses.includes(payment.status);

module.exports = { getBookingPayment, matchesBookingPayment, isVerifiedBookingPayment };
