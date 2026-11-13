const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const RentObligation = sequelize.define('RentObligation', {
  id: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  propertyId: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  unitReference: { type: DataTypes.STRING(100), allowNull: false },
  tenantReference: { type: DataTypes.STRING(200), allowNull: true },
  billingMonth: { type: DataTypes.STRING(7), allowNull: false },
  expectedTzs: { type: DataTypes.INTEGER, allowNull: false },
  dueDate: { type: DataTypes.DATEONLY, allowNull: false },
  // Set only when an agent links a verified Haven Link account to this tenancy.
  tenantUserId: { type: DataTypes.UUID, allowNull: true, references: { model: 'Users', key: 'id' } },
  tenancyEndedAt: { type: DataTypes.DATE, allowNull: true },
  leaseEndDate: { type: DataTypes.DATEONLY, allowNull: true },
  reminderOffsets: { type: DataTypes.JSON, allowNull: true },
  createdById: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Users', key: 'id' }
  }
}, {
  indexes: [
    { fields: ['propertyId', 'billingMonth', 'unitReference'], unique: true },
    { fields: ['propertyId', 'dueDate'] }
  ]
});

module.exports = RentObligation;
