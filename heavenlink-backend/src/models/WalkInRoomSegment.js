const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const WalkInRoomSegment = sequelize.define('WalkInRoomSegment', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  walkInReservationId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'WalkInReservations', key: 'id' }
  },
  roomId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Rooms', key: 'id' }
  },
  startAt: { type: DataTypes.DATE, allowNull: false },
  endAt: { type: DataTypes.DATE, allowNull: false }
}, {
  timestamps: true,
  indexes: [
    { fields: ['walkInReservationId', 'startAt'] },
    { fields: ['roomId', 'startAt', 'endAt'] }
  ]
});

module.exports = WalkInRoomSegment;
