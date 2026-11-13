const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const RoomType = sequelize.define('RoomType', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  listingId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'Properties',
      key: 'id'
    }
  },
  name: {
    type: DataTypes.STRING,
    allowNull: false,
    validate: {
      len: [2, 100]
    }
  },
  nightlyPriceTzs: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 0
    }
  },
  currency: {
    type: DataTypes.STRING(3),
    allowNull: false,
    defaultValue: 'TZS'
  },
  capacity: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 1,
      max: 20
    }
  },
  totalRooms: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: 1
    }
  },
  amenities: {
    type: DataTypes.JSON,
    defaultValue: []
  },
  amenityDetails: {
    type: DataTypes.JSON,
    allowNull: false,
    defaultValue: []
  },
  imageUrls: {
    type: DataTypes.JSON,
    allowNull: false,
    defaultValue: []
  },
  primaryImageUrl: {
    type: DataTypes.STRING,
    allowNull: true
  },
  bedType: {
    type: DataTypes.STRING(80),
    allowNull: true
  },
  numberOfBeds: {
    type: DataTypes.INTEGER,
    allowNull: true,
    validate: { min: 1 }
  },
  bathroomType: {
    type: DataTypes.STRING(80),
    allowNull: true
  },
  sizeSqm: {
    type: DataTypes.FLOAT,
    allowNull: true,
    validate: { min: 0 }
  },
  description: {
    type: DataTypes.TEXT,
    allowNull: true
  }
}, {
  timestamps: true,
  indexes: [
    {
      fields: ['listingId']
    }
  ]
});

module.exports = RoomType;
