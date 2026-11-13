const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const FinancialAlert = sequelize.define('FinancialAlert', {
  id: { type: DataTypes.UUID, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  ownerId: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  propertyId: {
    type: DataTypes.UUID, allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  alertKey: { type: DataTypes.STRING(200), allowNull: false },
  recordType: { type: DataTypes.STRING(80), allowNull: false },
  recordId: { type: DataTypes.UUID, allowNull: false },
  title: { type: DataTypes.STRING(200), allowNull: false },
  description: { type: DataTypes.STRING(1000), allowNull: false },
  severity: { type: DataTypes.ENUM('informational', 'warning', 'critical'), allowNull: false },
  isRead: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false },
  resolvedAt: { type: DataTypes.DATE, allowNull: true }
}, {
  indexes: [
    { fields: ['ownerId', 'resolvedAt', 'createdAt'] },
    { fields: ['propertyId', 'resolvedAt'] },
    { fields: ['propertyId', 'alertKey'], unique: true }
  ]
});

module.exports = FinancialAlert;
