const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const CheckInPolicy = sequelize.define('CheckInPolicy', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  listingId: {
    type: DataTypes.UUID,
    allowNull: false,
    unique: true,
    references: {
      model: 'Properties',
      key: 'id'
    }
  },
  checkInFrom: {
    type: DataTypes.STRING,
    defaultValue: '14:00',
    validate: {
      is: /^([01]?[0-9]|2[0-3]):[0-5][0-9]$/
    }
  },
  checkOutBy: {
    type: DataTypes.STRING,
    defaultValue: '11:00',
    validate: {
      is: /^([01]?[0-9]|2[0-3]):[0-5][0-9]$/
    }
  },
  cancellationHours: {
    type: DataTypes.INTEGER,
    defaultValue: 24,
    validate: {
      min: 0,
      max: 168
    }
  },
  allowLateCheckout: {
    type: DataTypes.BOOLEAN,
    defaultValue: false
  },
  notes: {
    type: DataTypes.TEXT,
    allowNull: true
  }
}, {
  timestamps: true,
  indexes: [
    {
      unique: true,
      fields: ['listingId']
    }
  ]
});

module.exports = CheckInPolicy;
