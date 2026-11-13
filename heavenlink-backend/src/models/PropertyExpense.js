const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const PropertyExpense = sequelize.define('PropertyExpense', {
  id: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  propertyId: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  unitReference: { type: DataTypes.STRING(100), allowNull: true },
  title: { type: DataTypes.STRING(200), allowNull: false },
  category: {
    type: DataTypes.ENUM('maintenance', 'cleaning', 'security', 'supplies', 'administration', 'other'),
    allowNull: false
  },
  amountTzs: { type: DataTypes.INTEGER, allowNull: false },
  expenseDate: { type: DataTypes.DATEONLY, allowNull: false },
  paidTzs: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  paymentMethod: { type: DataTypes.STRING(100), allowNull: true },
  description: { type: DataTypes.STRING(1000), allowNull: true },
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
  indexes: [{ fields: ['propertyId', 'expenseDate'] }, { fields: ['category'] }]
});

module.exports = PropertyExpense;
