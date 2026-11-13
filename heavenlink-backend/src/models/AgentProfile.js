const { DataTypes } = require('sequelize');
const sequelize = require('../config/database');

const AgentProfile = sequelize.define('AgentProfile', {
  userId: {
    type: DataTypes.UUID,
    primaryKey: true,
    references: {
      model: 'Users',
      key: 'id'
    }
  },
  agencyName: {
    type: DataTypes.STRING(100),
    allowNull: false,
    defaultValue: ''
  },
  bio: {
    type: DataTypes.STRING(500),
    allowNull: false,
    defaultValue: ''
  },
  photoUrl: {
    type: DataTypes.STRING(1000),
    allowNull: false,
    defaultValue: ''
  },
  videoUrl: {
    type: DataTypes.STRING(1000),
    allowNull: false,
    defaultValue: ''
  },
  serviceAreas: {
    type: DataTypes.JSON,
    allowNull: false,
    defaultValue: []
  }
}, {
  timestamps: true
});

module.exports = AgentProfile;
