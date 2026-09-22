const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const OwnerContact = sequelize.define('OwnerContact', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  propertyId: {
    type: DataTypes.UUID,
    allowNull: false,
    unique: true,
    references: {
      model: 'Properties',
      key: 'id'
    }
  },
  exactAddress: {
    type: DataTypes.TEXT,
    allowNull: false,
    validate: {
      len: [5, 500]
    }
  },
  contactName: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      len: [2, 100]
    }
  },
  role: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      len: [2, 100]
    }
  },
  phone: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      is: /^\+255\d{9}$/
    }
  },
  whatsApp: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      is: /^\+255\d{9}$/
    }
  },
  latitude: {
    type: DataTypes.FLOAT,
    allowNull: false,
    validate: {
      min: -90,
      max: 90
    }
  },
  longitude: {
    type: DataTypes.FLOAT,
    allowNull: false,
    validate: {
      min: -180,
      max: 180
    }
  }
}, {
  timestamps: true,
  indexes: [
    {
      fields: ['propertyId'],
      unique: true
    }
  ]
});

module.exports = OwnerContact;
