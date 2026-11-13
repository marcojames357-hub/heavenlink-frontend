const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const FinancialPayment = sequelize.define('FinancialPayment', {
  id: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  propertyId: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  recordType: {
    type: DataTypes.ENUM('propertyExpense', 'utilityBill', 'staffObligation'),
    allowNull: false
  },
  recordId: { type: DataTypes.UUID, allowNull: false },
  amountTzs: { type: DataTypes.INTEGER, allowNull: false },
  paymentDate: { type: DataTypes.DATEONLY, allowNull: false },
  method: { type: DataTypes.STRING(100), allowNull: true },
  reference: { type: DataTypes.STRING(200), allowNull: true },
  createdById: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  idempotencyKey: { type: DataTypes.STRING(200), allowNull: false },
  reversedAt: { type: DataTypes.DATE, allowNull: true },
  reversedById: {
    type: DataTypes.UUID, allowNull: true,
    references: { model: 'Users', key: 'id' }
  },
  reversalReason: { type: DataTypes.STRING(500), allowNull: true }
}, {
  indexes: [
    { fields: ['propertyId', 'recordType', 'recordId'] },
    { fields: ['createdById', 'idempotencyKey'], unique: true },
    { fields: ['paymentDate'] }
  ]
});

module.exports = FinancialPayment;
