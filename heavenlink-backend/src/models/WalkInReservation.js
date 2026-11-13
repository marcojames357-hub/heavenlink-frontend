const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const WalkInReservation = sequelize.define('WalkInReservation', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  propertyId: { type: DataTypes.UUID, allowNull: false, references: { model: 'Properties', key: 'id' } },
  roomId: { type: DataTypes.UUID, allowNull: false, references: { model: 'Rooms', key: 'id' } },
  roomTypeId: { type: DataTypes.UUID, allowNull: false, references: { model: 'RoomTypes', key: 'id' } },
  createdById: { type: DataTypes.UUID, allowNull: false, references: { model: 'Users', key: 'id' } },
  requestKey: { type: DataTypes.STRING(200), allowNull: false, unique: true },
  requestFingerprint: { type: DataTypes.STRING(64), allowNull: false },
  guestName: { type: DataTypes.STRING(100), allowNull: false },
  guestPhone: { type: DataTypes.STRING(40), allowNull: true },
  checkIn: { type: DataTypes.DATE, allowNull: false },
  checkOut: { type: DataTypes.DATE, allowNull: false },
  checkedInAt: { type: DataTypes.DATE, allowNull: true },
  checkedOutAt: { type: DataTypes.DATE, allowNull: true },
  priceTzs: { type: DataTypes.INTEGER, allowNull: false, validate: { min: 0 } },
  paymentStatus: { type: DataTypes.ENUM('unpaid', 'partiallyPaid', 'paid'), allowNull: false },
  notes: { type: DataTypes.STRING(1000), allowNull: true },
  status: { type: DataTypes.ENUM('reserved', 'checkedIn', 'completed', 'cancelled'), allowNull: false }
}, {
  timestamps: true,
  indexes: [
    { fields: ['propertyId', 'status'] },
    { fields: ['roomId', 'checkIn', 'checkOut'] }
  ]
});

module.exports = WalkInReservation;
