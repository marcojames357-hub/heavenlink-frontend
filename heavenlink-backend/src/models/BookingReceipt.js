const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

// Immutable platform receipt issued only after a verified successful payment.
const BookingReceipt = sequelize.define('BookingReceipt', {
  id: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  receiptNumber: { type: DataTypes.STRING(40), allowNull: false, unique: true },
  bookingId: {
    type: DataTypes.UUID, allowNull: false, unique: true,
    references: { model: 'Bookings', key: 'id' }
  },
  paymentTransactionId: {
    type: DataTypes.UUID, allowNull: false, unique: true,
    references: { model: 'PaymentTransactions', key: 'id' }
  },
  customerId: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  snapshot: { type: DataTypes.JSON, allowNull: false },
  issuedAt: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW }
});

module.exports = BookingReceipt;
