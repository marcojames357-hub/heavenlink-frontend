const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const SavedProperty = sequelize.define('SavedProperty', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  customerId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Users', key: 'id' }
  },
  listingId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Properties', key: 'id' }
  }
}, {
  timestamps: true,
  indexes: [{ unique: true, fields: ['customerId', 'listingId'] }]
});

module.exports = SavedProperty;