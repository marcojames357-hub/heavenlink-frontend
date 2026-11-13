const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const RentalMessage = sequelize.define('RentalMessage', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  listingId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  customerId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  senderId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  body: {
    type: DataTypes.TEXT,
    allowNull: false,
    validate: { len: [1, 2000] }
  },
  readAt: {
    type: DataTypes.DATE,
    allowNull: true
  }
}, {
  timestamps: true,
  indexes: [
    { fields: ['listingId', 'customerId', 'createdAt'] },
    { fields: ['senderId'] }
  ]
});

module.exports = RentalMessage;
