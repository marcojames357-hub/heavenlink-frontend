const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const BusinessConfiguration = sequelize.define('BusinessConfiguration', {
  id: {
    type: DataTypes.INTEGER,
    primaryKey: true,
    defaultValue: 1
  },
  unlockFeeTzs: {
    type: DataTypes.INTEGER,
    allowNull: false,
    defaultValue: Number.parseInt(process.env.DEFAULT_UNLOCK_FEE_TZS, 10) || 5000,
    validate: { min: 500, max: 50000 }
  },
  bookingFeeRate: {
    type: DataTypes.FLOAT,
    allowNull: false,
    defaultValue: Number.parseFloat(process.env.BOOKING_FEE_RATE) || 0.02,
    validate: { min: 0, max: Number.parseFloat(process.env.MAX_BOOKING_FEE_RATE) || 0.25 }
  }
}, {
  timestamps: true
});

module.exports = BusinessConfiguration;