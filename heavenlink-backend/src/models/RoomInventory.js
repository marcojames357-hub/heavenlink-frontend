const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const RoomInventory = sequelize.define('RoomInventory', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  roomTypeId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'RoomTypes',
      key: 'id'
    }
  },
  date: {
    type: DataTypes.DATEONLY,
    allowNull: false
  },
  booked: {
    type: DataTypes.INTEGER,
    defaultValue: 0,
    validate: {
      min: 0
    }
  },
  totalOverride: {
    type: DataTypes.INTEGER,
    allowNull: true,
    validate: {
      min: 0
    }
  }
}, {
  timestamps: true,
  indexes: [
    {
      unique: true,
      fields: ['roomTypeId', 'date']
    },
    {
      fields: ['date']
    }
  ]
});

// Instance methods
RoomInventory.prototype.totalFor = function(roomType) {
  return this.totalOverride !== null ? this.totalOverride : roomType.totalRooms;
};

RoomInventory.prototype.availableFor = function(roomType) {
  const total = this.totalFor(roomType);
  return Math.max(0, total - this.booked);
};

module.exports = RoomInventory;
