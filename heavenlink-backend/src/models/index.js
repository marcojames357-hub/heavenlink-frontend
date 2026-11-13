const { DataTypes } = require('sequelize');
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
const Floor = require('./Floor');
const Room = require('./Room');
const RoomAvailabilityBlock = require('./RoomAvailabilityBlock');
const ApartmentAvailabilityBlock = require('./ApartmentAvailabilityBlock');
const WalkInReservation = require('./WalkInReservation');
const WalkInRoomSegment = require('./WalkInRoomSegment');
const CheckInPolicy = require('./CheckInPolicy');
const GuestMessage = require('./GuestMessage');
const RentalMessage = require('./RentalMessage');
const Notification = require('./Notification');
const BusinessConfiguration = require('./BusinessConfiguration');
const SavedProperty = require('./SavedProperty');
const AdminAuditEvent = require('./AdminAuditEvent');
const Review = require('./Review');
const ReviewReport = require('./ReviewReport');
const AgentProfile = require('./AgentProfile');
const ProblemReport = require('./ProblemReport');
const ProblemReportNote = require('./ProblemReportNote');
const RentObligation = require('./RentObligation');
const RentReceipt = require('./RentReceipt');
const PropertyExpense = require('./PropertyExpense');
const UtilityBill = require('./UtilityBill');
const StaffObligation = require('./StaffObligation');
const FinancialAlert = require('./FinancialAlert');
const FinancialPayment = require('./FinancialPayment');
const AgentWorkspace = require('./AgentWorkspace');
const NotificationPreference = require('./NotificationPreference');
const BookingReceipt = require('./BookingReceipt');

const ensurePropertyLocationColumns = async () => {
  const queryInterface = sequelize.getQueryInterface();
  const columns = await queryInterface.describeTable('Properties');
  const locationColumns = {
    latitude: { type: DataTypes.FLOAT, allowNull: true },
    longitude: { type: DataTypes.FLOAT, allowNull: true },
    formattedAddress: { type: DataTypes.STRING(500), allowNull: true },
    locationVerification: {
      type: DataTypes.ENUM('unverified', 'pending', 'verified'),
      allowNull: false,
      defaultValue: 'unverified'
    },
    locationVisibility: {
      type: DataTypes.ENUM('exact', 'approximate', 'hidden'),
      allowNull: false,
      defaultValue: 'approximate'
    }
  };
  locationColumns.maxGuests = { type: DataTypes.INTEGER, allowNull: true };
  locationColumns.stayRules = { type: DataTypes.JSON, allowNull: true };

  for (const [name, definition] of Object.entries(locationColumns)) {
    if (!columns[name]) await queryInterface.addColumn('Properties', name, definition);
  }
};

const ensureRoomInventoryDateUniqueness = async () => {
  const queryInterface = sequelize.getQueryInterface();
  const indexes = await queryInterface.showIndex('RoomInventories');
  const hasLegacyRoomTypeConstraint = indexes.some(
    (index) =>
      index.unique &&
      !index.primary &&
      index.fields.length === 1 &&
      index.fields[0].attribute === 'roomTypeId'
  );
  if (!hasLegacyRoomTypeConstraint) return;

  const [duplicates] = await sequelize.query(`
    SELECT roomTypeId, date, COUNT(*) AS count
    FROM RoomInventories
    GROUP BY roomTypeId, date
    HAVING COUNT(*) > 1
  `);
  if (duplicates.length > 0) {
    throw new Error(
      'Cannot migrate room inventory because duplicate room-type dates exist.'
    );
  }

  await sequelize.transaction(async (transaction) => {
    await sequelize.query(`
      CREATE TABLE RoomInventories_rebuilt (
        id UUID PRIMARY KEY,
        roomTypeId UUID NOT NULL REFERENCES RoomTypes(id),
        date DATE NOT NULL,
        booked INTEGER DEFAULT '0',
        totalOverride INTEGER,
        createdAt DATETIME NOT NULL,
        updatedAt DATETIME NOT NULL
      )
    `, { transaction });
    await sequelize.query(`
      INSERT INTO RoomInventories_rebuilt
        (id, roomTypeId, date, booked, totalOverride, createdAt, updatedAt)
      SELECT id, roomTypeId, date, booked, totalOverride, createdAt, updatedAt
      FROM RoomInventories
    `, { transaction });
    await sequelize.query('DROP TABLE RoomInventories', { transaction });
    await sequelize.query(
      'ALTER TABLE RoomInventories_rebuilt RENAME TO RoomInventories',
      { transaction }
    );
    await sequelize.query(`
      CREATE UNIQUE INDEX room_inventories_room_type_id_date
      ON RoomInventories (roomTypeId, date)
    `, { transaction });
    await sequelize.query(`
      CREATE INDEX room_inventories_date ON RoomInventories (date)
    `, { transaction });
  });
};

// Define relationships
User.hasMany(Property, { foreignKey: 'agentId', as: 'listings' });
Property.belongsTo(User, { foreignKey: 'agentId', as: 'agent' });
RentObligation.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
RentObligation.hasMany(RentReceipt, { foreignKey: 'obligationId', as: 'receipts' });
RentReceipt.belongsTo(RentObligation, { foreignKey: 'obligationId', as: 'obligation' });
Property.hasMany(PropertyExpense, { foreignKey: 'propertyId', as: 'expenses' });
PropertyExpense.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
Property.hasMany(UtilityBill, { foreignKey: 'propertyId', as: 'utilityBills' });
UtilityBill.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
Property.hasMany(StaffObligation, { foreignKey: 'propertyId', as: 'staffObligations' });
StaffObligation.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
Property.hasMany(FinancialAlert, { foreignKey: 'propertyId', as: 'financialAlerts' });
FinancialAlert.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
User.hasMany(FinancialAlert, { foreignKey: 'ownerId', as: 'financialAlerts' });
FinancialAlert.belongsTo(User, { foreignKey: 'ownerId', as: 'owner' });
Property.hasMany(FinancialPayment, { foreignKey: 'propertyId', as: 'financialPayments' });
FinancialPayment.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
User.hasOne(AgentProfile, { foreignKey: 'userId', as: 'agentProfile' });
AgentProfile.belongsTo(User, { foreignKey: 'userId', as: 'user' });

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

Property.hasMany(Review, { foreignKey: 'propertyId', as: 'reviews' });
Review.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
Booking.hasOne(Review, { foreignKey: 'bookingId', as: 'review' });
Review.belongsTo(Booking, { foreignKey: 'bookingId', as: 'booking' });
User.hasMany(Review, { foreignKey: 'reviewerId', as: 'reviews' });
Review.belongsTo(User, { foreignKey: 'reviewerId', as: 'reviewer' });
Review.hasMany(ReviewReport, { foreignKey: 'reviewId', as: 'reportRecords' });
ReviewReport.belongsTo(Review, { foreignKey: 'reviewId', as: 'review' });
User.hasMany(ReviewReport, { foreignKey: 'reporterId', as: 'reviewReports' });
ReviewReport.belongsTo(User, { foreignKey: 'reporterId', as: 'reporter' });

ProblemReport.belongsTo(Booking, { foreignKey: 'bookingId', as: 'booking' });
ProblemReport.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
ProblemReport.belongsTo(User, { foreignKey: 'customerId', as: 'customer' });
ProblemReport.hasMany(ProblemReportNote, { foreignKey: 'reportId', as: 'notes' });
ProblemReportNote.belongsTo(ProblemReport, { foreignKey: 'reportId', as: 'report' });
ProblemReportNote.belongsTo(User, { foreignKey: 'authorId', as: 'author' });

Property.hasMany(RoomType, { foreignKey: 'listingId', as: 'roomTypes' });
RoomType.belongsTo(Property, { foreignKey: 'listingId', as: 'property' });
Property.hasMany(Floor, { foreignKey: 'propertyId', as: 'floors' });
Floor.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
Property.hasMany(Room, { foreignKey: 'propertyId', as: 'rooms' });
Room.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
Floor.hasMany(Room, { foreignKey: 'floorId', as: 'rooms' });
Room.belongsTo(Floor, { foreignKey: 'floorId', as: 'floor' });
RoomType.hasMany(Booking, { foreignKey: 'roomTypeId', as: 'bookings' });
Booking.belongsTo(RoomType, { foreignKey: 'roomTypeId', as: 'roomType' });

RoomType.hasMany(Room, { foreignKey: 'roomTypeId', as: 'rooms' });
Room.belongsTo(RoomType, { foreignKey: 'roomTypeId', as: 'roomType' });
Room.hasMany(Booking, { foreignKey: 'assignedRoomId', as: 'bookings' });
Booking.belongsTo(Room, { foreignKey: 'assignedRoomId', as: 'assignedRoom' });
Room.hasMany(RoomAvailabilityBlock, { foreignKey: 'roomId', as: 'availabilityBlocks' });
RoomAvailabilityBlock.belongsTo(Room, { foreignKey: 'roomId', as: 'room' });
Property.hasMany(ApartmentAvailabilityBlock, { foreignKey: 'propertyId', as: 'apartmentBlocks' });
ApartmentAvailabilityBlock.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
Room.hasMany(WalkInReservation, { foreignKey: 'roomId', as: 'walkIns' });
WalkInReservation.belongsTo(Room, { foreignKey: 'roomId', as: 'room' });
WalkInReservation.belongsTo(Property, { foreignKey: 'propertyId', as: 'property' });
WalkInReservation.belongsTo(RoomType, { foreignKey: 'roomTypeId', as: 'roomType' });
WalkInReservation.hasMany(WalkInRoomSegment, { foreignKey: 'walkInReservationId', as: 'roomSegments' });
WalkInRoomSegment.belongsTo(WalkInReservation, { foreignKey: 'walkInReservationId', as: 'reservation' });
WalkInRoomSegment.belongsTo(Room, { foreignKey: 'roomId', as: 'room' });

RoomType.hasMany(RoomInventory, { foreignKey: 'roomTypeId', as: 'inventory' });
RoomInventory.belongsTo(RoomType, { foreignKey: 'roomTypeId', as: 'roomType' });

Property.hasOne(CheckInPolicy, { foreignKey: 'listingId', as: 'checkInPolicy' });
CheckInPolicy.belongsTo(Property, { foreignKey: 'listingId', as: 'property' });

Booking.hasMany(GuestMessage, { foreignKey: 'bookingId', as: 'messages' });
GuestMessage.belongsTo(Booking, { foreignKey: 'bookingId', as: 'booking' });

User.hasMany(GuestMessage, { foreignKey: 'senderId', as: 'sentMessages' });
GuestMessage.belongsTo(User, { foreignKey: 'senderId', as: 'sender' });

Property.hasMany(RentalMessage, { foreignKey: 'listingId', as: 'rentalMessages' });
RentalMessage.belongsTo(Property, { foreignKey: 'listingId', as: 'property' });
User.hasMany(RentalMessage, { foreignKey: 'customerId', as: 'rentalConversations' });
RentalMessage.belongsTo(User, { foreignKey: 'customerId', as: 'customer' });
User.hasMany(RentalMessage, { foreignKey: 'senderId', as: 'sentRentalMessages' });
RentalMessage.belongsTo(User, { foreignKey: 'senderId', as: 'sender' });

User.hasMany(Notification, { foreignKey: 'userId', as: 'notifications' });
User.hasMany(AgentWorkspace, { foreignKey: 'userId', as: 'workspaces' });
AgentWorkspace.belongsTo(User, { foreignKey: 'userId', as: 'user' });
BookingReceipt.belongsTo(Booking, { foreignKey: 'bookingId', as: 'booking' });
BookingReceipt.belongsTo(PaymentTransaction, { foreignKey: 'paymentTransactionId', as: 'transaction' });
Notification.belongsTo(User, { foreignKey: 'userId', as: 'user' });

const addMissingColumns = async (table, definitions) => {
  const queryInterface = sequelize.getQueryInterface();
  const columns = await queryInterface.describeTable(table);
  for (const [name, definition] of Object.entries(definitions)) {
    if (!columns[name]) await queryInterface.addColumn(table, name, definition);
  }
};

const ensureReviewSystemColumns = async () => {
  await addMissingColumns('Reviews', {
    comfort: { type: DataTypes.INTEGER, allowNull: true },
    amenities: { type: DataTypes.INTEGER, allowNull: true },
    images: { type: DataTypes.JSON, allowNull: true },
    agentResponse: { type: DataTypes.STRING(1500), allowNull: true },
    agentResponseAt: { type: DataTypes.DATE, allowNull: true },
    agentResponderId: { type: DataTypes.UUID, allowNull: true },
    publishedAt: { type: DataTypes.DATE, allowNull: true }
  });
  await sequelize.query('UPDATE Reviews SET publishedAt = createdAt WHERE publishedAt IS NULL AND status = \'published\'');
  const bookingColumns = await sequelize.getQueryInterface().describeTable('Bookings');
  if (!bookingColumns.checkedOutAt) {
    await sequelize.getQueryInterface().addColumn('Bookings', 'checkedOutAt', {
      type: DataTypes.DATE,
      allowNull: true
    });
    // Stays completed before verified checkout existed keep their eligibility.
    await sequelize.query('UPDATE Bookings SET checkedOutAt = updatedAt WHERE status = \'completed\' AND checkedOutAt IS NULL');
  }
};

const ensureAlertAndTenancyColumns = async () => {
  await addMissingColumns('Notifications', {
    type: { type: DataTypes.STRING(50), allowNull: true },
    category: { type: DataTypes.STRING(30), allowNull: false, defaultValue: 'general' },
    priority: { type: DataTypes.STRING(20), allowNull: false, defaultValue: 'normal' },
    propertyId: { type: DataTypes.UUID, allowNull: true },
    bookingId: { type: DataTypes.UUID, allowNull: true },
    dedupeKey: { type: DataTypes.STRING(250), allowNull: true },
    channels: { type: DataTypes.JSON, allowNull: true },
    readAt: { type: DataTypes.DATE, allowNull: true }
  });
  await sequelize.query(
    'CREATE UNIQUE INDEX IF NOT EXISTS notifications_user_dedupe ON Notifications (userId, dedupeKey)'
  );
  await addMissingColumns('RentObligations', {
    tenantUserId: { type: DataTypes.UUID, allowNull: true },
    tenancyEndedAt: { type: DataTypes.DATE, allowNull: true },
    leaseEndDate: { type: DataTypes.DATEONLY, allowNull: true },
    reminderOffsets: { type: DataTypes.JSON, allowNull: true }
  });
};

const syncDatabase = async () => {
  await sequelize.authenticate();
  await sequelize.query('PRAGMA foreign_keys = ON');
  await sequelize.sync();
  await ensureRoomInventoryDateUniqueness();
  await ensurePropertyLocationColumns();
  await ensureReviewSystemColumns();
  await ensureAlertAndTenancyColumns();
  await addMissingColumns('Properties', {
    accommodationType: { type: DataTypes.STRING(30), allowNull: true },
    amenityDetails: { type: DataTypes.JSON, allowNull: false, defaultValue: [] }
  });
  await addMissingColumns('RoomTypes', {
    currency: { type: DataTypes.STRING(3), allowNull: false, defaultValue: 'TZS' },
    amenityDetails: { type: DataTypes.JSON, allowNull: false, defaultValue: [] },
    imageUrls: { type: DataTypes.JSON, allowNull: false, defaultValue: [] },
    primaryImageUrl: { type: DataTypes.STRING, allowNull: true },
    bedType: { type: DataTypes.STRING(80), allowNull: true },
    numberOfBeds: { type: DataTypes.INTEGER, allowNull: true },
    bathroomType: { type: DataTypes.STRING(80), allowNull: true },
    sizeSqm: { type: DataTypes.FLOAT, allowNull: true }
  });
  await addMissingColumns('Bookings', {
    assignedRoomId: { type: DataTypes.UUID, allowNull: true },
    holdExpiresAt: { type: DataTypes.DATE, allowNull: true }
  });
  const legacyWalkIns = await WalkInReservation.findAll({
    include: [{ model: WalkInRoomSegment, as: 'roomSegments', attributes: ['id'] }]
  });
  for (const stay of legacyWalkIns) {
    if (stay.roomSegments.length === 0) {
      await WalkInRoomSegment.create({
        walkInReservationId: stay.id,
        roomId: stay.roomId,
        startAt: stay.checkIn,
        endAt: stay.checkOut
      });
    }
  }
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
  Floor,
  Room,
  RoomAvailabilityBlock,
  ApartmentAvailabilityBlock,  WalkInReservation,
  WalkInRoomSegment,
  CheckInPolicy,
  GuestMessage,
  RentalMessage,
  Notification,
  BusinessConfiguration,
  SavedProperty,
  AdminAuditEvent,
  Review,
  ReviewReport,
  AgentProfile,
  ProblemReport,
  ProblemReportNote,
  RentObligation,
  RentReceipt,
  PropertyExpense,
  UtilityBill,
  StaffObligation,
  FinancialAlert,
  FinancialPayment,
  AgentWorkspace,
  NotificationPreference,
  BookingReceipt
};
