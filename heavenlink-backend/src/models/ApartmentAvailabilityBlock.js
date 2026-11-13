const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

// Host-blocked dates for a whole-unit apartment. endDate is exclusive.
const ApartmentAvailabilityBlock = sequelize.define('ApartmentAvailabilityBlock', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  propertyId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  startDate: { type: DataTypes.DATEONLY, allowNull: false },
  endDate: { type: DataTypes.DATEONLY, allowNull: false },
  reason: { type: DataTypes.STRING(500), allowNull: false }
}, {
  timestamps: true,
  indexes: [{ fields: ['propertyId', 'startDate', 'endDate'] }]
});

module.exports = ApartmentAvailabilityBlock;
