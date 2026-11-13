const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const StaffObligation = sequelize.define('StaffObligation', {
  id: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  propertyId: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  staffName: { type: DataTypes.STRING(200), allowNull: false },
  staffRole: { type: DataTypes.STRING(100), allowNull: false },
  frequency: {
    type: DataTypes.ENUM('monthly', 'weekly', 'daily', 'oneTime'), allowNull: false
  },
  amountTzs: { type: DataTypes.INTEGER, allowNull: false },
  paidTzs: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  dueDate: { type: DataTypes.DATEONLY, allowNull: false },
  paidDate: { type: DataTypes.DATEONLY, allowNull: true },
  paymentMethod: { type: DataTypes.STRING(100), allowNull: true },
  reference: { type: DataTypes.STRING(200), allowNull: true },
  createdById: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  reversedAt: { type: DataTypes.DATE, allowNull: true },
  reversedById: {
    type: DataTypes.UUID, allowNull: true,
    references: { model: 'Users', key: 'id' }
  },
  reversalReason: { type: DataTypes.STRING(500), allowNull: true }
}, {
  indexes: [{ fields: ['propertyId', 'dueDate'] }]
});

module.exports = StaffObligation;
