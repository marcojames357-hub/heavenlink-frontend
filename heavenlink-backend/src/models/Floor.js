const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const Floor = sequelize.define('Floor', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  propertyId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: { model: 'Properties', key: 'id' }
  },
  label: {
    type: DataTypes.STRING(80),
    allowNull: false
  },
  sortOrder: {
    type: DataTypes.INTEGER,
    allowNull: false,
    defaultValue: 0
  }
}, {
  timestamps: true,
  indexes: [{ fields: ['propertyId', 'sortOrder'] }]
});

module.exports = Floor;
