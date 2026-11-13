const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const RentReceipt = sequelize.define('RentReceipt', {
  id: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  obligationId: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'RentObligations', key: 'id' }
  },
  amountTzs: { type: DataTypes.INTEGER, allowNull: false },
  paymentDate: { type: DataTypes.DATEONLY, allowNull: false },
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
    { fields: ['obligationId'] },
    { fields: ['createdById', 'idempotencyKey'], unique: true }
  ]
});

module.exports = RentReceipt;
