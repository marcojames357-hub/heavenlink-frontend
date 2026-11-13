const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const Room = sequelize.define('Room', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  propertyId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  floorId: {
    type: DataTypes.UUID,
    allowNull: true,
    references: { model: 'Floors', key: 'id' }
  },
  roomTypeId: {
    type: DataTypes.UUID,
    allowNull: true,
    references: { model: 'RoomTypes', key: 'id' }
  },
  roomNumber: {
    type: DataTypes.STRING(40),
    allowNull: false
  },
  status: {
    type: DataTypes.ENUM('active', 'outOfService'),
    allowNull: false,
    defaultValue: 'active'
  },
  overrides: {
    type: DataTypes.JSON,
    allowNull: false,
    defaultValue: {}
  }
}, {
  timestamps: true,
  indexes: [
    { unique: true, fields: ['propertyId', 'roomNumber'] },
    { fields: ['roomTypeId', 'status'] },
    { fields: ['floorId'] }
  ]
});

module.exports = Room;
