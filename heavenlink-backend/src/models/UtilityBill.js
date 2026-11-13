const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const UtilityBill = sequelize.define('UtilityBill', {
  id: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  propertyId: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  unitReference: { type: DataTypes.STRING(100), allowNull: true },
  category: {
    type: DataTypes.ENUM('electricity', 'water', 'internet', 'tv', 'streaming', 'gas', 'waste', 'security', 'serviceCharge', 'other'),
    allowNull: false
  },
  provider: { type: DataTypes.STRING(200), allowNull: false },
  billingMonth: { type: DataTypes.STRING(7), allowNull: false },
  amountTzs: { type: DataTypes.INTEGER, allowNull: false },
  paidTzs: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  dueDate: { type: DataTypes.DATEONLY, allowNull: false },
  paidDate: { type: DataTypes.DATEONLY, allowNull: true },
  paymentMethod: { type: DataTypes.STRING(100), allowNull: true },
  reference: { type: DataTypes.STRING(200), allowNull: true },
  notes: { type: DataTypes.STRING(1000), allowNull: true },
  recurring: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false },
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
  indexes: [{ fields: ['propertyId', 'dueDate'] }, { fields: ['propertyId', 'billingMonth'] }]
});

module.exports = UtilityBill;
