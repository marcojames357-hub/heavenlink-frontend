const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const RoomAvailabilityBlock = sequelize.define('RoomAvailabilityBlock', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  roomId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Rooms', key: 'id' }
  },
  startDate: {
    type: DataTypes.DATEONLY,
    allowNull: false
  },
  endDate: {
    type: DataTypes.DATEONLY,
    allowNull: false
  },
  reason: {
    type: DataTypes.STRING(500),
    allowNull: false
  }
}, {
  timestamps: true,
  indexes: [{ fields: ['roomId', 'startDate', 'endDate'] }]
});

module.exports = RoomAvailabilityBlock;
