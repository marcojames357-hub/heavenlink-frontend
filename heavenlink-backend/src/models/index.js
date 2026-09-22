const sequelize = require('../config/database');
const User = require('./User');
const Property = require('./Property');
const OwnerContact = require('./OwnerContact');
const UnlockRecord = require('./UnlockRecord');
const PaymentTransaction = require('./PaymentTransaction');
const Booking = require('./Booking');
const OtpChallenge = require('./OtpChallenge');
const RoomType = require('./RoomType');
const RoomInventory = require('./RoomInventory');
const CheckInPolicy = require('./CheckInPolicy');
const GuestMessage = require('./GuestMessage');
const Notification = require('./Notification');
const BusinessConfiguration = require('./BusinessConfiguration');
const SavedProperty = require('./SavedProperty');
const AdminAuditEvent = require('./AdminAuditEvent');

// Define relationships
User.hasMany(Property, { foreignKey: 'agentId', as: 'listings' });
Property.belongsTo(User, { foreignKey: 'agentId', as: 'agent' });

User.hasMany(SavedProperty, { foreignKey: 'customerId', as: 'savedProperties' });
SavedProperty.belongsTo(User, { foreignKey: 'customerId', as: 'customer' });
Property.hasMany(SavedProperty, { foreignKey: 'listingId', as: 'savedBy' });
SavedProperty.belongsTo(Property, { foreignKey: 'listingId', as: 'property' });
User.hasMany(AdminAuditEvent, { foreignKey: 'actorId', as: 'auditEvents' });
AdminAuditEvent.belongsTo(User, { foreignKey: 'actorId', as: 'actor' });

Property.hasOne(OwnerContact, { foreignKey: 'propertyId', as: 'contact' });
OwnerContact.belongsTo(Property, { foreignKey: 'propertyId' });

User.hasMany(UnlockRecord, { foreignKey: 'customerId', as: 'unlocks' });
UnlockRecord.belongsTo(User, { foreignKey: 'customerId', as: 'customer' });

Property.hasMany(UnlockRecord, { foreignKey: 'listingId', as: 'unlocks' });
UnlockRecord.belongsTo(Property, { foreignKey: 'listingId', as: 'property' });

PaymentTransaction.hasOne(UnlockRecord, { foreignKey: 'paymentTransactionId', as: 'unlock' });
UnlockRecord.belongsTo(PaymentTransaction, { foreignKey: 'paymentTransactionId', as: 'transaction' });

User.hasMany(PaymentTransaction, { foreignKey: 'customerId', as: 'transactions' });
PaymentTransaction.belongsTo(User, { foreignKey: 'customerId', as: 'customer' });

Property.hasMany(PaymentTransaction, { foreignKey: 'listingId', as: 'transactions' });
PaymentTransaction.belongsTo(Property, { foreignKey: 'listingId', as: 'property' });

Property.hasMany(Booking, { foreignKey: 'propertyId', as: 'bookings' });
Booking.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });

User.hasMany(Booking, { foreignKey: 'customerId', as: 'bookings' });
Booking.belongsTo(User, { foreignKey: 'customerId', as: 'customer' });

PaymentTransaction.hasMany(Booking, { foreignKey: 'paymentTransactionId', as: 'bookings' });
Booking.belongsTo(PaymentTransaction, { foreignKey: 'paymentTransactionId', as: 'transaction' });

Property.hasMany(RoomType, { foreignKey: 'listingId', as: 'roomTypes' });
RoomType.belongsTo(Property, { foreignKey: 'listingId', as: 'property' });

RoomType.hasMany(RoomInventory, { foreignKey: 'roomTypeId', as: 'inventory' });
RoomInventory.belongsTo(RoomType, { foreignKey: 'roomTypeId', as: 'roomType' });

Property.hasOne(CheckInPolicy, { foreignKey: 'listingId', as: 'checkInPolicy' });
CheckInPolicy.belongsTo(Property, { foreignKey: 'listingId', as: 'property' });

Booking.hasMany(GuestMessage, { foreignKey: 'bookingId', as: 'messages' });
GuestMessage.belongsTo(Booking, { foreignKey: 'bookingId', as: 'booking' });

User.hasMany(GuestMessage, { foreignKey: 'senderId', as: 'sentMessages' });
GuestMessage.belongsTo(User, { foreignKey: 'senderId', as: 'sender' });

User.hasMany(Notification, { foreignKey: 'userId', as: 'notifications' });
Notification.belongsTo(User, { foreignKey: 'userId', as: 'user' });

const syncDatabase = async () => {
  await sequelize.authenticate();
  await sequelize.query('PRAGMA foreign_keys = ON');
  await sequelize.sync({ alter: process.env.NODE_ENV !== 'production' });
};

module.exports = {
  sequelize,
  syncDatabase,
  User,
  Property,
  OwnerContact,
  UnlockRecord,
  PaymentTransaction,
  Booking,
  OtpChallenge,
  RoomType,
  RoomInventory,
  CheckInPolicy,
  GuestMessage,
  Notification,
  BusinessConfiguration,
  SavedProperty,
  AdminAuditEvent
};
